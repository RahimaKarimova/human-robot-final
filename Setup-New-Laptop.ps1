param([ValidateRange(1,9)][int]$LaptopNumber=0)
# One-time setup of Echo Island + Reachy on a new Windows laptop.
# Installs everything inside this folder (no global Python, PATH or registry
# change). Needs internet and about 8 GB free; takes 20-40 minutes.
# Safe to run again: finished steps are skipped.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Set-Location $root
function Step($text){Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan}
function Check($what){if($LASTEXITCODE -ne 0){throw "$what failed. Fix the message above, then run Setup-New-Laptop again."}}

Step 'Laptop number'
$settingsPath=Join-Path $root 'tools/laptop.json'
New-Item -ItemType Directory -Force -Path (Join-Path $root 'tools') | Out-Null
if($LaptopNumber -eq 0 -and (Test-Path $settingsPath)){$LaptopNumber=(Get-Content -Raw $settingsPath | ConvertFrom-Json).laptop}
while($LaptopNumber -lt 1 -or $LaptopNumber -gt 9){
    Write-Host 'Each study laptop gives its participants their own numbers (laptop 1: P001-P099, laptop 2: P101-P199, ...).'
    $answer=Read-Host 'Which laptop is this? Type 1 for the main laptop, 2 for the second, 3 for the third'
    [int]::TryParse($answer,[ref]$LaptopNumber) | Out-Null
}
@{laptop=$LaptopNumber} | ConvertTo-Json | Set-Content -Encoding utf8 $settingsPath
Write-Host ("Laptop {0}: participant numbers start at P{1:000}." -f $LaptopNumber,(($LaptopNumber-1)*100+1))

Step 'Installer (uv)'
$uv=(Get-Command uv -ErrorAction SilentlyContinue).Source
if(-not $uv){$uv=Join-Path $env:USERPROFILE '.local/bin/uv.exe'}
if(-not (Test-Path $uv)){
    Write-Host 'Installing uv from astral.sh ...'
    powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://astral.sh/uv/install.ps1 | iex'
    if(-not (Test-Path $uv)){throw 'uv did not install. Install it from https://docs.astral.sh/uv/ and run setup again.'}
}
& $uv --version
$env:UV_PYTHON_INSTALL_DIR=Join-Path $root 'tools/python'
$env:UV_CACHE_DIR=Join-Path $root 'tools/uv-cache'

Step 'Python 3.12 and 3.10 (inside tools/python)'
& $uv python install 3.12.10 3.10.22 --no-bin --no-registry; Check 'Python install'

$environments=[ordered]@{
    'controller'='3.12.10'   # game controller (FastAPI)
    'speech'='3.12.10'       # microphone + Whisper/Vosk + Kokoro
    'dialogue'='3.12.10'     # Qwen topic finder + reply voice
    'rasa'='3.10.22'         # Rasa conversation understanding
}
foreach($name in $environments.Keys){
    Step "Python environment: $name"
    $venv=Join-Path $root "services/$name/.venv"
    $python=Join-Path $venv 'Scripts/python.exe'
    $works=$false
    if(Test-Path $python){ & $python -c 'import sys' 2>$null; $works=($LASTEXITCODE -eq 0) }
    if(-not $works){
        if(Test-Path $venv){Remove-Item -Recurse -Force $venv}  # copied from another laptop: rebuild
        & $uv venv --python $environments[$name] --managed-python $venv; Check "Creating $name environment"
    }
    $lock=Join-Path $root "services/$name/requirements-lock.txt"
    $extra=@()
    if($name -eq 'dialogue'){$extra=@('--extra-index-url','https://download.pytorch.org/whl/cpu','--extra-index-url','https://abetlen.github.io/llama-cpp-python/whl/cpu','--index-strategy','unsafe-best-match')}
    & $uv pip install --python $python -r $lock @extra; Check "Installing $name packages"
}

Step 'Godot 4.5.2 game engine'
$godot=Join-Path $root 'tools/godot'
if(-not (Test-Path (Join-Path $godot 'Godot_v4.5.2-stable_win64_console.exe'))){
    New-Item -ItemType Directory -Force -Path $godot | Out-Null
    $zip=Join-Path $godot 'godot.zip'
    Write-Host 'Downloading Godot ...'
    $ProgressPreference='SilentlyContinue'
    Invoke-WebRequest 'https://github.com/godotengine/godot/releases/download/4.5.2-stable/Godot_v4.5.2-stable_win64.exe.zip' -OutFile $zip
    Expand-Archive -Force $zip $godot; Remove-Item $zip
} else {Write-Host 'Already present.'}

Step 'Speech, dialogue and voice models + Reachy dances (several GB)'
$speechPython=Join-Path $root 'services/speech/.venv/Scripts/python.exe'
& $speechPython (Join-Path $root 'dev/setup/download_models.py'); Check 'Model download'
if(-not (Test-Path (Join-Path $root 'tools/narration/pocket-cache/hub/models--kyutai--pocket-tts-without-voice-cloning'))){
    & (Join-Path $root 'services/dialogue/.venv/Scripts/python.exe') (Join-Path $root 'dev/setup/prefetch_reply_voice.py'); Check 'Reply voice download'
} else {Write-Host 'Reply voice already present.'}

Step 'Import game files'
$console=Join-Path $godot 'Godot_v4.5.2-stable_win64_console.exe'
& $console --headless --path $root --import 2>&1 | Out-Null
Write-Host 'Done.'

Step 'Train the Rasa conversation model (a few minutes)'
$rasa=Join-Path $root 'services/rasa'
$rasaPython=Join-Path $rasa '.venv/Scripts/python.exe'
$env:RASA_TELEMETRY_ENABLED='false'; $env:TF_CPP_MIN_LOG_LEVEL='2'
Push-Location $rasa
try{
    & $rasaPython build_conversation_data.py; Check 'Conversation data'
    if(-not (Test-Path 'models/echo_conversation.tar.gz')){
        & $rasaPython run_local.py train --config conversation/config.yml --domain conversation/domain.yml --data conversation --out models --fixed-model-name echo_conversation --quiet; Check 'Rasa training'
    } else {Write-Host 'Already trained.'}
} finally {Pop-Location}

Step 'Quick check'
Push-Location (Join-Path $root 'services/controller')
try{ & .venv/Scripts/python.exe -m unittest discover -s tests 2>&1 | Select-Object -Last 3; Check 'Controller self-test' } finally {Pop-Location}

Step 'Reachy Mini Control app'
$appPython=Join-Path $env:LOCALAPPDATA 'Reachy Mini Control/.venv/Scripts/python.exe'
if(Test-Path $appPython){Write-Host 'Installed.' -ForegroundColor Green}
else{
    Write-Host 'NOT installed yet. Install "Reachy Mini Control" from Pollen Robotics:' -ForegroundColor Yellow
    Write-Host '  https://huggingface.co/docs/reachy_mini  (Getting started > Reachy Mini Lite)'
    Write-Host 'Open it once, connect Reachy with USB-C, and let it finish its own setup.'
}

Write-Host ''
Write-Host 'Setup finished. To play: plug in Reachy, open Reachy Mini Control, then double-click Play-Reachy-Study.cmd' -ForegroundColor Green
