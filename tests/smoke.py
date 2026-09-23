"""Prueba el stack aislado iniciado con tests/compose.test.yml."""
import os
import json
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError

BASE = os.getenv('TEST_BASE_URL', 'http://127.0.0.1:18080')
USER_TOKEN = None
DEVICE_KEY = None


def request(path, body=None, method=None, expected=200):
    token = DEVICE_KEY if path in ('/api/sensores', '/api/alertas') else USER_TOKEN
    req = Request(BASE + path, data=json.dumps(body).encode() if body is not None else None,
                  headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {})}, method=method)
    try:
        with urlopen(req, timeout=45) as response:
            assert response.status == expected, (path, response.status)
            return json.load(response)
    except HTTPError as error:
        assert error.code == expected, (path, error.code, error.read().decode())


suffix = uuid.uuid4().hex[:8]
request('/api/health')
user = request('/api/login', {'email': os.environ['TEST_EMAIL'], 'password': os.environ['TEST_PASSWORD']})
assert 'password_hash' not in user
USER_TOKEN = user['access_token']
request('/api/ready')
before = request('/api/empresas')
body = {'nombre': 'Prueba ' + suffix, 'responsable': 'QA', 'email': suffix + '@example.com', 'password': 'test-password'}
company = request('/api/empresas', body, expected=201)
request('/api/empresas', body, expected=409)
assert len(request('/api/empresas')) == len(before) + 1, 'Registro parcial al duplicar correo'
boss = request('/api/login', {'email': body['email'], 'password': body['password']})
area = request('/api/areas', {'id_empresa': company['id_empresa'], 'nombre': 'Producción'})
machine_id = 'TEST-' + suffix
machine = {'id_maquina': machine_id, 'id_area': area['id_area'], 'nombre': 'Motor de prueba',
           **{'medir_' + key: True for key in ['temp', 'temp_amb', 'vib', 'volt', 'vel', 'hum']}}
request('/api/maquinas', machine)
DEVICE_KEY = request(f'/api/maquinas/{machine_id}/device-key', {})['device_api_key']
request('/api/maquinas', machine, expected=409)
request('/api/maquinas', {**machine, 'id_maquina': '../invalid'}, expected=422)
assert request(f'/api/maquinas/{machine_id}/datos')['historial'] == []
payload = dict(id_maquina=machine_id, temperatura=25, temp_ambiente=22, vibracion=2, voltaje=12, velocidad=60, humedad=20)
request('/api/sensores', {**payload, 'humedad': 150}, expected=422)
request('/api/sensores', {**payload, 'id_maquina': 'MISSING'}, expected=403)
request('/api/sensores', payload)
data = request(f'/api/maquinas/{machine_id}/datos')
assert data['maquina']['estado'] == 'optimo'
assert data['historial'][0]['edad_segundos'] < 30
config = request(f'/api/maquinas/{machine_id}/config')
request(f'/api/maquinas/{machine_id}/config', {**config, 'temp_alerta': 100, 'temp_peligro': 40}, method='PUT', expected=422)
request(f'/api/maquinas/{machine_id}/config', {**config, 'medir_temp': False}, method='PUT')
assert request('/api/sensores', {**payload, 'temperatura': 100})['estado_calculado'] == 'optimo'
request(f'/api/maquinas/{machine_id}/config', config, method='PUT')
assert request('/api/sensores', {**payload, 'temperatura': 100})['estado_calculado'] == 'peligro'
request(f'/api/maquinas/{machine_id}/prediccion')
assert request('/api/chat', {'id_maquina': machine_id, 'mensaje': 'estado'})['respuesta']
print('OK: login, empresa transaccional, áreas, máquinas, configuración, sensores, predicción y chat a través de Nginx.')

# Identical telemetry is persisted only once, including concurrent retries.
from concurrent.futures import ThreadPoolExecutor
identified = {**payload, 'sequence': 1, 'boot_id': suffix, 'firmware_version': 'ci'}
with ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(lambda _: request('/api/sensores', identified), range(4)))
assert sum(bool(r.get('duplicate')) for r in results) == 3
assert len([r for r in request(f'/api/maquinas/{machine_id}/datos')['historial'] if r['boot_id'] == suffix]) == 1
old_key = DEVICE_KEY
DEVICE_KEY = request(f'/api/maquinas/{machine_id}/device-key', {})['device_api_key']
new_key = DEVICE_KEY
DEVICE_KEY = old_key
request('/api/sensores', payload, expected=401)
DEVICE_KEY = new_key
request('/api/sensores', {**identified, 'boot_id': suffix + '-reboot'})
admin_token = USER_TOKEN
USER_TOKEN = boss['access_token']
request('/api/empresas', body, expected=403)
request('/api/maquinas/M-01/datos', expected=403)
request('/api/usuarios', {'id_empresa': company['id_empresa'], 'nombre': 'Denied', 'email': suffix+'-denied@example.com', 'password': 'test-password', 'rol': 'instalador'}, expected=403)
assert len(request('/api/empresas')) == 1
request('/api/usuarios', {'id_empresa': company['id_empresa'], 'nombre': 'Reader', 'email': suffix+'-reader@example.com', 'password': 'test-password', 'rol': 'participante'})
reader = request('/api/login', {'email': suffix+'-reader@example.com', 'password': 'test-password'})
USER_TOKEN = reader['access_token']
request(f'/api/maquinas/{machine_id}/datos')
request(f'/api/maquinas/{machine_id}/device-key', {}, expected=403)
request(f'/api/maquinas/{machine_id}/config', config, method='PUT', expected=403)
USER_TOKEN = None
request('/api/empresas', expected=401)
print('OK: JWT, company isolation, roles, device rotation, concurrent deduplication, restart identity.')

# Cookie session survives a new page/request, without exposing JWT to storage.
from http.cookiejar import CookieJar
from urllib.request import build_opener, HTTPCookieProcessor
session = build_opener(HTTPCookieProcessor(CookieJar()))
login = session.open(Request(BASE + '/api/login', data=json.dumps({'email': os.environ['TEST_EMAIL'], 'password': os.environ['TEST_PASSWORD']}).encode(), headers={'Content-Type': 'application/json'}))
assert login.status == 200
assert 'HttpOnly' in login.headers['Set-Cookie'] and 'SameSite=lax' in login.headers['Set-Cookie']
assert session.open(BASE + '/api/me').status == 200
assert session.open(Request(BASE + '/api/logout', method='POST', headers={'Origin': 'http://localhost:8088'})).status == 200
try:
    session.open(BASE + '/api/me')
    raise AssertionError('Cookie session not cleared')
except HTTPError as error:
    assert error.code == 401

USER_TOKEN = admin_token
channel = request('/api/telegram/channels', {'id_empresa': company['id_empresa'], 'nombre': 'Test destination',
                  'bot_token': '123456789:' + 'x'*32, 'chat_id': '-100123456789'})
settings = {'channel_id': channel['id'], 'cooldown_seconds': 900}
request(f'/api/maquinas/{machine_id}/notifications', settings, method='PUT')
request('/api/maquinas/M-01/notifications', settings, method='PUT', expected=403)
second = machine_id + '-B'
request('/api/maquinas', {**machine, 'id_maquina': second})
request(f'/api/maquinas/{second}/notifications', settings, method='PUT')
for mid in (machine_id, second):
    result = request(f'/api/maquinas/{mid}/notifications')
    assert result['channel_id'] == channel['id']
    assert 'token' not in json.dumps(result)
USER_TOKEN = boss['access_token']
request(f'/api/maquinas/{machine_id}/installation', {}, expected=403)
USER_TOKEN = reader['access_token']
request(f'/api/maquinas/{machine_id}/notifications', expected=403)
USER_TOKEN = admin_token
installation = request(f'/api/maquinas/{second}/installation', {'server_url': 'http://predicta.planta:8088'})
USER_TOKEN = installation['enrollment_code']
enrolled = request('/api/device/enroll', {})
request('/api/device/enroll', {}, expected=401)
USER_TOKEN = admin_token
DEVICE_KEY = enrolled['device_api_key']
normal = {**payload, 'id_maquina': second, 'boot_id': 'installation-test'}
for sequence in range(3):
    request('/api/sensores', {**normal, 'temperatura': 100, 'sequence': sequence})
incident = request(f'/api/maquinas/{second}/datos')['ultima_alerta']
assert incident['severity'] == 2 and incident['occurrences'] == 3
assert incident['metrics'][0]['label'] == 'Motor'
assert 'diagnostico' not in incident
assert request(f'/api/maquinas/{second}/installation')['connected'] is True
for sequence in range(3, 8):
    request('/api/sensores', {**normal, 'sequence': sequence})
assert request(f'/api/maquinas/{second}/datos')['ultima_alerta']['active'] is False
print('OK: cookie reload/logout, shared Telegram routing, tenant isolation, one-use enrollment, grouped alerts and recovery.')
