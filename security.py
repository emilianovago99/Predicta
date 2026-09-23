"""User JWTs and independent, machine-scoped device credentials."""
import hashlib
import hmac
import os
import secrets
import time
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from database import conectar_db

bearer = HTTPBearer(auto_error=False)


def hash_password(password):
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 600000).hex()
    return f'pbkdf2_sha256$600000${salt}${digest}'


def verify_password(password, stored):
    try:
        algorithm, rounds, salt, digest = stored.split('$')
        if algorithm != 'pbkdf2_sha256':
            return False
        actual = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), int(rounds)).hex()
        return hmac.compare_digest(actual, digest)
    except (ValueError, TypeError):
        return False


def issue_token(user):
    now = int(time.time())
    expires = int(os.getenv('JWT_EXPIRES_SECONDS', '3600'))
    token = jwt.encode({'sub': str(user['id_usuario']), 'iat': now, 'exp': now + expires,
                        'iss': 'predicta', 'aud': 'predicta-users'}, os.environ['JWT_SECRET'], algorithm='HS256')
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': expires, **user}


def token_value(credentials):
    if not credentials or credentials.scheme.lower() != 'bearer':
        raise HTTPException(401, 'Autenticación requerida', headers={'WWW-Authenticate': 'Bearer'})
    return credentials.credentials


def query_one(sql, params):
    db = conectar_db()
    cur = db.cursor(dictionary=True)
    try:
        cur.execute(sql, params)
        return cur.fetchone()
    finally:
        cur.close()
        db.close()


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    token = token_value(credentials)
    try:
        claims = jwt.decode(token, os.environ['JWT_SECRET'], algorithms=['HS256'],
                            issuer='predicta', audience='predicta-users',
                            options={'require': ['sub', 'exp', 'iat']})
        user_id = int(claims['sub'])
    except (jwt.InvalidTokenError, ValueError, TypeError):
        raise HTTPException(401, 'Sesión inválida o vencida', headers={'WWW-Authenticate': 'Bearer'})
    user = query_one('SELECT id_usuario, id_empresa, nombre, rol FROM Usuario WHERE id_usuario=%s', (user_id,))
    if not user:
        raise HTTPException(401, 'Sesión inválida')
    return user


def require_editor(user=Depends(get_current_user)):
    if user['rol'] not in ('instalador', 'jefe'):
        raise HTTPException(403, 'Permisos insuficientes')
    return user


def require_installer(user=Depends(get_current_user)):
    if user['rol'] != 'instalador':
        raise HTTPException(403, 'Se requiere instalador')
    return user


def check_company(user, company_id):
    if user['rol'] != 'instalador' and user['id_empresa'] != company_id:
        raise HTTPException(403, 'Empresa no autorizada')


def check_area(user, area_id):
    row = query_one('SELECT id_empresa FROM Area WHERE id_area=%s', (area_id,))
    if not row:
        raise HTTPException(404, 'Área no encontrada')
    check_company(user, row['id_empresa'])


def check_machine(user, machine_id):
    row = query_one('SELECT a.id_empresa FROM Maquina m JOIN Area a ON a.id_area=m.id_area WHERE m.id_maquina=%s', (machine_id,))
    if not row:
        raise HTTPException(404, 'Máquina no encontrada')
    check_company(user, row['id_empresa'])


def get_device(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    value = token_value(credentials)
    row = query_one('SELECT id_maquina FROM DeviceCredential WHERE key_hash=%s',
                    (hashlib.sha256(value.encode()).hexdigest(),))
    if not row:
        raise HTTPException(401, 'Credencial de dispositivo inválida', headers={'WWW-Authenticate': 'Bearer'})
    return row


def check_device(device, machine_id):
    if device['id_maquina'] != machine_id:
        raise HTTPException(403, 'Credencial de otra máquina')


def machine_reader(id_maquina: str, credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    # Existing simulators read thresholds using their device credential.
    if token_value(credentials).startswith('pd_'):
        check_device(get_device(credentials), id_maquina)
    else:
        check_machine(get_current_user(credentials), id_maquina)


def rotate_device_key(machine_id):
    key = 'pd_' + secrets.token_urlsafe(32)
    db = conectar_db()
    cur = db.cursor()
    try:
        cur.execute('INSERT INTO DeviceCredential (id_maquina, key_hash) VALUES (%s,%s) '
                    'ON DUPLICATE KEY UPDATE key_hash=VALUES(key_hash), rotated_at=CURRENT_TIMESTAMP',
                    (machine_id, hashlib.sha256(key.encode()).hexdigest()))
        db.commit()
        return key
    finally:
        cur.close()
        db.close()
