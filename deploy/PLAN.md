# Diagnóstico y plan previo a implementación

Se revisaron Compose/Dockerfiles/Nginx, backend monolítico con SQL directo y ML,
init y migración 003, login/cliente/monitoreo Flutter, firmware, ambos simuladores,
variables (sin reproducir valores sensibles), exclusiones Git y README.

## Estado encontrado

- Login sin sesión verificable; permisos solo visuales y endpoints públicos.
- PBKDF2 existente para altas, pero seed y compatibilidad de login en texto plano.
- Clave externa incrustada en script.sh, Wi-Fi/IP en firmware y cuentas en UI/README.
- CORS universal, errores HTTP con detalles internos, init con DROP TABLE.
- Migración aditiva al arrancar sin historial/checksum; SQL directo, sin ORM.
- Persistencia MariaDB y healthchecks existentes. Sin Compose de producción/TLS.
- Cliente HTTP Flutter centralizado parcialmente, sin token. Firmware con esperas
  de Wi-Fi/HTTP y conversión DS18B20 dentro de la evaluación de seguridad.
- Se preservan umbrales, modelos ML, alertas, chat, multiempresa y simuladores.

## Archivos previstos

La lista comunicada antes de editar cubre backend/datos, infraestructura, IoT,
Flutter, tests, CI y documentación. Se concretó en el inventario de
[CHANGES.md](CHANGES.md). Durante validación se añadió `tests/run_stack.py` para
crear un proyecto aislado con credenciales efímeras, conservando sus volúmenes,
y `deploy/VALIDATION.md` para registrar evidencia y limitaciones.

## Datos e incompatibilidades

- `schema_version` con checksum y bloqueo de migraciones.
- `DeviceCredential`: una clave SHA-256 por máquina; generación aleatoria de
  256 bits y devolución solo al generar/rotar. No es un password de baja entropía.
- `SensorData`: sequence, boot_id, firmware_version, received_at e índices.
  Se rellena received_at histórico desde fecha. Identidad única por máquina,
  arranque y secuencia. Payloads antiguos siguen admitidos tras autenticarse.
- Conversión de passwords heredados a PBKDF2 sin cambiar su valor ni borrar usuarios.
- Clientes antiguos sin token dejan de acceder; no se mantiene acceso anónimo.
- Sin contraseñas predeterminadas: alta inicial por CLI local. Rotación de device
  keys invalida la anterior inmediatamente. JWT sigue vigente hasta expirar.
- Volúmenes existentes requieren sus passwords actuales y nombre de volumen correcto.
  No se reejecuta init.sql en volúmenes existentes ni se usa down -v.

## Fases

1. Retirar secretos y añadir plantillas/exclusiones.
2. JWT con expiración y dependencias; permisos actuales y aislamiento por empresa.
3. Claves independientes por máquina y rotación administrativa.
4. Metadatos y deduplicación antes de efectos de alertas.
5. HTTPS ESP32 con CA, tarea de red, cola y reintentos limitados.
6. Compose producción, Caddy, persistencia, redes y healthchecks.
7. CORS explícito, headers y errores públicos genéricos.
8. ApiClient Flutter, JWT, almacenamiento móvil, manejo de errores y logout.
9. SQL versionado idempotente, adelantado cuando lo requirieron fases 2–4.
10. Backup comprimido y restore con confirmación explícita.
11. Health/ready con comprobación de MariaDB; ML de entrenamiento diferido.
12. CI y deploy SSH condicionado a CI, sin ejecución de deploy real.
13. Documentación y comprobaciones; registrar lo no ejecutado.
