"""Prueba el stack aislado iniciado con tests/compose.test.yml."""
import json
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError

BASE = 'http://127.0.0.1:18080'


def request(path, body=None, method=None, expected=200):
    req = Request(BASE + path, data=json.dumps(body).encode() if body is not None else None,
                  headers={'Content-Type': 'application/json'}, method=method)
    try:
        with urlopen(req, timeout=45) as response:
            assert response.status == expected, (path, response.status)
            return json.load(response)
    except HTTPError as error:
        assert error.code == expected, (path, error.code, error.read().decode())


suffix = uuid.uuid4().hex[:8]
request('/api/health')
user = request('/api/login', {'email': 'admin@predicta.com', 'password': 'root'})
assert 'password_hash' not in user
before = request('/api/empresas')
body = {'nombre': 'Prueba ' + suffix, 'responsable': 'QA', 'email': suffix + '@example.com', 'password': 'test-password'}
company = request('/api/empresas', body, expected=201)
request('/api/empresas', body, expected=409)
assert len(request('/api/empresas')) == len(before) + 1, 'Registro parcial al duplicar correo'
request('/api/login', {'email': body['email'], 'password': body['password']})
area = request('/api/areas', {'id_empresa': company['id_empresa'], 'nombre': 'Producción'})
machine_id = 'TEST-' + suffix
machine = {'id_maquina': machine_id, 'id_area': area['id_area'], 'nombre': 'Motor de prueba',
           **{'medir_' + key: True for key in ['temp', 'temp_amb', 'vib', 'volt', 'vel', 'hum']}}
request('/api/maquinas', machine)
request('/api/maquinas', machine, expected=409)
request('/api/maquinas', {**machine, 'id_maquina': '../invalid'}, expected=422)
assert request(f'/api/maquinas/{machine_id}/datos')['historial'] == []
payload = dict(id_maquina=machine_id, temperatura=25, temp_ambiente=22, vibracion=2, voltaje=12, velocidad=60, humedad=20)
request('/api/sensores', {**payload, 'humedad': 150}, expected=422)
request('/api/sensores', {**payload, 'id_maquina': 'MISSING'}, expected=404)
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
