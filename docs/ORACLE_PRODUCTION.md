# Predicta en Oracle Cloud

- Dominio de producción: `https://isthisabank.tech`.
- IP pública: `129.80.170.15`; IP privada: `10.0.0.37`.
- Ubuntu 24.04, acceso SSH con usuario `ubuntu`.
- Versión inicial: `de55386a402e9ccbe5a5254f3b3d45a11afa6ac6`; consultar la
  versión activa con `sudo readlink -f /opt/predicta/current`.
- Directorio activo: `/opt/predicta/current`.
- Configuración privada: `/opt/predicta/current/.env.production`, permiso 600.
- Datos conservados: volumen `predicta_mariadb_data`.
- Certificado de Let's Encrypt administrado y renovado por Caddy.
- Solo Caddy publica puertos de Predicta: TCP 80 y 443.

El despliegue anterior de `/root/Predicta` se sustituyó por Compose de producción.
La base tenía dos empresas y una máquina, sin usuarios ni mediciones. Se creó
un instalador inicial y contraseñas independientes para producción. El `.env`
local de Windows sigue siendo de desarrollo y no se copió sobre producción.
Las credenciales iniciales están en `artifacts/private/oracle-access.json`,
ignorado por Git. No adjuntar ese archivo a incidencias ni compartirlo con sensores.

## Operación

Conectarse desde PowerShell:

```powershell
ssh -i C:\Users\emili\.ssh\esclavo.key ubuntu@129.80.170.15
```

En el servidor:

```bash
sudo -i
cd /opt/predicta/current
docker compose --env-file .env.production -f docker-compose.prod.yml ps
docker compose --env-file .env.production -f docker-compose.prod.yml logs --tail=80 api caddy
curl --fail https://isthisabank.tech/api/health
```

No ejecutar el Compose de desarrollo en paralelo sobre esta base. No usar
`down -v`. Las futuras publicaciones deben crear otra carpeta en
`/opt/predicta/releases/`, conservar el archivo privado de entorno y respaldar la
base antes de migrar. El enlace `current` indica la versión activa.

## Actualizar cuando haya cambios en main

Hacer push a GitHub **no actualiza Oracle automáticamente**. El flujo actual es
publicar los cambios en `main`, comprobar que CI pase y ejecutar el actualizador
por SSH. GitHub Actions no tiene configurados los secretos de despliegue de Oracle.

### 1. Publicar y comprobar main

Trabajar en una rama, subirla y fusionar su pull request a `main`. Si los cambios
ya están en `main`, no necesitas volver a publicarlos. En GitHub → Actions,
esperar a que termine correctamente CI para el commit que quieres desplegar.
El actualizador descarga la revisión de `main` disponible al comenzar; no
consulta el resultado de CI ni publica cambios locales sin commit.

### 2. Entrar a Oracle desde PowerShell

```powershell
ssh -i C:\Users\emili\.ssh\esclavo.key ubuntu@129.80.170.15
```

### 3. Consultar y actualizar

Dentro de Ubuntu:

```bash
# Opcional: muestra la versión instalada y la última de main, sin desplegar.
sudo bash /opt/predicta/current/scripts/update_oracle.sh --check

# Descarga main y actualiza la aplicación.
sudo bash /opt/predicta/current/scripts/update_oracle.sh
```

Mantener abierta la terminal hasta ver `Deployment complete`. La compilación
puede tardar varios minutos. Durante la recreación de contenedores habrá una
interrupción breve; los sensores deben reintentar sus envíos. Si no hay cambios,
el script comprueba HTTPS y termina sin reconstruir.

El script usa el repositorio `/root/Predicta` como origen de descarga. Ejecuta
`git fetch` y extrae el commit exacto, sin cambiar el checkout ni hacer `git reset`.
Conserva `.env.production`, claves, base y volúmenes de certificados, construye
API/web y hace un respaldo **antes** de recrear contenedores y aplicar migraciones.
Solo cambia `current` cuando los servicios están saludables y el dominio público
responde con API y base disponibles. Guarda la ruta anterior en
`/opt/predicta/previous` y el registro en `/opt/predicta/deployments/`.

No regenera usuarios, contraseñas, JWT ni claves de sensores. Si un cambio de
código requiere una variable nueva, añadirla al `.env.production` activo antes
de actualizar. No copiar encima el `.env` de Windows. Los cambios de esquema
deben usar migraciones nuevas, compatibles con los datos existentes.

### 4. Verificar

```bash
curl --fail https://isthisabank.tech/api/health
sudo readlink -f /opt/predicta/current
```

La respuesta debe incluir `"status":"ok"` y `"database":"ok"`. Abrir
`https://isthisabank.tech` y recargar; si ya estaba abierta con el código anterior,
usar Ctrl+F5. La app móvil instalada requiere compilar y distribuir una nueva
APK/versión cuando cambie su interfaz; actualizar Oracle actualiza web y API.

### Si falla

Leer el archivo de log indicado al final. Los respaldos están en
`/opt/predicta/backups`. Si falla la compilación o el respaldo, los contenedores
actuales no se recrean. Si falla durante arranque o HTTPS, `current` conserva la
ruta anterior, pero algunos contenedores o migraciones **ya pueden haber cambiado**.
Revisar el diagnóstico antes de reintentar el mismo comando.

No hay restauración automática ni borrado de volúmenes. Para volver al código
anterior puede ser necesario reconstruir sus imágenes: las etiquetas de Compose
se reutilizan. Ver [rollback y restauración](../deploy/README.md#rollback-básico),
comprobando primero la compatibilidad con el esquema actual. No ejecutar en
paralelo el actualizador y otro despliegue manual o de GitHub Actions.

### Instalar el actualizador si el release activo aún no lo incluye

Solo para una instalación existente con `/opt/predicta/current` y el checkout
`/root/Predicta`, ejecutar por SSH:

```bash
sudo -i
git -C /root/Predicta fetch origin main
umask 077
git -C /root/Predicta show origin/main:scripts/update_oracle.sh > /opt/predicta/update_oracle-bootstrap.sh
bash /opt/predicta/update_oracle-bootstrap.sh
exit
```

Después, usar el comando habitual de `/opt/predicta/current/scripts/`.

## Red y certificado

El registro A de `isthisabank.tech` debe apuntar a `129.80.170.15`. La Security
List de la subred o un NSG **asociado a la VNIC de la instancia** debe permitir
entrada TCP 80 y 443 desde `0.0.0.0/0`, con cualquier puerto de origen. No confundir
puerto de origen con puerto de destino. SSH conserva su configuración existente.

Si `/api/health` responde dentro de Oracle pero no desde Internet, revisar las
reglas del NSG/subred. Un contenedor saludable y un certificado emitido no prueban
por sí solos que el puerto público 443 esté accesible.

Se verificó el acceso público a `https://isthisabank.tech/api/health`, con respuesta
`{"status":"ok","database":"ok"}`, después de agregar 443 a la Security List
asociada a la subred de la instancia. La prueba de navegador sobre el dominio
público confirmó inicio de sesión, persistencia tras recargar, cookie Secure y
HttpOnly, acceso a Telegram e instalación y cierre de sesión sin errores de
JavaScript. También pasaron las 24 pruebas unitarias del backend en la imagen
desplegada.

## Respaldo y acceso

Se verificó un respaldo antes de migrar. Los respaldos están en
`/opt/predicta/backups` y son privados del administrador. El trabajo programado
`/etc/cron.d/predicta-backup` ejecuta el backup diario a las 03:15 según el reloj
del servidor. Revisar espacio y copiar periódicamente backups a otra ubicación;
no se configuró almacenamiento externo ni eliminación automática de respaldos.

Para generar otro respaldo:

```bash
cd /opt/predicta/current
sudo BACKUP_DIR=/opt/predicta/backups bash scripts/backup_db.sh
```

Para cambiar la contraseña de acceso de una cuenta:

```bash
sudo docker compose --env-file .env.production -f docker-compose.prod.yml exec api \
  python admin.py reset-password --email CORREO_DE_LA_CUENTA
```

## Sensores y Telegram

En **Telegram e instalación**, el servidor es `https://isthisabank.tech`.
Las mediciones se envían a `https://isthisabank.tech/api/sensores`, con ID y clave
de dispositivo. La IP del sensor la asigna DHCP. No usar `localhost`, la IP privada
de Oracle ni `predicta.planta` desde una red externa.

Seleccionar o crear el destino de Telegram desde cada máquina. No se enviaron
mensajes reales ni se aprovisionaron dispositivos físicos durante el despliegue.
Ver [la guía del equipo de sensores](SENSORES_E_INSTALACION.md).
