"""Additive MariaDB migrations. DDL auto-commits; scripts must be restartable."""
import hashlib
from pathlib import Path
from database import conectar_db
from security import hash_password


def migrate():
    db = conectar_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT GET_LOCK('predicta_schema', 60)")
        if cur.fetchone()[0] != 1:
            raise RuntimeError('Cannot acquire migration lock')
        cur.execute('CREATE TABLE IF NOT EXISTS schema_version (version VARCHAR(100) PRIMARY KEY, '
                    'checksum CHAR(64) NOT NULL, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)')
        for path in sorted(Path(__file__).with_name('migrations').glob('*.sql')):
            source = path.read_text(encoding='utf-8')
            checksum = hashlib.sha256(source.encode()).hexdigest()
            cur.execute('SELECT checksum FROM schema_version WHERE version=%s', (path.name,))
            row = cur.fetchone()
            if row:
                if row[0] != checksum:
                    raise RuntimeError(f'Migration checksum changed: {path.name}')
                continue
            sql = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('--'))
            for statement in sql.split(';'):
                if statement.strip():
                    cur.execute(statement)
            cur.execute('INSERT INTO schema_version (version, checksum) VALUES (%s,%s)', (path.name, checksum))
            db.commit()
        # Upgrade legacy plaintext once, without changing user passwords or deleting users.
        cur.execute('SELECT id_usuario, password_hash FROM Usuario')
        for user_id, stored in cur.fetchall():
            if not stored.startswith('pbkdf2_sha256$'):
                cur.execute('UPDATE Usuario SET password_hash=%s WHERE id_usuario=%s', (hash_password(stored), user_id))
        db.commit()
    finally:
        cur.execute("SELECT RELEASE_LOCK('predicta_schema')")
        cur.fetchone()
        cur.close()
        db.close()


if __name__ == '__main__':
    migrate()
