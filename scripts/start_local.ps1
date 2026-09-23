[CmdletBinding()]
param([switch]$Demo)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath '.env')) {
        throw 'Crea .env desde .env.example y completa DB_PASSWORD, DB_ROOT_PASSWORD y JWT_SECRET.'
    }
    $localConfig = @{}
    Get-Content -LiteralPath '.env' | ForEach-Object {
        if ($_ -match '^([A-Z_]+)=(.*)$') { $localConfig[$matches[1]] = $matches[2].Trim() }
    }
    if ($Demo -and -not $localConfig['DEVICE_API_KEY']) {
        throw 'Configura DEVICE_API_KEY antes de usar -Demo. Consulta README.md para generar una clave.'
    }
    docker compose -f docker-compose.yml config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Revisa las variables de .env.' }
    # Rebuild so the browser and API always use the current source code.
    docker compose -f docker-compose.yml up -d --build --wait --wait-timeout 240 api web
    if ($LASTEXITCODE -ne 0) { throw 'Fallo al arrancar. Revisa: docker compose logs --tail=80 api web' }
    if ($Demo) {
        docker compose -f docker-compose.yml --profile demo up -d --build simulator
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar el simulador.' }
    }
    $webPort = if ($localConfig['WEB_PORT']) { $localConfig['WEB_PORT'] } else { '8088' }
    $health = Invoke-RestMethod -Uri "http://localhost:$webPort/api/health" -TimeoutSec 15
    if ($health.status -ne 'ok') { throw 'Fallo la comprobacion de API/MariaDB.' }
    Write-Host "Predicta local listo: http://localhost:$webPort"
    Write-Host 'Inicia sesion con tu cuenta. No se requiere dominio ni HTTPS para este entorno local.'
} finally {
    Pop-Location
}
