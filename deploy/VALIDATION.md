# Validación realizada — 2026-09-23

## Ajuste local posterior — 2026-09-23

- `scripts/start_local.ps1` ejecutado: reconstrucción de API/web y los tres
  contenedores `hack` saludables, conservando el volumen de MariaDB.
- `/api/health` devuelve `ok` tanto en 8000 como por Nginx en 8088.
- Preflight CORS desde `http://localhost:5173`: 200 y origen permitido.
- `flutter analyze`: sin incidencias. `flutter test`: seis pruebas aprobadas.
- Build web con `--pwa-strategy=none`: completado.
- Edge headless contra localhost:8088: login real y GET empresas con Bearer/200.
- Migración de caché en un proxy local de prueba: el worker heredado de Flutter
  servía JavaScript obsoleto; el nuevo index lo eliminó y permitió login/empresas.
- Respuesta 401 simulada en el navegador: regreso al login verificado.
- Sintaxis del script PowerShell y `git diff --check`: sin errores.

Se ajustó el `.env` local ignorado por Git y se verificaron las credenciales de
la base existente. No se borraron datos ni se cambiaron contraseñas en MariaDB.
No se ejecutó el Compose de producción ni se publicó la aplicación.

## Comprobaciones de la preparación inicial

| Comprobación | Resultado observado |
|---|---|
| Backend unitario/seguridad | 15 tests aprobados con Python 3.12 en Docker, incluidas reglas ML existentes |
| Stack MariaDB 10.11/API/Nginx | Login, alta transaccional, áreas/máquinas, configuración, sensores, predicción y chat fallback aprobados |
| Permisos reales | 401 sin credencial; 403 por empresa/rol/máquina; jefe no eleva roles; participante solo lectura |
| Rotación IoT | Clave anterior rechazada con 401 tras rotación |
| Deduplicación concurrente | Cuatro POST con identidad igual: una inserción y tres respuestas duplicate |
| Reinicio de contador | Nueva boot_id permite la misma sequence |
| Migración de datos | Usuario plaintext convertido a hash sin cambiar acceso; lectura previa preservada y received_at=fecha |
| Migración repetida | Runner ejecutado dos veces sobre la misma DB sin borrar datos |
| Actualización API | Contenedor API sustituido y /api/health accesible nuevamente por Nginx |
| Backup | Dump MariaDB real comprimido; gzip leído y tablas principales presentes |
| Protección restore | Respuesta CANCEL termina con código 1 antes de importar o detener escritores |
| Flutter | 4 tests del ApiClient aprobados |
| Flutter analyze | Sin incidencias tras corregir un aviso de llaves |
| Flutter Web release | Build JavaScript aprobado, también mediante docker/web.Dockerfile |
| Docker backend | Dockerfile construido con Python 3.12 |
| Compose | config --quiet aprobado para desarrollo y producción con valores efímeros de prueba |
| Exposición producción | Aserción JSON: solo Caddy publica 80/443; no existe servicio simulator |
| Caddy | caddy validate: Valid configuration; formato oficial aplicado |
| Python lint | ruff check --select E9,F63,F7,F82: All checks passed |
| Python sintaxis | compileall aprobado |
| Bash | bash -n de backup_db.sh y restore_db.sh aprobado |
| Workflows | YAML parseado sin errores; no ejecutados en GitHub |
| Exclusiones | git check-ignore confirmó .env, .env.production, secrets.h, dump y key.properties |
| Revisión Git | git diff --check sin errores de whitespace; sin commits |

El test reproducible es `python tests/run_stack.py`. Usa puertos de loopback
18080/18000/13307 y un nombre de proyecto aleatorio. Se ejecutó de nuevo tras
el ajuste DNS para verificar también reemplazo de API. Los contenedores/redes de
prueba se detuvieron; se conservaron, sin borrar, los volúmenes:

- predicta-test-6bc97b9b_mariadb_data
- predicta-test-b387e1e7_mariadb_data

En la preparación inicial no se reiniciaron ni migraron los contenedores
hack/lamp que ya estaban en marcha y el `.env` original no se modificó.
Los secrets de test fueron efímeros y no se
incorporaron al código ni se usaron como credenciales de producción.

## Limitaciones y avisos observados

- El intento de tests en el venv local Python 3.9 falló al cargar la DLL `_rust`
  de cryptography. La validación del backend sí pasó en el entorno Docker Python
  3.12. No se declara reparado el venv antiguo.
- Flutter Web emitió avisos de dry-run Wasm por dart:html/dart:js del plugin
  flutter_secure_storage_web 9.x, y de fuente Cupertino. El build JavaScript
  final terminó correctamente; no se afirma soporte de compilación Wasm.
- Se observaron avisos de deprecación de google.generativeai y de la integración
  httpx de Starlette. Se conservó el SDK Gemini existente para evitar migrar
  componentes fuera de alcance. No se probaron llamadas reales Gemini/Telegram;
  las integraciones se desactivaron en el stack de prueba.
- No se compiló el firmware: arduino-cli no está disponible. No se probaron placa,
  sensores, relé, desconexión física, NTP ni cadena TLS real del dispositivo.
- No se ejecutaron builds APK/App Bundle/iOS ni almacenamiento Keychain/Keystore
  en dispositivos. Se documentaron los comandos y los requisitos de firma.
- No se ejecutó restore destructivo; se verificaron sintaxis, creación/lectura del
  dump y cancelación. Una restauración completa debe ensayarse con autorización
  explícita y una base destinada a ello.
- No hubo despliegue público, emisión ACME para un dominio real, SSH a una VM,
  ejecución GitHub Actions ni prueba cron en Ubuntu. Caddy y Compose se validaron
  localmente; los workflows quedaron preparados.

Antes de publicar hay que proporcionar dominio/secretos propios, cambiar las
contraseñas heredadas conocidas, revocar claves expuestas históricamente y
provisionar el ESP32 con una CA verificada. No se reescribió el historial Git.
