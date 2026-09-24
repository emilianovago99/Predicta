"""Disposable integration stack. Does not touch an existing Compose project/volume."""
import os
import gzip
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.request import urlopen
from urllib.error import URLError

root = Path(__file__).resolve().parents[1]
os.chdir(root)
project = 'predicta-test-' + uuid.uuid4().hex[:8]
env = dict(os.environ, DB_PASSWORD=secrets.token_urlsafe(32), DB_ROOT_PASSWORD=secrets.token_urlsafe(32),
           JWT_SECRET=secrets.token_urlsafe(48), GEMINI_API_KEY='', TELEGRAM_BOT_TOKEN='', TELEGRAM_CHAT_ID='')
with tempfile.TemporaryDirectory(prefix='predicta-tests-') as directory:
    env_file = Path(directory) / '.env'
    env_file.write_text('\n'.join(f'{key}={env[key]}' for key in
        ('DB_PASSWORD', 'DB_ROOT_PASSWORD', 'JWT_SECRET', 'GEMINI_API_KEY', 'TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHAT_ID')), encoding='utf-8')
    compose = ['docker', 'compose', '--env-file', str(env_file), '-p', project,
               '-f', 'docker-compose.yml', '-f', 'tests/compose.test.yml']

    def run(*args, **kwargs):
        return subprocess.run([*compose, *args], env=env, check=True, **kwargs)

    try:
        run('config', '--quiet')
        password = secrets.token_urlsafe(24)
        run('up', '-d', '--wait', '--wait-timeout', '120', 'mariadb')
        # Seed legacy data BEFORE the API performs additive migrations.
        seed = f"""INSERT INTO Usuario (id_empresa,nombre,email,password_hash,rol)
VALUES (1,'CI','ci@example.com','{password}','instalador');
INSERT INTO SensorData (id_maquina,temperatura,temp_ambiente,vibracion,voltaje,velocidad,humedad,fecha)
VALUES ('M-01',25,22,2,12,60,20,'2025-01-01 00:00:00');
"""
        run('exec', '-T', 'mariadb', 'sh', '-c',
            'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb --user="$MARIADB_USER" "$MARIADB_DATABASE"', input=seed.encode())
        run('up', '-d', '--build', '--wait', '--wait-timeout', '240', 'web')
        verify = """from database import conectar_db
db=conectar_db(); c=db.cursor()
c.execute("SELECT password_hash FROM Usuario WHERE email='ci@example.com'")
assert c.fetchone()[0].startswith('pbkdf2_sha256$')
c.execute("SELECT COUNT(*) FROM SensorData WHERE id_maquina='M-01' AND received_at=fecha AND YEAR(fecha)=2025")
assert c.fetchone()[0] == 1
db.close()
print('OK: legacy users and telemetry preserved by migrations')
"""
        run('exec', '-T', 'api', 'python', '-', input=verify.encode())
        # Re-run migrations twice to verify checksums and restart safety on populated data.
        run('exec', '-T', 'api', 'python', 'migrate.py')
        run('exec', '-T', '-e', 'PREDICTA_DB_INTEGRATION=true', 'api', 'python', '-m', 'unittest', 'discover', '-s', '/tests', '-p', 'test_*.py', '-v')
        run('exec', '-T', 'api', 'python', 'migrate.py')
        subprocess.run([sys.executable, 'tests/smoke.py'], env=dict(env, TEST_EMAIL='ci@example.com', TEST_PASSWORD=password), check=True)
        run('up', '-d', '--no-deps', '--force-recreate', '--wait', 'api')
        for attempt in range(10):
            try:
                with urlopen('http://127.0.0.1:18080/api/health', timeout=5) as response:
                    assert response.status == 200
                break
            except URLError:
                if attempt == 9:
                    raise
                time.sleep(2)
        print('OK: Nginx reaches API after container replacement')
        # Exercise a real compressed backup; never automatically restore/drop data.
        bash = str(Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe') if os.name == 'nt' else shutil.which('bash')
        backup_dir = Path(directory) / 'backups'
        backup_env = dict(env, ENV_FILE=env_file.as_posix(), COMPOSE_FILE='docker-compose.yml',
                          COMPOSE_PROJECT_NAME=project, BACKUP_DIR=backup_dir.as_posix())
        subprocess.run([bash, 'scripts/backup_db.sh'], env=backup_env, check=True)
        dumps = list(backup_dir.glob('*.sql.gz'))
        assert len(dumps) == 1
        with gzip.open(dumps[0], 'rt', encoding='utf-8') as dump:
            content = dump.read()
        assert 'schema_version' in content and 'DeviceCredential' in content and 'SensorData' in content
        # Wrong confirmation must cancel before stopping any service or importing data.
        cancelled = subprocess.run([bash, 'scripts/restore_db.sh', dumps[0].as_posix()],
                                   env=backup_env, input=b'CANCEL\n')
        assert cancelled.returncode == 1
        print('OK: compressed backup and restore cancellation guard')
    finally:
        # Preserve even disposable test volumes; do not automate data deletion.
        run('down')
        print(f'Test project stopped. Retained test volume: {project}_mariadb_data')
