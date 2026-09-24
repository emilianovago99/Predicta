"""Compact incidents and persistent, coalescing Telegram delivery."""
import base64
import hashlib
import html
import json
import logging
import os
import uuid
from datetime import datetime, timedelta

import requests
from cryptography.fernet import Fernet
from database import conectar_db

METRICS = [('temperatura', 'temp', 'Motor', '°C'),
           ('temp_ambiente', 'temp_amb', 'Ambiente', '°C'),
           ('vibracion', 'vib', 'Vibración', 'mm/s'),
           ('voltaje', 'volt', 'Voltaje', 'V'),
           ('velocidad', 'vel', 'Velocidad', 'rpm'),
           ('humedad', 'hum', 'Humedad', '%')]


def cipher():
    return Fernet(base64.urlsafe_b64encode(hashlib.sha256(os.environ['JWT_SECRET'].encode()).digest()))


def summarize(reading, limits, event=False, prediction=None, edge_kind=None):
    metrics = []
    severity = 0
    for field, flag, label, unit in METRICS:
        if not limits.get('medir_' + flag, True) or field not in reading:
            continue
        value = float(reading[field])
        warning = float(limits.get(flag + '_alerta', float('inf')))
        danger = float(limits.get(flag + '_peligro', float('inf')))
        level = 2 if value >= danger else 1 if value >= warning else 0
        if level:
            severity = max(severity, level)
            metrics.append({'label': label, 'value': round(value, 2), 'unit': unit,
                            'limit': danger if level == 2 else warning, 'severity': level})
    metrics.sort(key=lambda m: -m['severity'])
    kind = 'critico' if severity == 2 else 'umbral'
    title = 'Límite crítico superado' if severity == 2 else 'Medición fuera de rango'
    action = 'Revisa el equipo y aplica el protocolo de parada de tu planta.' if severity == 2 else 'Inspecciona el sensor indicado y programa una revisión.'
    if not severity:
        if event or edge_kind == 'evento':
            severity, kind, title = 1, 'evento', 'Cambio brusco detectado'
            action = 'Comprueba alimentación, carga y paradas del equipo.'
        elif (prediction or {}).get('requiere_alerta_preventiva') or edge_kind:
            severity, kind, title = 1, 'predictivo', 'Tendencia que requiere revisión'
            action = 'Revisa la tendencia y programa mantenimiento.'
        else:
            kind, title, action = 'recuperado', 'Mediciones en rango', 'Continúa el monitoreo.'
    return dict(severity=severity, tipo=kind, title=title, action=action, metrics=metrics[:3])


def record_incident(cursor, machine_id, payload, cooldown=900):
    """Caller holds the Maquina row lock; incident/history/outbox share its transaction."""
    now = datetime.utcnow()
    cursor.execute('SELECT * FROM MachineAlert WHERE id_maquina=%s FOR UPDATE', (machine_id,))
    previous = cursor.fetchone()
    severity = payload['severity']
    if not severity:
        if not previous or not previous['severity']:
            return
        count = previous['normal_count'] + 1
        if count < 3:
            cursor.execute('UPDATE MachineAlert SET normal_count=%s WHERE id_maquina=%s', (count, machine_id))
            return
    # Avoid oscillation/edge duplicates downgrading an active critical incident.
    if previous and severity and severity < previous['severity']:
        count = previous['normal_count'] + 1
        if count < 3:
            cursor.execute('UPDATE MachineAlert SET normal_count=%s WHERE id_maquina=%s', (count, machine_id))
            return
    new_episode = previous is None or (previous['severity'] == 0 and severity > 0)
    changed = previous is None or severity != previous['severity']
    emit = changed or (now - previous['emitted_at']).total_seconds() >= cooldown
    episode = uuid.uuid4().hex if new_episode else previous['episode']
    occurrences = 1 if new_episode else previous['occurrences'] + 1
    payload = {**payload, 'episode': episode, 'occurrences': occurrences,
               'fecha': now.isoformat() + 'Z', 'active': severity > 0}
    pending_payload = (previous or {}).get('pending_payload')
    pending_revision = (previous or {}).get('pending_revision')
    if emit:
        # A recovery/downgrade must not replace an unsent warning or critical event.
        # A new revision also protects events that arrive during Telegram's HTTP call.
        if not pending_payload or severity >= json.loads(pending_payload)['severity']:
            pending_payload = json.dumps(payload)
        pending_revision = uuid.uuid4().hex
    cursor.execute('INSERT INTO MachineAlert (id_maquina,episode,severity,kind,payload,occurrences,normal_count,updated_at,emitted_at,pending) '
                   'VALUES (%s,%s,%s,%s,%s,%s,0,%s,%s,%s) ON DUPLICATE KEY UPDATE '
                   'episode=VALUES(episode),severity=VALUES(severity),kind=VALUES(kind),payload=VALUES(payload),'
                   'occurrences=VALUES(occurrences),normal_count=0,updated_at=VALUES(updated_at),'
                   'emitted_at=VALUES(emitted_at),pending=(pending OR VALUES(pending))',
                   (machine_id, episode, severity, payload['tipo'], json.dumps(payload), occurrences, now,
                    now if emit else previous['emitted_at'], emit))
    if emit:
        cursor.execute('UPDATE MachineAlert SET pending_payload=%s,pending_revision=%s WHERE id_maquina=%s',
                       (pending_payload, pending_revision, machine_id))
    if emit and severity:
        cursor.execute('INSERT INTO Alertas (id_maquina,riesgo,diagnostico,tipo) VALUES (%s,%s,%s,%s)',
                       (machine_id, 95 if severity == 2 else 60,
                        payload['title'] + '. ' + payload['action'],
                        payload['tipo'] if payload['tipo'] != 'umbral' else 'predictivo'))


def delivery_payload(row):
    return json.loads(row.get('pending_payload') or row['payload'])


def telegram_text(rows):
    blocks = []
    for row in rows:
        p = delivery_payload(row)
        current = json.loads(row['payload'])
        icon = '🔴' if p['severity'] == 2 else '🟠' if p['severity'] else '🟢'
        lines = [f"{icon} <b>{html.escape(row['nombre'])}</b> · {html.escape(row['id_maquina'])}",
                 html.escape(p['title'])]
        for m in p['metrics']:
            lines.append(html.escape(f"{m['label']}: {m['value']:g} {m['unit']} · límite {m['limit']:g}"))
        if current['severity'] != p['severity']:
            state = {0: '🟢 En rango', 1: '🟠 Alerta', 2: '🔴 Peligro'}[current['severity']]
            lines.append('Estado actual: ' + state)
        action = ('El equipo volvió a rango; revisa la causa del incidente.'
                  if p['severity'] and not current['severity'] else p['action'])
        lines.append(html.escape(action))
        lines.append(html.escape(p['fecha'][:19].replace('T', ' ') + ' UTC'))
        blocks.append('\n'.join(lines))
    return '<b>PREDICTA · Estado de equipos</b>\n\n' + '\n\n'.join(blocks)


def deliver_pending():
    """One digest/60s/channel, at most five machines; retries respect Telegram 429.

    Advisory locks serialize workers for each unique bot/chat destination. Network I/O
    happens outside the telemetry transaction. Never log tokens or Telegram URLs.
    """
    db = conectar_db()
    c = db.cursor(dictionary=True)
    try:
        c.execute('SELECT id FROM TelegramChannel WHERE enabled=1 AND (next_send_at IS NULL OR next_send_at<=UTC_TIMESTAMP())')
        channel_ids = [r['id'] for r in c.fetchall()]
        db.commit()
        for channel_id in channel_ids:
            lock = 'telegram:' + str(channel_id)
            c.execute('SELECT GET_LOCK(%s,0) AS ok', (lock,))
            if c.fetchone()['ok'] != 1:
                continue
            try:
                c.execute('SELECT * FROM TelegramChannel WHERE id=%s AND enabled=1 AND (next_send_at IS NULL OR next_send_at<=UTC_TIMESTAMP())', (channel_id,))
                channel = c.fetchone()
                if not channel:
                    continue
                c.execute('SELECT a.*,m.nombre FROM MachineAlert a JOIN Maquina m ON m.id_maquina=a.id_maquina '
                          'JOIN Area ar ON ar.id_area=m.id_area WHERE m.telegram_channel_id=%s AND ar.id_empresa=%s AND a.pending=1 '
                          "ORDER BY COALESCE(JSON_EXTRACT(a.pending_payload,'$.severity'),a.severity) DESC,a.emitted_at LIMIT 5",
                          (channel_id, channel['id_empresa']))
                rows = c.fetchall()
                if not rows:
                    continue
                db.commit()
                delay, status, success = 60, 'Error de conexión; se reintentará', False
                try:
                    token = cipher().decrypt(channel['token_encrypted'].encode()).decode()
                    response = requests.post(f'https://api.telegram.org/bot{token}/sendMessage',
                        json={'chat_id': channel['chat_id'], 'text': telegram_text(rows), 'parse_mode': 'HTML',
                              'disable_notification': all(delivery_payload(r)['severity'] < 2 for r in rows)}, timeout=8)
                    result = response.json()
                    success = response.ok and result.get('ok') is True
                    status = 'Entregado' if success else f'Telegram rechazó el envío ({response.status_code})'
                    if response.status_code == 429:
                        delay = max(60, min(86400, int(result.get('parameters', {}).get('retry_after', 60))))
                except Exception:
                    pass
                c.execute('UPDATE TelegramChannel SET next_send_at=%s,last_status=%s WHERE id=%s',
                          (datetime.utcnow() + timedelta(seconds=delay), status, channel_id))
                if success:
                    for row in rows:
                        c.execute('UPDATE MachineAlert SET pending=0,pending_payload=NULL,pending_revision=NULL '
                                  'WHERE id_maquina=%s AND pending_revision=%s',
                                  (row['id_maquina'], row['pending_revision']))
                db.commit()
            finally:
                c.execute('SELECT RELEASE_LOCK(%s)', (lock,))
                c.fetchone()
                db.commit()
    finally:
        c.close()
        db.close()


def notification_loop(stop):
    while not stop.wait(5):
        if os.getenv('TELEGRAM_DELIVERY_ENABLED', 'true').lower() != 'true':
            continue
        try:
            deliver_pending()
        except Exception:
            logging.getLogger(__name__).warning('No se pudo procesar la cola de notificaciones')
