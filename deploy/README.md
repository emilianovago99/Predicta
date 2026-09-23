# Despliegue de Predicta

## Arquitectura

Internet → HTTPS Caddy → web:80 (Nginx + Flutter Web) → /api/* → api:8000
→ MariaDB:3306. Android/iOS y ESP32 usan el mismo dominio HTTPS.
Solo Caddy publica 80/443. MariaDB tiene red interna y volumen persistente.
La API mantiene acceso saliente para Gemini/Telegram. El simulador no existe
en Compose producción. No se incorporan MQTT, Redis, ORM ni Kubernetes.

## Requisitos y variables

VM Ubuntu 24.04 LTS, DNS propio, puertos 80/443 accesibles y SSH restringido.
Se recomienda 4 GB RAM como punto de partida para compilar Flutter y ejecutar ML;
dimensionar según volumen real. Docker Engine + plugin Compose >= 2.24.4.
Python 3.12 es el entorno de referencia del contenedor. Flutter 3.38.3/Dart 3.10.1.

Copiar `.env.example` a `.env` para desarrollo o `.env.production` para producción.
Los valores vacíos deben completarse; el repositorio no trae secretos utilizables.
No sobrescribir un `.env` existente: incorporar las variables faltantes manualmente.

| Variable | Uso |
|---|---|
| DB_PASSWORD / DB_ROOT_PASSWORD | Passwords del usuario API y root; obligatorios en ambos Compose |
| DB_NAME / DB_USER | Defaults `mecanimales_db` / `api_user` |
| DB_HOST / DB_PORT | API Python local: 127.0.0.1:3307; Compose usa mariadb:3306 |
| JWT_SECRET | Secreto aleatorio de al menos 32 caracteres; obligatorio |
| JWT_EXPIRES_SECONDS | 3600 por defecto, rango 60–86400 |
| DOMAIN / ACME_EMAIL | Hostname sin esquema/path y email ACME; obligatorios en producción |
| APP_ENV | development para Python local; Compose producción fuerza production |
| CORS_ORIGINS | Orígenes exactos separados por comas, solo desarrollo |
| DB_VOLUME_NAME | Volumen producción; default predicta_mariadb_data; mantener estable |
| API_BIND / API_PORT | Desarrollo: 127.0.0.1 / 8000; abrir LAN solo explícitamente |
| WEB_BIND / WEB_PORT | Desarrollo: 127.0.0.1 / 8088 |
| GEMINI_API_KEY | Opcional, chat/diagnóstico; se conserva fallback sin Gemini |
| TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID | Opcionales; no se envían notificaciones si faltan |
| API_BASE_URL / MACHINE_ID / DEVICE_API_KEY | Simuladores; origen, máquina y clave independiente |

Generar cada secreto de servidor por separado en la VM: `openssl rand -hex 32`.
Guardar los valores en un gestor de secretos y en el archivo privado, no en Git.
Cambiar variables de MariaDB no cambia passwords dentro de un volumen ya creado:
usar las credenciales actuales o cambiarlas explícitamente con un administrador DB.

## Desarrollo exacto

Este es el entorno de trabajo actual. En Windows también puedes ejecutar
`powershell -ExecutionPolicy Bypass -File .\scripts\start_local.ps1` desde la raíz:
reconstruye el cliente y la API, levanta solo el Compose local y verifica health.
Con DEVICE_API_KEY configurada, `-Demo` inicia además el simulador.
La web elimina cachés antiguas de Flutter y se construye con `--pwa-strategy=none`
para evitar clientes previos a JWT. Una sesión ausente/vencida vuelve al login.

Desde la raíz, crear `.env` si aún no existe y completar DB_PASSWORD,
DB_ROOT_PASSWORD y JWT_SECRET. Mantener las integraciones externas opcionales vacías.

```bash
docker compose config --quiet
docker compose up -d --build --wait
docker compose exec api python admin.py create-installer --email TU_EMAIL --name "Administrador"
```

La CLI pide la contraseña dos veces sin mostrarla. Abrir http://localhost:8088 e
iniciar sesión con esa cuenta. Se conservan las empresas demo y M-01; no hay cuentas
demo predefinidas. El instalador crea empresas con jefe desde la UI; el jefe agrega
participantes. Las cuentas existentes se conservan.

Para el simulador de M-01:

```bash
docker compose exec api python admin.py rotate-device-key --machine M-01
# Guardar el valor mostrado UNA VEZ en DEVICE_API_KEY dentro de .env.
docker compose --profile demo up -d --build simulator
docker compose logs -f simulator
```

Para Flutter con recarga:

```bash
cd mantenimiento_predictivo
flutter pub get
flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://127.0.0.1:8000
# Android emulator (debug):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

No se lee `.env` automáticamente en Flutter. Usar `--dart-define` o
`--dart-define-from-file=.env`. Para teléfono físico, configurar un host accesible
y `API_BIND=0.0.0.0` explícitamente en desarrollo. iOS mantiene ATS: usar HTTPS
en dispositivo; cualquier excepción HTTP local debe limitarse al proyecto debug.

Para ejecutar Python fuera de Docker: levantar solamente `docker compose up -d mariadb`,
crear un venv Python 3.12, `pip install -r requirements.txt` y
`uvicorn main:app --reload --host 127.0.0.1 --port 8000`. Si la API Docker ya estaba
activa, detenerla primero para liberar 8000. Las migraciones corren al arrancar.

## Preparar Ubuntu, Docker y DNS

Crear usuario de despliegue con clave SSH y directorio `/opt/predicta` de su propiedad.
Configurar el firewall/cloud security group para 80/443 y SSH desde las redes
administrativas; no abrir 3306/8000/8088. La pertenencia al grupo docker equivale
a privilegios de administración de la VM.

Instalar Docker desde su repositorio oficial:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
# Salir y volver a entrar por SSH antes de usar Docker sin sudo.
```

Crear registro A del DOMAIN hacia la IP pública. Crear AAAA solo si IPv6 funciona.
El certificado público requiere que DNS y puertos sean correctos. Caddy obtiene y
renueva TLS automáticamente; persistir caddy_data y caddy_config. No borrar esos
volúmenes al actualizar. No iniciar Caddy con un dominio ficticio como prueba real.

## Primer deploy manual

Transferir/clonar el repositorio a `/opt/predicta/app`, entrar ahí, crear
`.env.production` desde la plantilla y completar variables. Configurar
`APP_ENV=production`, DOMAIN, ACME_EMAIL y secretos propios. Proteger el archivo:

```bash
chmod 600 .env.production
docker compose --env-file .env.production -f docker-compose.prod.yml config --quiet
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build --wait --wait-timeout 240
docker compose --env-file .env.production -f docker-compose.prod.yml exec api python admin.py create-installer --email TU_EMAIL --name "Administrador"
curl --fail https://TU_DOMINIO/api/health
```

No combinar Compose desarrollo y producción con varios `-f`: podría publicar
puertos de desarrollo. Producción usa solamente docker-compose.prod.yml.
`config --quiet` valida sin imprimir secretos interpolados.

Si migras una instalación existente, hacer backup primero, detener sus escritores,
obtener el nombre real del volumen con `docker volume ls` y asignarlo a
DB_VOLUME_NAME. No arrancar dos servidores MariaDB sobre el mismo volumen.
No usar `down -v` ni ejecutar init.sql manualmente sobre datos existentes.
Antes de publicar, cambiar passwords heredados conocidos con
`... exec api python admin.py reset-password --email EMAIL`. Revocar en sus
proveedores las claves externas/Wi-Fi expuestas históricamente; quitarlas del árbol
actual no las elimina del historial. No se reescribe Git automáticamente.

## Autenticación y permisos

`POST /api/login` recibe email/password y devuelve `access_token`, `token_type`,
`expires_in`, id_usuario, id_empresa, nombre, rol y empresa_nombre al mismo nivel,
manteniendo el contrato usado por las pantallas. Nunca devuelve hashes/passwords.
Usar `Authorization: Bearer USER_JWT`. `GET /api/me` recupera el perfil.

- instalador: administración global existente.
- jefe: lectura y gestión en su empresa; solo puede dar de alta participantes.
- participante: lectura y chat de su empresa, sin configuración/rotación.
- dispositivos: solo sensores, alertas y GET de configuración de su propia máquina.

JWT HS256 verifica firma, emisor, audiencia y expiración. El rol/empresa se relee
en DB. No hay refresh tokens: al expirar se inicia sesión nuevamente. Cerrar sesión
borra el token local; un token copiado sigue válido hasta expirar. Para revocar
todas las sesiones de inmediato, cambiar JWT_SECRET y recrear API.
Web guarda el token solo en memoria; recargar requiere login. Android/iOS usan
flutter_secure_storage, restauran sesión con /api/me y no guardan passwords.
Los endpoints health/ready son públicos y no incluyen datos de usuarios.

## ESP32 y rotación de device keys

Copiar `secrets.example.h` como `secrets.h` junto a `arduino.ino`, completar Wi-Fi,
MACHINE_ID, API_URL=`https://TU_DOMINIO/api/sensores` y DEVICE_API_KEY.
Pegar en API_ROOT_CA el PEM raíz de la CA que firma la cadena del dominio,
obtenido y verificado en la fuente oficial de la CA. La raíz es pública, pero
`secrets.h` contiene secretos y está ignorado. Actualizar la confianza antes de
cambios de CA. Mantener `ALLOW_LOCAL_HTTP=false` en producción. No hay setInsecure.

Instalar Arduino ESP32, OneWire, DallasTemperature, DHT sensor library,
Adafruit MPU6050, Adafruit Unified Sensor y Adafruit BusIO. Seleccionar la placa
real y sus pines. El sketch requiere un directorio Arduino con nombre coincidente
(por ejemplo `arduino/arduino.ino`) al compilar con Arduino IDE/CLI; copiar allí
también secrets.h. Configurar NTP saliente UDP/123 para validar fechas TLS.

El envío ocurre en tarea FreeRTOS separada; cola de 16 lecturas, hasta tres
intentos con timeout/backoff y mismo boot_id/sequence. Se descartan nuevas lecturas
cuando la cola está llena y la lectura en envío tras agotar reintentos. La cola
no sobrevive a cortes de energía. `received_at` es recepción, no hora de muestreo;
una cola antigua puede llegar después. Riesgo local y comunicación se imprimen
por separado; la falta de red no cambia el relé. Se conservan pines, polaridad y
umbrales originales, y el fallback DHT a cero; DS18B20 ahora convierte de forma
asíncrona. La validación física del relé/sensores sigue siendo necesaria.

Generar/rotar:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml exec api python admin.py rotate-device-key --machine M-01
```

O usar `POST /api/maquinas/M-01/device-key` con JWT de instalador/jefe autorizado.
Respuesta `device_api_key` una sola vez, con Cache-Control no-store. Actualizar el
firmware/simulador al rotar: la anterior deja de funcionar inmediatamente. No hay
endpoint para recuperar una clave guardada; en DB queda únicamente SHA-256.
Una clave inválida recibe 401; una válida para otra máquina recibe 403.

## Telemetría, migraciones y alertas

Se mantienen todos los campos crudos y features. Son opcionales `sequence`
(entero no negativo), `boot_id` (identidad nueva por arranque) y `firmware_version`.
La combinación máquina/boot_id/sequence es única. Sin sequence no se deduplica;
sequence sin boot_id usa `legacy`: el cliente debe mantener un contador persistente.
Repetir identidad devuelve 200 con `duplicate: true`, sin nuevas alertas ni entrenamiento.
Se usa bloqueo por máquina e índice único para concurrencia. No cambia el algoritmo
ML, las reglas de estado, alertas por evento ni umbrales preventivos/críticos.

Migraciones SQL 003 y 004 son reiniciables porque MariaDB hace auto-commit de DDL.
`schema_version` registra nombre/checksum; un cambio de una migración aplicada
falla explícitamente. Crear una migración nueva para cambios posteriores.
`GET_LOCK` serializa migradores. Se convierten passwords antiguos a PBKDF2.
El primer arranque sobre una tabla grande puede tardar por índices/ALTER:
planificar ventana y backup. Reejecutar: `... exec api python migrate.py`.
No hay downgrade SQL automático. /api/ready comprueba DB igual que health:
los modelos se entrenan con datos, por lo que carecer de modelo no implica fallo.
Nginx renueva la resolución del servicio api usando el DNS interno de Docker,
para tolerar el cambio de IP al sustituir contenedores.

## Backups, cron y restore

Desde la raíz en Ubuntu/Bash:

```bash
bash scripts/backup_db.sh
# Desarrollo:
ENV_FILE=.env COMPOSE_FILE=docker-compose.yml bash scripts/backup_db.sh
```

Dump consistente de tablas InnoDB, gzip, fecha UTC, permisos privados y rename
atómico tras comprobar gzip. DB passwords se leen dentro del contenedor sin
colocarlos en argumentos del proceso del host. No hay borrado automático/retención.
Copiar backups cifrados fuera de la VM y probar restauración en un entorno aislado.

Cron diario, por el usuario de despliegue (ajustar ruta de instalación):

```cron
15 2 * * * cd /opt/predicta/current && BACKUP_DIR=/opt/predicta/backups /bin/bash scripts/backup_db.sh >> /opt/predicta/backup.log 2>&1
```

Restore requiere archivo explícito y escribir `RESTORE`:

```bash
bash scripts/restore_db.sh /opt/predicta/backups/ARCHIVO.sql.gz
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --wait
```

El script detiene API/web después de confirmar. Reemplaza tablas; hacer backup
del estado actual primero. Si falla deja los escritores detenidos. Nunca se ejecuta
restore automáticamente en deploy/rollback. Los scripts deben ejecutarse con Bash,
no PowerShell ni el prototipo `script.sh` (que, pese a su nombre, contiene Python).

## CI/CD y actualización

CI valida Python/tests, lint de errores, sintaxis Bash, Compose, Caddy, flutter
analyze/test/build web y un stack de integración aislado MariaDB/API/Nginx.
El deploy solo se invoca desde CI después de que todos los jobs pasen, manualmente
con workflow_dispatch y deploy=true en main. No hay deploy en pull requests.

Configurar environment `production` (y revisores si se desea) y estos **GitHub
Actions Secrets**, sin archivos privados en el repositorio:

- DEPLOY_HOST, DEPLOY_USER.
- SSH_PRIVATE_KEY: clave del usuario que administra Docker en la VM.
- SSH_KNOWN_HOSTS: entrada obtenida y verificada por un canal independiente.
- PRODUCTION_ENV: contenido completo de .env.production, incluidos DOMAIN y secretos.

Preparar `/opt/predicta/releases` escribible por ese usuario. SSH verifica el host,
transfiere el commit exacto como archivo, construye antes de actualizar, hace backup
si hay `/opt/predicta/current`, levanta Compose con espera de health y actualiza
el enlace current. El proyecto Compose siempre se llama predicta y el volumen no
depende del directorio del commit. No imprimir `docker compose config` sin --quiet
en logs públicos. El archivo privado queda con modo 600 en la VM.

Actualización manual: guardar backup, obtener la revisión deseada y ejecutar
`docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build --wait`.
En primer deploy manual no existe el enlace current del flujo CI; crearlo cuando
se adopte el layout releases, o ajustar cron a la ruta app.

## Rollback básico

Conservar directorios de releases anteriores y sus imágenes/backups. Si fallan
healthchecks no se actualiza current, pero algunos servicios pueden haberse
recreado: revisar logs y ejecutar Compose desde el release anterior compatible:

```bash
cd /opt/predicta/releases/COMMIT_ANTERIOR
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build --wait
ln -sfn /opt/predicta/releases/COMMIT_ANTERIOR /opt/predicta/current
```

El rollback de aplicación mantiene el esquema aditivo. Si versiones anteriores
no son compatibles, detener la actualización y planificar restore explícito;
no bajar versiones MariaDB sobre el mismo volumen ni restaurar automáticamente.
Conservar secretos actuales (o actualizar el env del release) para no invalidar
sesiones por accidente ni usar passwords DB antiguos.

## Flutter Web, APK y App Bundle

```bash
cd mantenimiento_predictivo
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
flutter build apk --release --dart-define=API_BASE_URL=https://TU_DOMINIO
flutter build appbundle --release --dart-define=API_BASE_URL=https://TU_DOMINIO
# En macOS con Xcode y firma configurados:
flutter build ios --release --dart-define=API_BASE_URL=https://TU_DOMINIO
```

Web release usa siempre origen actual + /api y no necesita dart-define. Dockerfile
web compila y sirve el bundle. Móviles release exigen origen HTTPS explícito.
Configurar firma Android propia para distribución (el proyecto conserva su ajuste
de firma previo); ignorar keystores y key.properties. iOS requiere cuenta/certificados
de firma y Keychain según el entorno de flutter_secure_storage. Para conservar
compilación desktop Linux con el nuevo plugin, instalar `libsecret-1-dev` y
`libjsoncpp-dev` (aunque allí el token solo se mantenga en memoria). No se afirma que
los builds móviles hayan sido comprobados desde Windows.

## Logs y troubleshooting

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml ps
docker compose --env-file .env.production -f docker-compose.prod.yml logs --tail=100 api web caddy mariadb
curl --fail https://TU_DOMINIO/api/health
```

| Problema | Revisar |
|---|---|
| 401 usuario | Expiración, JWT_SECRET, nueva sesión; token móvil persistido |
| 401 IoT | DEVICE_API_KEY actual y Authorization; JWT de usuario no sirve |
| 403 | Empresa/rol o maquina_id distinta de la clave |
| 429 login | Esperar; Nginx limita intentos; detrás de Caddy el límite se comparte por proxy |
| 502 / unhealthy | Estado de DB, migraciones y logs; no exponer puertos para resolverlo |
| Certificado | DNS A/AAAA, firewall, reloj/NTP y CA configurada en ESP32 |
| CORS debug | Origin exacto con puerto en CORS_ORIGINS; recrear API |
| Datos antiguos | edad_segundos usa received_at; cola ESP32 no es almacenamiento duradero |
| Migración checksum | No editar una aplicada; añadir SQL nuevo |
| Password DB rechazado | El env no modifica credenciales dentro de un volumen existente |
| UI no muestra detalle interno | Intencional: errores públicos genéricos; revisar logs internos |
| Python Windows DLL | Usar Python 3.12 limpio o imagen Docker; no reutilizar venv incompatible |

Referencias de implementación: [JWT FastAPI](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/),
[Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy),
[Compose health dependencies](https://docs.docker.com/compose/how-tos/startup-order/),
[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage),
[Docker en Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
