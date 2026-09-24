import json
import unittest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch
from notifications import summarize, telegram_text, record_incident, deliver_pending
from device_setup import InstallationInput
from pydantic import ValidationError


class NotificationTests(unittest.TestCase):
    def test_enabled_metrics_and_actual_thresholds(self):
        p = summarize({'temperatura': 95, 'vibracion': 99}, {'temp_alerta': 50, 'temp_peligro': 80, 'medir_vib': False})
        self.assertEqual(p['severity'], 2)
        self.assertEqual(len(p['metrics']), 1)
        self.assertEqual(p['metrics'][0]['limit'], 80)
        self.assertNotIn('diagnostico', p)

    def test_html_escaped_and_digest_bounded(self):
        payload = {**summarize({'temperatura': 90}, {'temp_alerta': 50, 'temp_peligro': 80}), 'fecha': '2026-09-23T15:00:00Z'}
        text = telegram_text([dict(nombre='<Motor & prueba>', id_maquina='M-01', payload=json.dumps(payload))] * 5)
        self.assertIn('&lt;Motor &amp; prueba&gt;', text)
        self.assertLess(len(text), 4096)
        self.assertIn('90 °C', text)

    def test_repeats_do_not_insert_history(self):
        c = MagicMock()
        old = dict(severity=2, emitted_at=datetime.utcnow()-timedelta(seconds=5), episode='a'*32, occurrences=3, normal_count=0)
        c.fetchone.return_value = old
        record_incident(c, 'M', dict(severity=2, tipo='critico', title='Critical', action='Review', metrics=[]))
        self.assertEqual(c.execute.call_count, 2)
        self.assertEqual(c.execute.call_args.args[1][-2], old['emitted_at'])
        self.assertFalse(c.execute.call_args.args[1][-1])

    def test_escalation_does_not_wait_for_cooldown(self):
        c = MagicMock()
        c.fetchone.return_value = dict(severity=1, emitted_at=datetime.utcnow(), episode='a'*32, occurrences=3, normal_count=0)
        record_incident(c, 'M', dict(severity=2, tipo='critico', title='Critical', action='Review', metrics=[]))
        self.assertEqual(c.execute.call_count, 4)
        self.assertIn('INSERT INTO Alertas', c.execute.call_args.args[0])

    def test_recovery_requires_three_readings(self):
        c = MagicMock()
        old = dict(severity=2, emitted_at=datetime.utcnow(), episode='a'*32, occurrences=3, normal_count=1)
        c.fetchone.return_value = old
        payload = dict(severity=0, tipo='recuperado', title='Recovered', action='Monitor', metrics=[])
        record_incident(c, 'M', payload)
        self.assertEqual(c.execute.call_args.args[1][0], 2)
        c.reset_mock()
        c.fetchone.return_value = {**old, 'normal_count': 2}
        record_incident(c, 'M', payload)
        inserts = [call for call in c.execute.call_args_list if 'INSERT INTO MachineAlert' in call.args[0]]
        self.assertTrue(inserts[0].args[1][-1])

    def test_recovery_keeps_unsent_critical_snapshot(self):
        c = MagicMock()
        critical = dict(severity=2, title='Critical', action='Review', metrics=[], fecha='2026-09-23T00:00:00Z')
        c.fetchone.return_value = dict(severity=2, emitted_at=datetime.utcnow(), episode='a'*32,
                                      occurrences=1, normal_count=2,
                                      pending_payload=json.dumps(critical), pending_revision='old')
        recovered = dict(severity=0, tipo='recuperado', title='Recovered', action='Monitor', metrics=[])
        record_incident(c, 'M', recovered)
        snapshot, revision, machine = c.execute.call_args.args[1]
        self.assertEqual(json.loads(snapshot), critical)
        self.assertNotEqual(revision, 'old')
        text = telegram_text([dict(nombre='Motor', id_maquina=machine, pending_payload=snapshot,
                                   payload=json.dumps(recovered))])
        self.assertIn('🔴', text)
        self.assertIn('Estado actual: 🟢 En rango', text)
        self.assertIn('revisa la causa', text)

    def test_enrollment_url_validation(self):
        for url in ('http://localhost:8088', 'http://127.0.0.1:8000', 'http://u:p@host', 'https://host/api'):
            with self.assertRaises(ValidationError):
                InstallationInput(server_url=url)
        self.assertEqual(InstallationInput(server_url='https://predicta.example.com/').server_url, 'https://predicta.example.com')

    def test_429_keeps_pending_and_delays_retry(self):
        db = MagicMock()
        c = db.cursor.return_value
        row = dict(id_maquina='M', nombre='Motor', severity=2, updated_at=datetime.utcnow(),
                   payload=json.dumps(dict(severity=2, metrics=[], title='Critical', action='Review', fecha='2026-09-23T00:00:00Z')))
        c.fetchall.side_effect = [[{'id': 1}], [row]]
        c.fetchone.side_effect = [{'ok': 1}, {'id': 1, 'id_empresa': 1, 'chat_id': '-1', 'token_encrypted': 'encrypted'}, {'ok': 1}]
        response = MagicMock(status_code=429, ok=False)
        response.json.return_value = {'ok': False, 'parameters': {'retry_after': 120}}
        with patch('notifications.conectar_db', return_value=db), patch('notifications.cipher') as cipher, patch('notifications.requests.post', return_value=response):
            cipher.return_value.decrypt.return_value = b'test-token'
            before = datetime.utcnow()
            deliver_pending()
        updates = [call for call in c.execute.call_args_list if 'UPDATE TelegramChannel' in call.args[0]]
        self.assertGreaterEqual((updates[0].args[1][0] - before).total_seconds(), 120)
        self.assertFalse(any('pending=0' in call.args[0] for call in c.execute.call_args_list))
