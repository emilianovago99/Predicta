import os
import secrets
import time
import unittest
from unittest.mock import patch, MagicMock
import jwt
from fastapi.testclient import TestClient
from fastapi.security import HTTPAuthorizationCredentials
import main
import security
from settings import cors_origins


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'JWT_SECRET': secrets.token_urlsafe(48), 'JWT_EXPIRES_SECONDS': '3600'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.user = dict(id_usuario=7, id_empresa=2, nombre='Tester', rol='jefe')
        self.client = TestClient(main.app, raise_server_exceptions=False)

    def credentials(self, value):
        return HTTPAuthorizationCredentials(scheme='Bearer', credentials=value)

    def test_jwt_signature_expiry_and_audience(self):
        issued = security.issue_token(self.user)
        with patch.object(security, 'query_one', return_value=self.user):
            self.assertEqual(security.get_current_user(self.credentials(issued['access_token'])), self.user)
            for claims in [dict(sub='7', iat=1, exp=2, iss='predicta', aud='predicta-users'),
                           dict(sub='7', iat=int(time.time()), exp=int(time.time())+60, iss='predicta', aud='devices')]:
                token = jwt.encode(claims, os.environ['JWT_SECRET'], algorithm='HS256')
                with self.assertRaises(main.HTTPException) as error:
                    security.get_current_user(self.credentials(token))
                self.assertEqual(error.exception.status_code, 401)
            with self.assertRaises(main.HTTPException):
                security.get_current_user(self.credentials(issued['access_token'] + 'tampered'))

    def test_all_private_routes_require_credentials(self):
        for path, operations in main.app.openapi()['paths'].items():
            if not path.startswith('/api/') or path in ('/api/health', '/api/ready', '/api/login'):
                continue
            path = path.replace('{id_maquina}', 'M-01').replace('{id_empresa}', '2').replace('{id_area}', '1').replace('{channel_id}', '1')
            for method in (m.upper() for m in operations if m in ('get', 'post', 'put', 'delete', 'patch')):
                with self.subTest(path=path, method=method):
                    response = self.client.request(method, path, json={} if method in ('POST', 'PUT') else None)
                    self.assertEqual(response.status_code, 401)

    def test_tenant_and_role_boundaries(self):
        with self.assertRaises(main.HTTPException) as error:
            security.check_company(self.user, 99)
        self.assertEqual(error.exception.status_code, 403)
        with self.assertRaises(main.HTTPException):
            security.require_editor({**self.user, 'rol': 'participante'})
        with self.assertRaises(main.HTTPException):
            security.require_installer(self.user)

    def test_device_invalid_401_and_wrong_machine_403(self):
        with patch.object(security, 'query_one', return_value=None):
            with self.assertRaises(main.HTTPException) as error:
                security.get_device(self.credentials('bad'))
            self.assertEqual(error.exception.status_code, 401)
        with self.assertRaises(main.HTTPException) as error:
            security.check_device({'id_maquina': 'A'}, 'B')
        self.assertEqual(error.exception.status_code, 403)

    def test_duplicate_has_no_alert_or_training_side_effects(self):
        db = MagicMock()
        db.cursor.return_value.fetchone.side_effect = [{'temp_alerta': 50}, {'id_data': 1}]
        data = main.Telemetria(maquina_id='M-01', temperatura=99, vibracion=1, voltaje=12,
                              velocidad=50, humedad=20, sequence=1, boot_id='boot')
        with patch.object(main, 'conectar_db', return_value=db), patch.object(main, 'record_incident') as notify:
            self.assertTrue(main.registrar_telemetria(data, {'id_maquina': 'M-01'})['duplicate'])
            notify.assert_not_called()
        db.commit.assert_not_called()
        self.assertEqual(db.cursor.return_value.execute.call_count, 2)

    def test_login_never_returns_password_and_validation_redacts_input(self):
        db = MagicMock()
        db.cursor.return_value.fetchone.return_value = {**self.user, 'password_hash': security.hash_password('test-only-password')}
        with patch.object(main, 'conectar_db', return_value=db):
            response = self.client.post('/api/login', json={'email': 'a@example.com', 'password': 'test-only-password'})
        self.assertEqual(response.status_code, 200)
        self.assertNotIn('password', response.text)
        self.assertEqual(response.json()['expires_in'], 3600)
        response = self.client.post('/api/login', json={'email': 'x', 'password': {'secret': 'do-not-echo'}})
        self.assertNotIn('do-not-echo', response.text)
        self.assertEqual(response.status_code, 422)

    def test_production_cors(self):
        with patch.dict(os.environ, {'APP_ENV': 'production', 'DOMAIN': 'example.com', 'CORS_ORIGINS': '*'}):
            self.assertEqual(cors_origins(), ['https://example.com'])

    def test_cookie_session_and_logout(self):
        issued = security.issue_token(self.user)
        self.client.cookies.set('predicta_session', issued['access_token'])
        with patch.object(security, 'query_one', return_value=self.user):
            response = self.client.post('/api/logout', headers={'Origin': 'http://localhost:8088'})
        self.assertEqual(response.status_code, 200)
        self.assertIn('Max-Age=0', response.headers['set-cookie'])

    def test_cookie_mutation_rejects_foreign_origin(self):
        self.client.cookies.set('predicta_session', security.issue_token(self.user)['access_token'])
        response = self.client.put('/api/maquinas/M-01/notifications', json={}, headers={'Origin': 'https://other.example'})
        self.assertEqual(response.status_code, 403)

    def test_health_unavailable(self):
        with patch.object(main, 'conectar_db', side_effect=main.mysql.connector.Error('private-db-host')):
            response = self.client.get('/api/health')
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private-db-host', response.text)


if __name__ == '__main__':
    unittest.main()
