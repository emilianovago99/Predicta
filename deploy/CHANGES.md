# Archivos creados/modificados

## Ajuste posterior para trabajo local

- `scripts/start_local.ps1`: reconstruye e inicia el Compose de desarrollo, espera
  los healthchecks y comprueba la API a través de Nginx; `-Demo` es opcional.
- `mantenimiento_predictivo/web/index.html`: retira workers y cachés antiguas de
  Flutter antes de cargar el cliente actual. Docker/CI compilan sin caché offline.
- `mantenimiento_predictivo/lib/services/api.dart`: una respuesta 401 sin token
  también vuelve al login, sin duplicar avisos ni invalidar una sesión más nueva.
  Se añadieron dos pruebas de regresión.
- README y guía de despliegue: arranque local y Flutter con recarga rápida.
- `.env` local (ignorado por Git): puertos loopback, CORS local y credenciales de
  MariaDB verificadas contra el volumen existente. No se borraron datos ni se
  cambiaron contraseñas en MariaDB. Producción conserva su Compose separado.

## Preparación inicial de producción

54 archivos en la preparación inicial; no se realizó deploy público. En esa fase
no se modificaron los valores de `.env` existentes.

| Archivo | Cambio |
|---|---|
| [.dockerignore](../.dockerignore) | Excluye secretos, claves, backups y archivos privados del contexto de build. |
| [.env.example](../.env.example) | Plantilla sin passwords reales; variables de JWT, CORS, dominio, DB y dispositivo. |
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | Tests/lint backend, Flutter analyze/test/build, Compose/Caddy y stack aislado. |
| [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) | Deploy reusable tras CI, SSH verificado, Secrets, backup previo y releases por commit; no ejecutado. |
| [.gitignore](../.gitignore) | Ignora secretos de firmware, env de producción, claves y dumps. |
| [Dockerfile](../Dockerfile) | Incluye módulos de seguridad/configuración, CLI administrativa y migraciones. |
| [README.md](../README.md) | Inicio y arquitectura actuales; elimina instrucciones inseguras/contradictorias y enlaza guía. |
| [admin.py](../admin.py) | Alta de instalador, cambio de password y rotación de clave vía acceso administrativo local. |
| [arduino.ino](../arduino.ino) | TLS con CA, secretos externos, tarea de red, cola limitada, reconexión, timeout/backoff e identidad de lectura; mantiene relé/umbrales. |
| [database.py](../database.py) | Conexión MariaDB compartida y password obligatorio desde entorno. |
| [deploy/CHANGES.md](../deploy/CHANGES.md) | Inventario completo con explicación por archivo. |
| [deploy/Caddyfile](../deploy/Caddyfile) | TLS, proxy a web, headers y healthcheck interno. |
| [deploy/PLAN.md](../deploy/PLAN.md) | Diagnóstico, cambios DB, incompatibilidades y plan de fases comunicado. |
| [deploy/README.md](../deploy/README.md) | Guía completa de desarrollo, VM, TLS, operación, backups, rollback, Flutter e IoT. |
| [deploy/VALIDATION.md](../deploy/VALIDATION.md) | Evidencia de pruebas y limitaciones verificadas. |
| [docker-compose.prod.yml](../docker-compose.prod.yml) | Stack separado, persistencia, redes, dependencias saludables y solo Caddy público. |
| [docker-compose.yml](../docker-compose.yml) | Desarrollo conservado; secretos obligatorios, JWT y simulador autenticado. |
| [docker/nginx.conf](../docker/nginx.conf) | Proxy /api preservado, DNS Docker renovable al reemplazar API, headers y límites de tamaño/login. |
| [init.sql](../init.sql) | Elimina DROP y usuarios con passwords predeterminados; mantiene esquema/datos demo. |
| [main.py](../main.py) | JWT en login, autorización por empresa/rol, ingestión autenticada/deduplicada, received_at, health/ready/me, rotación y errores seguros; ML preservado. |
| [mantenimiento_predictivo/.env.example](../mantenimiento_predictivo/.env.example) | Aclara configuración explícita con dart-define-from-file. |
| [mantenimiento_predictivo/README.md](../mantenimiento_predictivo/README.md) | Comandos reales y comportamiento de sesión/URL. |
| [mantenimiento_predictivo/android/app/src/debug/AndroidManifest.xml](../mantenimiento_predictivo/android/app/src/debug/AndroidManifest.xml) | Mantiene HTTP de desarrollo. |
| [mantenimiento_predictivo/android/app/src/main/AndroidManifest.xml](../mantenimiento_predictivo/android/app/src/main/AndroidManifest.xml) | Release deshabilita HTTP claro y backup de datos sensibles. |
| [mantenimiento_predictivo/android/app/src/profile/AndroidManifest.xml](../mantenimiento_predictivo/android/app/src/profile/AndroidManifest.xml) | Mantiene HTTP para perfilado local. |
| [mantenimiento_predictivo/lib/app.dart](../mantenimiento_predictivo/lib/app.dart) | Guarda JWT, restaura sesión móvil, redirige al expirar y retira cuentas/servidor de demostración de UI. |
| [mantenimiento_predictivo/lib/config/api_config.dart](../mantenimiento_predictivo/lib/config/api_config.dart) | Web release usa origen actual; móvil release exige API_BASE_URL HTTPS. |
| [mantenimiento_predictivo/lib/services/api.dart](../mantenimiento_predictivo/lib/services/api.dart) | ApiClient único, Bearer, manejo 401/403/429/timeouts/errores, token seguro móvil y memoria web. |
| [mantenimiento_predictivo/lib/workspace.dart](../mantenimiento_predictivo/lib/workspace.dart) | Logout borra sesión/token antes de volver al login. |
| [mantenimiento_predictivo/linux/flutter/generated_plugin_registrant.cc](../mantenimiento_predictivo/linux/flutter/generated_plugin_registrant.cc) | Registro generado por flutter pub get para plugins de almacenamiento seguro y sus dependencias. |
| [mantenimiento_predictivo/linux/flutter/generated_plugins.cmake](../mantenimiento_predictivo/linux/flutter/generated_plugins.cmake) | Registro generado por flutter pub get para plugins de almacenamiento seguro y sus dependencias. |
| [mantenimiento_predictivo/macos/Flutter/GeneratedPluginRegistrant.swift](../mantenimiento_predictivo/macos/Flutter/GeneratedPluginRegistrant.swift) | Registro generado por flutter pub get para plugins de almacenamiento seguro y sus dependencias. |
| [mantenimiento_predictivo/pubspec.lock](../mantenimiento_predictivo/pubspec.lock) | Resolución de almacenamiento seguro y dependencias transitivas. |
| [mantenimiento_predictivo/pubspec.yaml](../mantenimiento_predictivo/pubspec.yaml) | Dependencia flutter_secure_storage. |
| [mantenimiento_predictivo/test/api_test.dart](../mantenimiento_predictivo/test/api_test.dart) | Prueba Bearer, limpieza de sesión, permisos, errores HTML y timeout. |
| [mantenimiento_predictivo/windows/flutter/generated_plugin_registrant.cc](../mantenimiento_predictivo/windows/flutter/generated_plugin_registrant.cc) | Registro generado por flutter pub get para plugins de almacenamiento seguro y sus dependencias. |
| [mantenimiento_predictivo/windows/flutter/generated_plugins.cmake](../mantenimiento_predictivo/windows/flutter/generated_plugins.cmake) | Registro generado por flutter pub get para plugins de almacenamiento seguro y sus dependencias. |
| [migrate.py](../migrate.py) | Runner SQL versionado, checksums/bloqueo y conversión de passwords heredados. |
| [migrations/003_temp_ambiente_evento.sql](../migrations/003_temp_ambiente_evento.sql) | Migración heredada reiniciable, incluye features opcionales antiguas. |
| [migrations/004_security_telemetry.sql](../migrations/004_security_telemetry.sql) | Credenciales por máquina, metadatos de ingestión, identidad única e índices. |
| [requirements.txt](../requirements.txt) | Añade PyJWT y cliente HTTP para pruebas FastAPI. |
| [script.sh](../script.sh) | Retira clave externa incrustada del prototipo Python y autentica alertas por entorno. |
| [scripts/backup_db.sh](../scripts/backup_db.sh) | Dump gzip fechado, permisos privados y publicación atómica. |
| [scripts/restore_db.sh](../scripts/restore_db.sh) | Archivo obligatorio, validación gzip y confirmación explícita antes de detener escritores/restaurar. |
| [secrets.example.h](../secrets.example.h) | Plantilla de configuración ESP32 y certificado raíz, sin credenciales. |
| [security.py](../security.py) | PBKDF2, JWT verificable, dependencias reutilizables, aislamiento de recursos y device keys hasheadas. |
| [settings.py](../settings.py) | Carga/env, validación de secretos y CORS según entorno. |
| [simulador_cambio.py](../simulador_cambio.py) | Mantiene simulación de cambios bruscos, añade autenticación e identidad de telemetría. |
| [simulador_edge.py](../simulador_edge.py) | Mantiene simulación/ML, añade clave de dispositivo e identidad de telemetría. |
| [tests/compose.test.yml](../tests/compose.test.yml) | Imágenes y puertos aislados y montaje de tests para ejecución en contenedor. |
| [tests/run_stack.py](../tests/run_stack.py) | Crea stack efímero; prueba datos heredados, reemplazo de API, backup/cancelación y preserva volumen al finalizar. |
| [tests/smoke.py](../tests/smoke.py) | Flujos reales por Nginx, roles, empresa, rotación y deduplicación concurrente. |
| [tests/test_logic.py](../tests/test_logic.py) | Adapta pruebas existentes al rechazo de plaintext y autenticación de telemetría. |
| [tests/test_security.py](../tests/test_security.py) | Tests de JWT, aislamiento, permisos, rutas protegidas, deduplicación, redacción y health. |
