param([ValidateSet('','humour','control')][string]$Condition='',
      [string]$SurveyUrl='https://claude.ai/artifact/8r5EUZ57pMuZpyt5KT63rP',
      [switch]$CheckOnly)  # -CheckOnly: test robot, microphone and speaker without starting a game
# One click study session: Reachy Mini Lite (USB-C) + Reachy Mini Control app,
# hold-B talking, Rasa conversation, private transcript and the survey link.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$daemon='http://127.0.0.1:8000'
function Fail($text){Write-Host ''; Write-Host $text -ForegroundColor Red; exit 1}
function Get-DaemonState{try{(Invoke-RestMethod "$daemon/api/daemon/status" -TimeoutSec 2)}catch{$null}}

# 1. Setup present?
foreach($path in 'services/controller/.venv','services/speech/.venv','services/dialogue/.venv','services/rasa/.venv','tools/godot','services/rasa/models/echo_conversation.tar.gz'){
    if(-not (Test-Path (Join-Path $root $path))){Fail 'This laptop is not set up yet. Double-click Setup-New-Laptop.cmd first.'}
}
$appPython=Join-Path $env:LOCALAPPDATA 'Reachy Mini Control/.venv/Scripts/python.exe'
if(-not (Test-Path $appPython)){Fail 'Install and open the Reachy Mini Control app first (see START HERE - NEW LAPTOP.txt).'}

# 2. Participant number range of this laptop.
$settings=Join-Path $root 'tools/laptop.json'
$laptop=if(Test-Path $settings){(Get-Content -Raw $settings | ConvertFrom-Json).laptop}else{1}
$env:ECHO_FIRST_PARTICIPANT=[string](($laptop-1)*100+1)
Remove-Item Env:ECHO_ROBOT_DEBUG -ErrorAction SilentlyContinue

# 3. Reachy Mini Control app and robot.
Write-Host 'Checking Reachy ...' -ForegroundColor Cyan
if(-not (Get-DaemonState)){
    $app=Join-Path $env:ProgramFiles 'Reachy Mini Control/reachy-mini-control.exe'
    if(Test-Path $app){Write-Host 'Opening Reachy Mini Control ...'; Start-Process $app}
    Write-Host 'In the Reachy Mini Control window, connect to the robot (USB). Waiting ...' -ForegroundColor Yellow
}
$clock=[Diagnostics.Stopwatch]::StartNew(); $restarted=$false
while($true){
    $status=Get-DaemonState
    if($status -and $status.state -eq 'running' -and -not $status.simulation_enabled -and -not $status.mockup_sim_enabled){break}
    if($clock.Elapsed.TotalSeconds -gt 45 -and $status -and -not $restarted){
        Write-Host 'Restarting the robot connection ...'
        try{Invoke-RestMethod -Method Post "$daemon/api/daemon/restart" -TimeoutSec 30 | Out-Null}catch{}
        $restarted=$true
    }
    if($clock.Elapsed.TotalSeconds -gt 150){Fail 'Reachy is not connected. Check: robot power adapter plugged in, USB-C cable in the laptop, Reachy Mini Control shows the robot. Then try again.'}
    Start-Sleep -Seconds 2
}
try{
    Invoke-RestMethod -Method Post "$daemon/api/motors/set_mode/enabled" -TimeoutSec 10 | Out-Null
    Invoke-RestMethod -Method Post "$daemon/api/move/play/wake_up" -TimeoutSec 10 | Out-Null
}catch{Write-Host 'Could not wake the motors; continuing.' -ForegroundColor Yellow}
Write-Host 'Reachy connected.' -ForegroundColor Green

# 4. Reachy's microphone and speaker (device numbers differ per laptop).
$audio=& (Join-Path $root 'services/speech/.venv/Scripts/python.exe') (Join-Path $root 'dev/setup/find_reachy_audio.py') | ConvertFrom-Json
if($audio.input -lt 0){Fail "Windows does not see Reachy's microphone. Unplug and replug the USB-C cable, wait 10 seconds, try again."}
$speaker=if($audio.speaker){$audio.speaker}else{'Echo Cancelling Speakerphone (Reachy Mini Audio)'}
Write-Host "Microphone $($audio.input), speaker: $speaker"
if($CheckOnly){Write-Host 'Check passed: this laptop is ready to play.' -ForegroundColor Green; exit 0}

# 5. Jokes on or off (shows how many of each this laptop has run, to balance).
if(-not $Condition){
    $log=Join-Path $root 'transcripts/conversations.md'
    $on=0;$off=0
    if(Test-Path $log){$text=Get-Content -Raw $log; $on=([regex]::Matches($text,'- Jokes: on')).Count; $off=([regex]::Matches($text,'- Jokes: off')).Count}
    Write-Host ''
    Write-Host "Sessions on this laptop so far: jokes ON $on, jokes OFF $off"
    do{$choice=Read-Host 'Type 1 for jokes ON or 2 for jokes OFF'}while($choice -notin '1','2')
    $Condition=if($choice -eq '1'){'humour'}else{'control'}
}

# 6. Rasa conversation server, then the game.
$ownedRouter=$null
function Test-Router{try{(Invoke-RestMethod 'http://127.0.0.1:5006/status' -TimeoutSec 2).model_file -eq 'echo_conversation.tar.gz'}catch{$false}}
try{
    if(-not (Test-Router)){
        $runtime=Join-Path $root 'tools/runtime'; New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        Write-Host 'Starting conversation understanding (up to 2 minutes) ...'
        $ownedRouter=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $root 'Start-Rasa-Conversation.ps1')+'"')) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'conversation-router.log') -RedirectStandardError (Join-Path $runtime 'conversation-router-errors.log')
        $wait=[Diagnostics.Stopwatch]::StartNew()
        while($wait.Elapsed.TotalSeconds -lt 180 -and -not (Test-Router)){
            if($ownedRouter.HasExited){Fail 'Conversation server stopped. See tools/runtime/conversation-router-errors.log.'}
            Start-Sleep -Milliseconds 500
        }
        if(-not (Test-Router)){Fail 'Conversation server did not start in time. Try again.'}
    }
    Write-Host ''
    Write-Host 'Starting the game. Write down the Participant ID printed below.' -ForegroundColor Green
    & (Join-Path $root 'Play-Controller.ps1') -ReachyLite -RobotPython $appPython -SpeakerName $speaker -Expressive -Conversation -PushToTalk -Transcript -SurveyUrl $SurveyUrl -InputDevice $audio.input -Condition $Condition
} finally {
    if($null -ne $ownedRouter -and -not $ownedRouter.HasExited){& taskkill.exe /PID $ownedRouter.Id /T /F | Out-Null}
}
