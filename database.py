import os
import mysql.connector
import settings  # loads .env for local CLI commands


def conectar_db():
    return mysql.connector.connect(
        host=os.getenv('DB_HOST', '127.0.0.1'),
        port=int(os.getenv('DB_PORT', '3307')),
        user=os.getenv('DB_USER', 'api_user'),
        password=os.environ['DB_PASSWORD'],
        database=os.getenv('DB_NAME', 'mecanimales_db'),
        connection_timeout=5, autocommit=False,
    )
