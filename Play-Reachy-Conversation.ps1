param([ValidateSet('control','humour')][string]$Condition='humour')
$ErrorActionPreference='Stop'
$ownedRouter=$null
function Test-ConversationRouter {
    try {
        $status=Invoke-RestMethod -Uri 'http://127.0.0.1:5006/status' -TimeoutSec 2
        return $status.model_file -eq 'echo_conversation.tar.gz'
    } catch {return $false}
}
try {
    if (-not (Test-ConversationRouter)) {
        $runtime=Join-Path $PSScriptRoot 'tools/runtime'
        New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        $ownedRouter=Start-Process -FilePath powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Start-Rasa-Conversation.ps1')+'"')) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'conversation-router.log') -RedirectStandardError (Join-Path $runtime 'conversation-router-errors.log')
        Write-Host 'Preparing planned conversations. The microphone stays off until Reachy finishes a question.'
        $startup=[Diagnostics.Stopwatch]::StartNew()
        while ($startup.Elapsed.TotalSeconds -lt 180 -and -not (Test-ConversationRouter)) {
            if ($ownedRouter.HasExited) {throw 'The conversation router exited. Read tools/runtime/conversation-router-errors.log.'}
            Start-Sleep -Milliseconds 500
        }
        if (-not (Test-ConversationRouter)) {throw 'The conversation router did not become ready.'}
    }
    # A reused router can still hold an older archive with the same filename.
    # Reload the current model for this explicitly requested new play session.
    $currentModel=Join-Path $PSScriptRoot 'services/rasa/models/echo_conversation.tar.gz'
    $reloadBody=@{model_file=$currentModel} | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri 'http://127.0.0.1:5006/model' -Method Put -ContentType 'application/json' -Body $reloadBody -TimeoutSec 90 | Out-Null
    & (Join-Path $PSScriptRoot 'Play-Reachy-Control.ps1') -Conversation -Condition $Condition
} finally {
    if ($null -ne $ownedRouter -and -not $ownedRouter.HasExited) { & taskkill.exe /PID $ownedRouter.Id /T /F | Out-Null }
}
