"""Configuration shared by API, migrations and administrative commands."""
import os
from dotenv import load_dotenv

load_dotenv()


def validate_settings():
    if len(os.getenv('JWT_SECRET', '')) < 32:
        raise RuntimeError('JWT_SECRET must contain at least 32 characters')
    if not os.getenv('DB_PASSWORD'):
        raise RuntimeError('DB_PASSWORD is required')
    if not 60 <= int(os.getenv('JWT_EXPIRES_SECONDS', '3600')) <= 86400:
        raise RuntimeError('JWT_EXPIRES_SECONDS must be between 60 and 86400')
    if os.getenv('APP_ENV', 'development') == 'production':
        domain = os.getenv('DOMAIN', '')
        if not domain or any(c in domain for c in '/ :'):
            raise RuntimeError('DOMAIN must be a hostname')


def cors_origins():
    if os.getenv('APP_ENV', 'development') == 'production':
        return ['https://' + os.environ['DOMAIN']]
    origins = os.getenv('CORS_ORIGINS', 'http://localhost:8088,http://127.0.0.1:8088,http://localhost:5173').split(',')
    if '*' in origins:
        raise RuntimeError('Use explicit CORS origins')
    return [origin.strip() for origin in origins if origin.strip()]
