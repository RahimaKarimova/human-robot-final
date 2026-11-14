param([switch]$Train, [ValidateRange(1024,65535)][int]$Port = 5005)
$ErrorActionPreference = 'Stop'
$serviceRoot = Join-Path $PSScriptRoot 'services/rasa'
$pythonExe = Join-Path $serviceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) { throw 'Set up the separate Rasa environment. See services/rasa/README.md.' }
$priorTelemetry = $env:RASA_TELEMETRY_ENABLED
$priorTfLog = $env:TF_CPP_MIN_LOG_LEVEL
try {
    $env:RASA_TELEMETRY_ENABLED = 'false'
    $env:TF_CPP_MIN_LOG_LEVEL = '2'
    Push-Location $serviceRoot
    try {
        & $pythonExe build_training_data.py
        if ($LASTEXITCODE -ne 0) { throw 'Synthetic training-data generation failed.' }
        if ($Train -or -not (Test-Path -LiteralPath 'models/echo_controls.tar.gz')) {
            $ErrorActionPreference = 'Continue'
            & $pythonExe run_local.py train nlu --config config.yml --nlu data/nlu.yml --out models --fixed-model-name echo_controls --quiet
            $trainExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($trainExit -ne 0) { throw 'Rasa control-model training failed.' }
        }
        Write-Host "Starting local Rasa NLU on 127.0.0.1:$Port. This does not start a microphone or robot."
        $ErrorActionPreference = 'Continue'
        & $pythonExe run_local.py run --enable-api --interface 127.0.0.1 --port $Port --model models/echo_controls.tar.gz --quiet
        $serverExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($serverExit -ne 0) { throw 'Rasa NLU server exited with an error.' }
    } finally { Pop-Location }
} finally {
    $env:RASA_TELEMETRY_ENABLED = $priorTelemetry
    $env:TF_CPP_MIN_LOG_LEVEL = $priorTfLog
}
