"""Company-scoped Telegram destinations and one-use sensor enrollment."""
import hashlib
import os
import secrets
from datetime import datetime
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, Field, field_validator
from database import conectar_db
from notifications import cipher
import mysql.connector
from security import (bearer, token_value, require_editor, require_installer,
                      check_machine, check_company)

router = APIRouter()


class ChannelInput(BaseModel):
    id_empresa: int
    nombre: str = Field(min_length=1, max_length=100)
    bot_token: str = Field(pattern=r'^\d{5,20}:[A-Za-z0-9_-]{20,100}$')
    chat_id: str = Field(pattern=r'^-?\d{1,20}$')


class NotificationInput(BaseModel):
    channel_id: int | None = None
    cooldown_seconds: int = Field(default=900, ge=300, le=86400)


class InstallationInput(BaseModel):
    server_url: str = Field(max_length=255)

    @field_validator('server_url')
    @classmethod
    def valid_url(cls, value):
        value = value.strip().rstrip('/')
        u = urlsplit(value)
        if (u.scheme not in ('http', 'https') or not u.hostname or u.username or u.password
                or u.query or u.fragment or u.path or u.hostname in ('localhost', '127.0.0.1', '0.0.0.0', '::1')
                or (os.getenv('APP_ENV') == 'production' and u.scheme != 'https')):
            raise ValueError('Usa un origen accesible desde el sensor; HTTPS en producción')
        return value


def company_for_machine(c, machine):
    c.execute('SELECT a.id_empresa FROM Maquina m JOIN Area a ON a.id_area=m.id_area WHERE m.id_maquina=%s', (machine,))
    return c.fetchone()['id_empresa']


@router.get('/api/maquinas/{id_maquina}/notifications')
def notification_settings(id_maquina: str, user=Depends(require_editor)):
    check_machine(user, id_maquina)
    db = conectar_db()
    c = db.cursor(dictionary=True)
    try:
        company = company_for_machine(c, id_maquina)
        c.execute('SELECT telegram_channel_id AS channel_id,alert_cooldown_seconds AS cooldown_seconds FROM Maquina WHERE id_maquina=%s', (id_maquina,))
        result = c.fetchone()
        c.execute('SELECT id,nombre,chat_id,enabled,last_status FROM TelegramChannel WHERE id_empresa=%s ORDER BY nombre', (company,))
        return {**result, 'id_empresa': company, 'channels': c.fetchall()}
    finally:
        c.close()
        db.close()


@router.post('/api/telegram/channels')
def create_channel(data: ChannelInput, user=Depends(require_editor)):
    check_company(user, data.id_empresa)
    db = conectar_db()
    c = db.cursor()
    try:
        destination = hashlib.sha256((data.bot_token + '/' + data.chat_id).encode()).hexdigest()
        c.execute('INSERT INTO TelegramChannel (id_empresa,nombre,token_encrypted,chat_id,destination_hash) VALUES (%s,%s,%s,%s,%s)',
                  (data.id_empresa, data.nombre.strip(), cipher().encrypt(data.bot_token.encode()).decode(), data.chat_id, destination))
        db.commit()
        return {'id': c.lastrowid, 'nombre': data.nombre.strip()}
    except mysql.connector.IntegrityError:
        raise HTTPException(409, 'Este destino ya está registrado. Selecciona el destino existente.')
    finally:
        c.close()
        db.close()


@router.put('/api/telegram/channels/{channel_id}')
def update_channel(channel_id: int, data: ChannelInput, user=Depends(require_editor)):
    db = conectar_db()
    c = db.cursor(dictionary=True)
    try:
        c.execute('SELECT id_empresa FROM TelegramChannel WHERE id=%s', (channel_id,))
        row = c.fetchone()
        if not row:
            raise HTTPException(404, 'Destino no encontrado')
        check_company(user, row['id_empresa'])
        if data.id_empresa != row['id_empresa']:
            raise HTTPException(403, 'No se puede mover un destino entre empresas')
        destination = hashlib.sha256((data.bot_token + '/' + data.chat_id).encode()).hexdigest()
        c.execute('UPDATE TelegramChannel SET nombre=%s,token_encrypted=%s,chat_id=%s,destination_hash=%s,last_status=NULL WHERE id=%s',
                  (data.nombre.strip(), cipher().encrypt(data.bot_token.encode()).decode(), data.chat_id, destination, channel_id))
        db.commit()
        return {'id': channel_id, 'nombre': data.nombre.strip()}
    except mysql.connector.IntegrityError:
        raise HTTPException(409, 'Este destino ya está registrado')
    finally:
        c.close()
        db.close()


@router.put('/api/maquinas/{id_maquina}/notifications')
def assign_channel(id_maquina: str, data: NotificationInput, user=Depends(require_editor)):
    check_machine(user, id_maquina)
    db = conectar_db()
    c = db.cursor(dictionary=True)
    try:
        company = company_for_machine(c, id_maquina)
        if data.channel_id is not None:
            c.execute('SELECT id FROM TelegramChannel WHERE id=%s AND id_empresa=%s', (data.channel_id, company))
            if not c.fetchone():
                raise HTTPException(403, 'El destino debe pertenecer a la misma empresa')
        c.execute('UPDATE Maquina SET telegram_channel_id=%s,alert_cooldown_seconds=%s WHERE id_maquina=%s',
                  (data.channel_id, data.cooldown_seconds, id_maquina))
        # Do not send historical pending incidents when enabling/changing a destination.
        c.execute('UPDATE MachineAlert SET pending=0 WHERE id_maquina=%s', (id_maquina,))
        db.commit()
        return {'status': 'Configuración guardada'}
    finally:
        c.close()
        db.close()


@router.get('/api/maquinas/{id_maquina}/installation')
def installation_status(id_maquina: str, user=Depends(require_installer)):
    check_machine(user, id_maquina)
    db = conectar_db()
    c = db.cursor(dictionary=True)
    try:
        c.execute('SELECT firmware_version,received_at,boot_id,TIMESTAMPDIFF(SECOND,received_at,UTC_TIMESTAMP()) AS age_seconds '
                  'FROM SensorData WHERE id_maquina=%s ORDER BY id_data DESC LIMIT 1', (id_maquina,))
        last = c.fetchone()
        c.execute('SELECT id_maquina,key_encrypted FROM DeviceCredential WHERE id_maquina=%s', (id_maquina,))
        credential = c.fetchone()
        device_api_key = None
        if credential and credential.get('key_encrypted'):
            device_api_key = cipher().decrypt(credential['key_encrypted'].encode()).decode()
        return {'maquina_id': id_maquina, 'provisioned': credential is not None,
                'server_url': os.getenv('DEVICE_SERVER_URL', ''), 'last_reading': last,
                'device_api_key': device_api_key,
                'connected': last is not None and last['age_seconds'] <= 30}
    finally:
        c.close()
        db.close()


@router.post('/api/maquinas/{id_maquina}/installation')
def create_installation(id_maquina: str, data: InstallationInput, user=Depends(require_installer)):
    check_machine(user, id_maquina)
    code = 'pi_' + secrets.token_urlsafe(24)
    db = conectar_db()
    c = db.cursor()
    try:
        c.execute('INSERT INTO DeviceInstallation (id_maquina,code_hash,expires_at,server_url) '
                  'VALUES (%s,%s,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 10 MINUTE),%s) ON DUPLICATE KEY UPDATE '
                  'code_hash=VALUES(code_hash),expires_at=VALUES(expires_at),server_url=VALUES(server_url)',
                  (id_maquina, hashlib.sha256(code.encode()).hexdigest(), data.server_url))
        db.commit()
        return {'maquina_id': id_maquina, 'enrollment_code': code, 'expires_in': 600,
                'server_url': data.server_url, 'enrollment_url': data.server_url + '/api/device/enroll'}
    finally:
        c.close()
        db.close()


@router.post('/api/device/enroll')
def enroll(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    code = token_value(credentials)
    if not code.startswith('pi_'):
        raise HTTPException(401, 'Código de instalación inválido o vencido')
    db = conectar_db()
    c = db.cursor(dictionary=True)
    try:
        c.execute('SELECT * FROM DeviceInstallation WHERE code_hash=%s FOR UPDATE', (hashlib.sha256(code.encode()).hexdigest(),))
        installation = c.fetchone()
        if not installation or installation['expires_at'] <= datetime.utcnow():
            raise HTTPException(401, 'Código de instalación inválido o vencido')
        key = 'pd_' + secrets.token_urlsafe(32)
        c.execute('INSERT INTO DeviceCredential (id_maquina,key_hash) VALUES (%s,%s) '
                  'ON DUPLICATE KEY UPDATE key_hash=VALUES(key_hash),rotated_at=CURRENT_TIMESTAMP',
                  (installation['id_maquina'], hashlib.sha256(key.encode()).hexdigest()))
        c.execute('DELETE FROM DeviceInstallation WHERE id_maquina=%s', (installation['id_maquina'],))
        db.commit()
        return {'maquina_id': installation['id_maquina'], 'device_api_key': key,
                'server_url': installation['server_url'], 'telemetry_path': '/api/sensores', 'interval_ms': 2000}
    finally:
        c.close()
        db.close()
