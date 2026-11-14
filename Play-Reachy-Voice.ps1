param([ValidateSet('control','humour')][string]$Condition='humour')
$ErrorActionPreference='Stop'
$ownedRasa=$null
function Test-LocalSpeechRouter {
    try {
        $status=Invoke-RestMethod -Uri 'http://127.0.0.1:5005/status' -TimeoutSec 2
        return -not [string]::IsNullOrEmpty($status.model_file)
    } catch { return $false }
}
try {
    if (-not (Test-LocalSpeechRouter)) {
        $runtime=Join-Path $PSScriptRoot 'tools/runtime'
        New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        $ownedRasa=Start-Process -FilePath powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Start-Rasa.ps1')+'"')) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'voice-router.log') -RedirectStandardError (Join-Path $runtime 'voice-router-errors.log')
        Write-Host 'Starting local voice commands. The microphone remains closed until you hold V or B in the game.'
        $startup=[Diagnostics.Stopwatch]::StartNew()
        $ready=$false
        while ($startup.Elapsed.TotalSeconds -lt 150 -and -not $ready) {
            if ($ownedRasa.HasExited) { throw 'The local voice router exited. Read tools/runtime/voice-router-errors.log.' }
            $ready=Test-LocalSpeechRouter
            if (-not $ready) { Start-Sleep -Milliseconds 500 }
        }
        if (-not $ready) { throw 'The local voice router did not become ready. Read tools/runtime/voice-router-errors.log.' }
    }
    & (Join-Path $PSScriptRoot 'Play-Reachy-Control.ps1') -Microphone -Condition $Condition
} finally {
    if ($null -ne $ownedRasa -and -not $ownedRasa.HasExited) { & taskkill.exe /PID $ownedRasa.Id /T /F | Out-Null }
}
