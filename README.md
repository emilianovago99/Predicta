# Predicta — mantenimiento predictivo industrial

Flutter Web/Android/iOS, FastAPI, MariaDB y ESP32: empresas → áreas → máquinas,
telemetría, gráficas, umbrales configurables, alertas críticas/preventivas/eventos,
ML de mantenimiento y chat Mecanimal. Gemini/Telegram son opcionales.

## Inicio local

Guía del nuevo flujo: [sensores, instalación y Telegram](docs/SENSORES_E_INSTALACION.md).

**El entorno de trabajo actual es local:** http://localhost:8088. No necesitas
DOMAIN, ACME_EMAIL, Caddy ni certificados. La configuración de producción queda
separada en `docker-compose.prod.yml` para más adelante.

En Windows, con `.env` configurado, el comando habitual desde la raíz es:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_local.ps1
```

Reconstruye API/web, espera los healthchecks y verifica `/api/health` por Nginx.
Así se evita ejecutar una web antigua después de cambiar el código. Conserva los
usuarios, contraseñas, JWT y permisos también en local. Si tenías la app abierta
antes de actualizar, recarga la pestaña e inicia sesión otra vez. La web limpia
las cachés antiguas de Flutter al arrancar y se compila sin caché offline.

Para editar Flutter con recarga rápida, deja Docker activo y usa otra terminal:

```powershell
cd mantenimiento_predictivo
flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000
```

Para Android emulador usa `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.
El archivo `.env` de Flutter no contiene secretos del backend ni se carga solo.

Pasos manuales y primera instalación:

1. Crear `.env` desde `.env.example` **solo si no existe**. Completar DB_PASSWORD,
   DB_ROOT_PASSWORD y JWT_SECRET (mínimo 32 caracteres aleatorios).
2. Ejecutar desde la raíz:

```bash
docker compose config --quiet
docker compose up -d --build --wait
docker compose exec api python admin.py create-installer --email TU_EMAIL --name "Administrador"
```

3. Abrir http://localhost:8088 e iniciar sesión. No hay passwords predeterminados.
   Las cuentas/datos de instalaciones existentes se conservan; las contraseñas
   heredadas se convierten a hash al migrar. Cambiarlas antes de publicar.
4. Para demo, generar clave de M-01 y guardarla como DEVICE_API_KEY en `.env`:

```bash
docker compose exec api python admin.py rotate-device-key --machine M-01
docker compose --profile demo up -d --build simulator
```

Si ya configuraste una clave válida, no necesitas volver a generarla. Al cambiar
el código del simulador usa `--build`: reiniciar el contenedor no actualiza su
imagen. Un simulador antiguo puede enviar lecturas sin credencial y recibir 401.
Abre la máquina `M-01` para ver el monitoreo, que consulta datos cada 2 segundos.
El simulador ejecuta 40 ciclos (aproximadamente 80 segundos) y termina; para
repetir la demostración ejecuta de nuevo el comando anterior.

Roles conservados: instalador administra empresas; jefe gestiona su empresa;
participante consulta y usa chat. Las comprobaciones se ejecutan también en API.

## Producción

HTTPS → Caddy → Nginx/Flutter → /api → FastAPI → MariaDB. Solo Caddy publica
80/443; no hay simulador en producción. Crear `.env.production` con secretos propios,
DOMAIN y ACME_EMAIL y preparar DNS/VM según la guía:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml config --quiet
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build --wait --wait-timeout 240
```

No mezclar los dos Compose. No borrar volúmenes ni ejecutar init.sql sobre datos
existentes. No hay despliegue real ejecutado como parte de estos cambios.

## Guías y validación

- [Guía completa: desarrollo, producción, Flutter, ESP32, backups y rollback](deploy/README.md).
- [Diagnóstico, datos e incompatibilidades](deploy/PLAN.md).
- [Inventario de cambios](deploy/CHANGES.md).
- [Comprobaciones realizadas y limitaciones](deploy/VALIDATION.md).

```bash
python -m unittest discover -s tests -p 'test_*.py' -v
python tests/run_stack.py
cd mantenimiento_predictivo
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
```

`tests/run_stack.py` construye un proyecto Docker aislado y conserva su volumen de
prueba al detenerlo. No necesita las credenciales de tu base existente.
El prototipo histórico `script.sh` contiene Python, no Bash; usa configuración por
entorno. Para demo habitual usar `simulador_edge.py` o `simulador_cambio.py`.

## Autenticación y telemetría

Login devuelve JWT de usuario con expiración; enviar Authorization Bearer en
requests privados. ESP32/simuladores usan DEVICE_API_KEY independiente y limitada
a una máquina. Los campos anteriores siguen válidos; sequence/boot_id/firmware_version
son opcionales. received_at se registra en servidor. Reintentos con la misma
identidad no duplican mediciones ni alertas. Health: GET /api/health y /api/ready.

Se mantienen los algoritmos y umbrales ML existentes. Credenciales previamente
publicadas deben revocarse en su proveedor: retirarlas del código no borra Git.
