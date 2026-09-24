"""Real MariaDB regression checks; enabled only inside the disposable test stack."""
import json
import os
import unittest
import uuid
from types import SimpleNamespace
from unittest.mock import patch

from database import conectar_db
from notifications import cipher, deliver_pending, record_incident


@unittest.skipUnless(os.getenv('PREDICTA_DB_INTEGRATION') == 'true', 'Requires disposable database')
class NotificationOutboxTests(unittest.TestCase):
    def setUp(self):
        self.db = conectar_db()
        self.c = self.db.cursor(dictionary=True)
        self.machine = 'queue-test-' + uuid.uuid4().hex[:12]
        self.c.execute('SELECT id_area,id_empresa FROM Area LIMIT 1')
        area = self.c.fetchone()
        self.c.execute('INSERT INTO TelegramChannel (id_empresa,nombre,token_encrypted,chat_id) VALUES (%s,%s,%s,%s)',
                       (area['id_empresa'], 'Queue test', cipher().encrypt(b'fake-token').decode(), '-1'))
        self.channel = self.c.lastrowid
        self.c.execute('INSERT INTO Maquina (id_maquina,id_area,nombre,telegram_channel_id) VALUES (%s,%s,%s,%s)',
                       (self.machine, area['id_area'], 'Queue test machine', self.channel))
        self.db.commit()
        response = SimpleNamespace(ok=True, status_code=200, json=lambda: {'ok': True})
        patcher = patch('notifications.requests.post', return_value=response)
        self.post = patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        self.db.rollback()
        self.c.execute('DELETE FROM Maquina WHERE id_maquina=%s', (self.machine,))
        self.c.execute('DELETE FROM TelegramChannel WHERE id=%s', (self.channel,))
        self.db.commit()
        self.c.close()
        self.db.close()

    def record(self, severity):
        self.c.execute('SELECT id_maquina FROM Maquina WHERE id_maquina=%s FOR UPDATE', (self.machine,))
        self.c.fetchone()
        payload = dict(severity=severity, tipo={0: 'recuperado', 1: 'umbral', 2: 'critico'}[severity],
                       title={0: 'En rango', 1: 'Alerta', 2: 'Peligro'}[severity], action='Revisar', metrics=[])
        record_incident(self.c, self.machine, payload)
        self.db.commit()

    def incident(self):
        self.db.commit()
        self.c.execute('SELECT * FROM MachineAlert WHERE id_maquina=%s', (self.machine,))
        row = self.c.fetchone()
        self.db.commit()
        return row

    def allow_send(self):
        self.c.execute('UPDATE TelegramChannel SET next_send_at=NULL WHERE id=%s', (self.channel,))
        self.db.commit()

    def test_warning_survives_recovery_before_first_send(self):
        self.record(1)
        for _ in range(3):
            self.record(0)
        self.assertEqual(self.incident()['severity'], 0)
        deliver_pending()
        self.assertEqual(self.post.call_count, 1)
        message = self.post.call_args.kwargs['json']
        self.assertIn('🟠', message['text'])
        self.assertIn('Estado actual: 🟢 En rango', message['text'])
        self.assertTrue(message['disable_notification'])
        self.assertFalse(self.incident()['pending'])

    def test_critical_survives_rate_limit_and_recovery(self):
        self.record(1)
        deliver_pending()
        self.assertEqual(self.post.call_count, 1)
        self.record(2)
        for _ in range(3):
            self.record(0)
        deliver_pending()
        self.assertEqual(self.post.call_count, 1, 'Must respect channel rate limit')
        self.allow_send()
        deliver_pending()
        self.assertEqual(self.post.call_count, 2)
        message = self.post.call_args.kwargs['json']
        self.assertIn('🔴', message['text'])
        self.assertIn('Estado actual: 🟢 En rango', message['text'])
        self.assertFalse(message['disable_notification'])
        self.assertFalse(self.incident()['pending'])

    def test_repeated_critical_readings_do_not_flood(self):
        for _ in range(20):
            self.record(2)
        deliver_pending()
        for _ in range(20):
            self.record(2)
        self.allow_send()
        deliver_pending()
        self.assertEqual(self.post.call_count, 1)

    def test_event_arriving_during_send_is_not_acknowledged_by_older_send(self):
        self.record(1)
        original = self.post.return_value

        def escalate(*args, **kwargs):
            self.record(2)
            return original

        self.post.side_effect = escalate
        deliver_pending()
        row = self.incident()
        self.assertTrue(row['pending'])
        self.assertEqual(json.loads(row['pending_payload'])['severity'], 2)
        self.post.side_effect = None
        self.allow_send()
        deliver_pending()
        self.assertIn('🔴', self.post.call_args.kwargs['json']['text'])
        self.assertFalse(self.incident()['pending'])
