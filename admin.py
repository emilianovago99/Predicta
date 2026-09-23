"""Local administrative access through docker compose exec (no public bootstrap)."""
import argparse
import getpass
from database import conectar_db
from security import hash_password, rotate_device_key


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('create-installer')
    create.add_argument('--email', required=True)
    create.add_argument('--name', required=True)
    reset = sub.add_parser('reset-password')
    reset.add_argument('--email', required=True)
    rotate = sub.add_parser('rotate-device-key')
    rotate.add_argument('--machine', required=True)
    args = parser.parse_args()
    if args.command == 'rotate-device-key':
        print(rotate_device_key(args.machine))
        return
    password = getpass.getpass('Password (at least 12 characters): ')
    if len(password) < 12 or password != getpass.getpass('Repeat password: '):
        parser.error('Passwords must match and contain at least 12 characters')
    db = conectar_db()
    cur = db.cursor()
    try:
        if args.command == 'reset-password':
            cur.execute('UPDATE Usuario SET password_hash=%s WHERE email=%s', (hash_password(password), args.email.lower()))
            if cur.rowcount != 1:
                raise ValueError('User not found')
        else:
            cur.execute('INSERT INTO Empresa (nombre) VALUES (%s)', ('Predicta Administration',))
            company_id = cur.lastrowid
            cur.execute("INSERT INTO Usuario (id_empresa,nombre,email,password_hash,rol) VALUES (%s,%s,%s,%s,'instalador')",
                        (company_id, args.name, args.email.lower(), hash_password(password)))
        db.commit()
    finally:
        cur.close()
        db.close()


if __name__ == '__main__':
    main()
