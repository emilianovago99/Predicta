"""Reference for the firmware team; explicit enrollment, no secrets in output.

DEVICE_SERVER_URL and DEVICE_ENROLLMENT_CODE enroll once into a private file.
Subsequent runs reuse that file. Send example readings only in a test machine.
"""
import json
import os
from pathlib import Path
import time
import uuid
import requests


def main():
    credentials_file = Path(os.getenv('DEVICE_CREDENTIALS_FILE', '.device-credentials.json'))
    if credentials_file.exists():
        credentials = json.loads(credentials_file.read_text())
    else:
        base = os.environ['DEVICE_SERVER_URL'].rstrip('/')
        r = requests.post(base + '/api/device/enroll', headers={
            'Authorization': 'Bearer ' + os.environ['DEVICE_ENROLLMENT_CODE']}, timeout=10)
        if r.status_code != 200:
            raise SystemExit(f'Enrollment rejected ({r.status_code}); request a new code if needed.')
        credentials = r.json()
        with os.fdopen(os.open(credentials_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
            json.dump(credentials, f)
    boot = uuid.uuid4().hex
    headers = {'Authorization': 'Bearer ' + credentials['device_api_key']}
    for sequence in range(10):
        payload = dict(maquina_id=credentials['maquina_id'], boot_id=boot, sequence=sequence,
                       firmware_version='reference-1.0', temperatura=25, temp_ambiente=22,
                       vibracion=1.2, voltaje=120, velocidad=1400, humedad=45)
        delay = 2
        while True:
            try:
                r = requests.post(credentials['server_url'] + '/api/sensores', json=payload, headers=headers, timeout=10)
                if r.status_code == 200:
                    print('Measurement accepted:', sequence)
                    break
                if r.status_code in (401, 403, 422):
                    raise SystemExit(f'Configuration error ({r.status_code}); contact the installer.')
            except requests.RequestException:
                pass
            time.sleep(delay)
            delay = min(60, delay * 2)
        time.sleep(2)


if __name__ == '__main__':
    main()
