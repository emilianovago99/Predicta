# Predicta: guía para sensores e instaladores

## Mensaje para compartir con el equipo de sensores

Cada sensor se identifica con un **ID de máquina y una clave propia**, nunca por
su dirección IP. Puede obtener su IP automáticamente por DHCP. Debe iniciar
conexiones HTTP al servidor de Predicta en la red local o HTTPS en producción;
el servidor no necesita conectarse hacia el ESP32 ni abrir puertos en él.

El instalador entrega un paquete con `server_url`, `enrollment_code` e ID de
máquina. El firmware canjea el código una vez y guarda la clave devuelta en NVS.
En reinicios siguientes reutiliza esa clave; no repite el canje.

1. Conectar Wi-Fi/Ethernet y resolver el nombre DNS del servidor.
2. Si todavía no hay clave, enviar `POST /api/device/enroll` con
   `Authorization: Bearer <enrollment_code>`. El código vence en 10 minutos.
3. Guardar `maquina_id`, `device_api_key` y `server_url` devueltos en NVS.
4. Generar un `boot_id` aleatorio nuevo en cada arranque y comenzar `sequence=0`.
5. Cada 2 segundos enviar un JSON a `POST /api/sensores` con
   `Content-Type: application/json` y `Authorization: Bearer <device_api_key>`.
6. Ante timeout, reintentar **el mismo JSON y la misma secuencia**. Incrementar
   la secuencia para una nueva medición, no para cada reintento.

Ejemplo de medición:

```json
{
  "maquina_id": "MOTOR-02",
  "boot_id": "arranque_a914f839",
  "sequence": 1,
  "firmware_version": "esp32-1.1.0",
  "temperatura": 42.5,
  "temp_ambiente": 25.1,
  "vibracion": 2.3,
  "voltaje": 120.0,
  "velocidad": 1450,
  "humedad": 48.0
}
```

| Campo | Unidad y requisito |
|---|---|
| temperatura / temp_ambiente | °C; temperatura del motor y del ambiente |
| vibracion | mm/s, no negativa; acordar RMS y ventana con el equipo, no enviar aceleración en g como si fuera mm/s |
| voltaje | V |
| velocidad | rpm, entero no negativo |
| humedad | % entre 0 y 100 |
| boot_id | 1–64 letras, números, `_` o `-`; distinto por arranque |
| sequence | entero no negativo; creciente por arranque |
| firmware_version | texto de hasta 64 caracteres |

Todos los campos de medición del ejemplo forman parte del contrato actual.
Si un sensor no está instalado, deshabilitar su métrica en Predicta y acordar
un valor numérico de relleno con el firmware; no interpretar ese relleno como
una medición válida. No enviar `NaN`, infinito ni cadenas en lugar de números.
La hora oficial de recepción la asigna el servidor (`received_at`); el ESP32 no
tiene que mandar su reloj. No enviar claves de usuario, de Telegram ni Gemini.

| Respuesta | Acción del firmware |
|---|---|
| 200 | Aceptada; `duplicate: true` también confirma recepción previa |
| 401 | Clave/código inválido o vencido; detener reintentos rápidos y avisar al instalador |
| 403 | La clave corresponde a otra máquina; corregir el ID |
| 422 | JSON o valores inválidos; revisar contrato |
| 429 / 5xx / timeout | Espera progresiva con variación aleatoria, máximo 60 s; conservar identidad del paquete |

Limitar la cola local de reintentos. Tras recuperar conexión, espaciar el envío
para evitar ráfagas. La conexión TLS de producción debe validar la CA y el
nombre del servidor: no usar `setInsecure()`. El firmware existente puede seguir
usando una clave provisionada manualmente; para el nuevo asistente debe añadir
el canje inicial descrito arriba. Hay un cliente de referencia en
[`sensor_reference.py`](../examples/sensor_reference.py).

## Instalación de una máquina nueva

1. El instalador entra a Predicta, crea/selecciona empresa y área y registra la
   máquina con un ID permanente, por ejemplo `PRENSA-07`.
2. En **Sensores y umbrales**, activa solamente sensores instalados y configura
   los límites correspondientes al equipo.
3. En la tarjeta de la máquina abre **Telegram e instalación**.
4. Selecciona un destino Telegram existente o crea uno con nombre, token de
   BotFather y Chat ID. Varias máquinas de la **misma empresa** pueden seleccionar
   ese mismo destino. Guarda la asignación. “Sin Telegram” la desactiva.
5. En **Instalar sensor**, escribe la dirección estable del servidor y genera
   el código. Copia el paquete al firmware mediante el procedimiento del equipo
   (USB, herramienta de provisionamiento o portal local del ESP32).
6. El dispositivo canjea el código y comienza a medir. **Actualizar estado** debe
   mostrar “Recibiendo mediciones”, la última recepción y la versión de firmware.
7. Abre **Monitorear** y contrasta los valores con los instrumentos de referencia.

El código no es un QR de Wi-Fi ni configura automáticamente el router. El asistente
prepara las credenciales de Predicta; el equipo de sensores implementa la carga
del paquete y la conexión Wi-Fi. Volver a generar un código invalida el código
pendiente anterior. Canjearlo sustituye la clave anterior de esa máquina.
Un código usado o vencido no se puede reutilizar.

## Nombre de servidor y red local

Recomendación de diseño: un nombre DNS estable de la red de planta, por ejemplo
`predicta.planta`, que apunte al equipo donde corre Predicta. El administrador
de red crea ese registro y una reserva DHCP para el **servidor**. Los sensores
usan DHCP normal. Si cambia el servidor se actualiza DNS, sin reprogramar cada
sensor. Escribir un nombre en el formulario no crea el registro DNS.

La configuración actual publica Docker únicamente en la computadora. Para una
prueba con un ESP32 físico en la misma red, configurar en `.env`:

```dotenv
WEB_BIND=0.0.0.0
DEVICE_SERVER_URL=http://predicta.planta:8088
CORS_ORIGINS=http://localhost:8088,http://127.0.0.1:8088,http://localhost:5173,http://predicta.planta:8088
```

Recrear web/API con `scripts/start_local.ps1`. Permitir TCP 8088 en el firewall
solo en la red de planta y comprobar desde otro equipo que el nombre resuelve
y `/api/health` responde. La API 8000 y MariaDB pueden seguir en loopback. No se
modifica el firewall automáticamente. Para una prueba puntual se puede usar
la IP LAN del servidor; **localhost en el ESP32 apunta al propio ESP32**.

En producción usar `https://predicta.tudominio.com`, DNS y certificado válidos.
No es necesario publicar la IP de cada máquina ni abrir puertos hacia sensores.

## Alertas y Telegram

La app muestra una tarjeta que se actualiza, sin una ventana emergente por lectura.
Las alertas se resumen con reglas y mediciones; los párrafos de IA no se envían
a Telegram. Se conserva el chat de IA como consulta voluntaria.

- Un incidente agrupa repeticiones por máquina. Se recuerda cada 15 minutos
  por defecto (configurable desde 5 minutos).
- Una subida a crítico queda pendiente sin esperar ese recordatorio. La entrega
  respeta el límite del destino: hasta un resumen por minuto, cinco máquinas por
  mensaje, prioridad a incidentes críticos.
- Tres lecturas consecutivas de menor gravedad permiten bajar de nivel; tres
  normales confirman recuperación.
- Las notificaciones no críticas se envían sin sonido. Ante 429 se respeta la
  espera indicada por Telegram. La cola sobrevive reinicios de la API.
- Sin una asignación por máquina no se envía a Telegram. Las variables globales
  antiguas `TELEGRAM_BOT_TOKEN/CHAT_ID` ya no eligen destinatarios de alertas.

Ejemplo:

```text
🔴 Motor principal · M-01
Límite crítico superado
Motor: 85 °C · límite 80
Vibración: 8.1 mm/s · límite 7
Revisa el equipo y aplica el protocolo de parada de tu planta.
2026-09-23 18:40:00 UTC
```

El bot debe estar agregado al grupo o el usuario debe abrir su chat con `/start`.
El token se guarda cifrado y no se vuelve a entregar al navegador. El cifrado
depende de `JWT_SECRET`: conservarlo en backups; si se cambia, volver a cargar
las credenciales de Telegram. Estado de entrega visible en el diálogo de máquina.
Documentación oficial: [sendMessage](https://core.telegram.org/bots/api#sendmessage)
y [límites de envío](https://core.telegram.org/bots/faq#my-bot-is-hitting-limits-how-do-i-avoid-this).

## Sesión e iconos

La web conserva la sesión al recargar usando cookie HttpOnly, SameSite=Lax y
Secure en producción; caduca según `JWT_EXPIRES_SECONDS` (una hora por defecto).
Cerrar sesión elimina la cookie. El token no se guarda en localStorage.
Android/iOS conservan almacenamiento seguro. Los iconos nativos requieren
reconstruir/reinstalar la app; el favicon se actualiza al recargar la web.
