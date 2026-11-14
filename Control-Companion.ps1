param([string]$Config, [string]$RasaUrl = 'http://127.0.0.1:5005')
$ErrorActionPreference = 'Stop'
$serviceRoot = Join-Path $PSScriptRoot 'services/controller'
$pythonExe = Join-Path $serviceRoot '.venv/Scripts/python.exe'
$arguments = @('-m','echo_controller.companion_gateway','--rasa-url',$RasaUrl)
if ($Config) { $arguments += @('--config', (Resolve-Path -LiteralPath $Config).Path) }
Push-Location $serviceRoot
try { & $pythonExe @arguments } finally { Pop-Location }
