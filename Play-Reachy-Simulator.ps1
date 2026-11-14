param([ValidateSet('control','humour')][string]$Condition='humour', [switch]$Microphone)
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$simPython=Join-Path $projectRoot 'services/robot/.venv/Scripts/pythonw.exe'
if (-not (Test-Path -LiteralPath $simPython)) { throw 'Install services/robot/requirements-simulation.txt in services/robot/.venv first.' }
$runtimeRoot=Join-Path $projectRoot 'tools/runtime'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$daemonProcess=$null
$oldAppData=$env:APPDATA
$oldLocalAppData=$env:LOCALAPPDATA
$oldHfHome=$env:HF_HOME
$oldCache=$env:XDG_CACHE_HOME
$oldConfig=$env:XDG_CONFIG_HOME
try {
    $env:APPDATA=Join-Path $runtimeRoot 'Roaming'
    $env:LOCALAPPDATA=Join-Path $runtimeRoot 'Local'
    $env:HF_HOME=Join-Path $projectRoot 'tools/robot/huggingface'
    $env:XDG_CACHE_HOME=Join-Path $projectRoot 'tools/robot/cache'
    $env:XDG_CONFIG_HOME=Join-Path $projectRoot 'tools/robot/config'
    $status=$null
    try { $status=Invoke-RestMethod -Uri 'http://127.0.0.1:8000/api/daemon/status' -TimeoutSec 1 } catch { }
    if ($null -eq $status) {
        $daemonArgs=@('-m','reachy_mini.daemon.app.main','--sim','--scene','minimal','--no-media','--no-preload-datasets','--fastapi-host','127.0.0.1','--fastapi-port','8000','--log-level','WARNING')
        $daemonProcess=Start-Process -FilePath $simPython -ArgumentList $daemonArgs -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $runtimeRoot 'reachy-mujoco.log') -RedirectStandardError (Join-Path $runtimeRoot 'reachy-mujoco-errors.log')
        for ($attempt=0; $attempt -lt 40 -and ($null -eq $status -or $status.state -ne 'running'); $attempt++) {
            Start-Sleep -Milliseconds 250
            try { $status=Invoke-RestMethod -Uri 'http://127.0.0.1:8000/api/daemon/status' -TimeoutSec 1 } catch { }
            if ($daemonProcess.HasExited) { throw 'The official simulator exited. Read tools/runtime/reachy-mujoco-errors.log.' }
        }
    }
    if ($null -eq $status -or $status.state -ne 'running' -or $status.simulation_enabled -ne $true -or $status.mockup_sim_enabled -eq $true) { throw 'A running official MuJoCo daemon is required. Physical and mockup daemons are refused.' }
    Write-Host 'Official Reachy Mini MuJoCo is ready. Opening Echo Island; click Begin to see the simulated robot react.'
    $playArgs=@{ReachySimulator=$true;Condition=$Condition}
    if ($Microphone) { $playArgs.Microphone=$true }
    & (Join-Path $projectRoot 'Play-Controller.ps1') @playArgs
} finally {
    if ($null -ne $daemonProcess -and -not $daemonProcess.HasExited) {
        & taskkill.exe /PID $daemonProcess.Id /T /F | Out-Null
    }
    $env:APPDATA=$oldAppData
    $env:LOCALAPPDATA=$oldLocalAppData
    $env:HF_HOME=$oldHfHome
    $env:XDG_CACHE_HOME=$oldCache
    $env:XDG_CONFIG_HOME=$oldConfig
}
