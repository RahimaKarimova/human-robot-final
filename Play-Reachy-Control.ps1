param([ValidateSet('control','humour')][string]$Condition='humour', [switch]$Microphone, [switch]$Conversation)
$ErrorActionPreference='Stop'
$status=Invoke-RestMethod -Uri 'http://127.0.0.1:8000/api/daemon/status' -TimeoutSec 3
if ($status.state -ne 'running') { throw 'Start the local simulator in Reachy Mini Control first.' }
$playArgs=@{Condition=$Condition;Port=8768}
if ($status.mockup_sim_enabled -eq $true) { $playArgs.ControlSimulator=$true }
elseif ($status.simulation_enabled -eq $true) { $playArgs.ReachySimulator=$true }
else { throw 'Choose simulation in Reachy Mini Control. This launcher does not select physical hardware.' }
if ($Microphone) { $playArgs.Microphone=$true }
if ($Conversation) { $playArgs.Conversation=$true; $playArgs.Port=8769 }
$viewer=$null
try {
    if ($status.mockup_sim_enabled -eq $true) {
        $viewerPython=Join-Path $PSScriptRoot 'services/robot/.venv/Scripts/pythonw.exe'
        $viewerScript=Join-Path $PSScriptRoot 'dev/view_control_robot.py'
        $runtime=Join-Path $PSScriptRoot 'tools/runtime'
        New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        $viewer=Start-Process -FilePath $viewerPython -ArgumentList @('"'+$viewerScript+'"') -WorkingDirectory $PSScriptRoot -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $runtime 'control-3d-view.log') -RedirectStandardError (Join-Path $runtime 'control-3d-view-errors.log')
    }
    & (Join-Path $PSScriptRoot 'Play-Controller.ps1') @playArgs
} finally {
    if ($null -ne $viewer -and -not $viewer.HasExited) { & taskkill.exe /PID $viewer.Id /T /F | Out-Null }
}
