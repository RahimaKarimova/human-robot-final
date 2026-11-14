param([switch]$Train,[ValidateRange(1024,65535)][int]$Port=5006)
$ErrorActionPreference='Stop'
$service=Join-Path $PSScriptRoot 'services/rasa'
$python=Join-Path $service '.venv/Scripts/python.exe'
$oldTelemetry=$env:RASA_TELEMETRY_ENABLED
$oldTf=$env:TF_CPP_MIN_LOG_LEVEL
try {
    $env:RASA_TELEMETRY_ENABLED='false'
    $env:TF_CPP_MIN_LOG_LEVEL='2'
    Push-Location $service
    try {
        & $python build_conversation_data.py
        if ($LASTEXITCODE -ne 0) {throw 'Conversation data generation failed.'}
        if ($Train -or -not (Test-Path models/echo_conversation.tar.gz)) {
            & $python run_local.py train --config conversation/config.yml --domain conversation/domain.yml --data conversation --out models --fixed-model-name echo_conversation --quiet
            if ($LASTEXITCODE -ne 0) {throw 'Conversation policy training failed.'}
        }
        Write-Host "Starting planned Rasa conversation on localhost:$Port. No microphone is opened."
        & $python run_local.py run --enable-api --interface 127.0.0.1 --port $Port --model models/echo_conversation.tar.gz --credentials conversation/credentials.yml --quiet
        if ($LASTEXITCODE -ne 0) {throw 'Conversation router exited.'}
    } finally {Pop-Location}
} finally {
    $env:RASA_TELEMETRY_ENABLED=$oldTelemetry
    $env:TF_CPP_MIN_LOG_LEVEL=$oldTf
}
