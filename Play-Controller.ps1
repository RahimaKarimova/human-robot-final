param([switch]$Test, [switch]$Rasa, [switch]$PrestartStop, [switch]$CompanionPreview, [switch]$RenderTest, [switch]$BridgeSimulator, [switch]$ReachyLite, [string]$RobotPython, [string]$SpeakerName, [switch]$Gestures, [switch]$Expressive, [switch]$FullCompanionTest, [switch]$Microphone, [switch]$Conversation, [switch]$PushToTalk, [switch]$Transcript, [string]$SurveyUrl, [ValidateRange(1024,65535)][int]$ConversationRouterPort=5006, [int]$InputDevice = -1, [switch]$Wireless, [switch]$ReachySimulator, [switch]$ControlSimulator, [ValidateRange(1024,65535)][int]$SimulatorPort=8000, [ValidateSet('control','humour')][string]$Condition = 'control', [ValidateRange(1024,65535)][int]$Port = 8765)
$ErrorActionPreference = 'Stop'
if ($Conversation) { $Microphone=$true; $CompanionPreview=$true }
if ($ControlSimulator -and ($ReachySimulator -or $ReachyLite -or $Wireless -or $BridgeSimulator)) { throw 'Choose ControlSimulator by itself.' }
if ($BridgeSimulator -and $ReachyLite) { throw 'Choose one output adapter.' }
if ($ReachySimulator -and ($BridgeSimulator -or $ReachyLite -or $Wireless)) { throw 'Choose official Reachy simulator mode by itself; it is distinct from the lightweight test fake.' }
if ($ReachySimulator -and $Test -and ($Microphone -or $SimulatorPort -eq 8000)) { throw 'Official simulator tests require an isolated -SimulatorPort; physical routes and the play-session daemon are not test targets.' }
if ($ReachySimulator -or $ControlSimulator) { $RobotPython = Join-Path $PSScriptRoot 'services/robot/.venv/Scripts/python.exe' }
if ($ControlSimulator) { $RobotPython = Join-Path $env:LOCALAPPDATA 'Reachy Mini Control/.venv/Scripts/python.exe'; if (-not (Test-Path -LiteralPath $RobotPython)) { throw 'The installed Reachy Mini Control Python environment is missing.' } }
if ($Wireless -and ($BridgeSimulator -or $ReachyLite -or $Test)) { throw 'Wireless output requires a separate on-robot worker. Choose one route; tests never operate hardware.' }
if ($ReachyLite -and ($Test -or -not $RobotPython -or -not $SpeakerName)) { throw 'Physical Lite output requires -RobotPython and -SpeakerName; automated tests never select physical hardware.' }
if ($BridgeSimulator -or $ReachyLite -or $Wireless -or $ReachySimulator -or $ControlSimulator) { $CompanionPreview = $true }
if ($Microphone) { $CompanionPreview = $true }
if ($FullCompanionTest -and (-not $Test -or -not $CompanionPreview)) { throw '-FullCompanionTest requires -Test and -CompanionPreview or -BridgeSimulator.' }
if ($RenderTest -and $BridgeSimulator) { throw 'Bridge checks run headless and silent.' }
if ($Rasa -and -not $Test) { throw 'Use -Test -Rasa for the synthetic check. For interactive requests, run Start-Rasa.ps1 and Control-Companion.ps1 in separate terminals.' }
if ($RenderTest -and (-not $Test -or -not $CompanionPreview)) { throw '-RenderTest requires -Test -CompanionPreview.' }
if ($CompanionPreview -and ($Rasa -or $PrestartStop)) { throw 'Preview has its own test scene; use -Test -CompanionPreview separately from -Rasa or -PrestartStop.' }
$projectRoot = $PSScriptRoot
$serviceRoot = Join-Path $projectRoot 'services/controller'
$pythonExe = Join-Path $serviceRoot '.venv/Scripts/python.exe'
$engineExe = Join-Path $projectRoot 'tools/godot/Godot_v4.5.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) { throw 'Set up services/controller/.venv first. See services/controller/README.md.' }
if (-not (Test-Path -LiteralPath $engineExe)) { throw 'The workspace Godot executable is missing. See Launch.ps1 for installed-engine options.' }
$runtimeRoot = Join-Path $projectRoot 'tools/runtime'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$runId = [guid]::NewGuid().ToString('N')
$configPath = Join-Path $runtimeRoot ($runId + '.session.json')
$robotConfigPath = Join-Path $runtimeRoot ($runId + '.robot.json')
$robotProcess = $null
$speechProcess = $null
$speechConfigPath = Join-Path $runtimeRoot ($runId + '.speech.json')
$speechPython = Join-Path $projectRoot 'services/speech/.venv/Scripts/python.exe'
$speechModel = Join-Path $projectRoot 'tools/speech/vosk-model-small-en-us-0.15'
if ($Microphone) {
    if (-not (Test-Path -LiteralPath $speechPython) -or -not (Test-Path -LiteralPath (Join-Path $speechModel 'am/final.mdl'))) { throw 'Install the optional offline speech environment/model. See docs/VOICE_CONTROLS.md.' }
    if ($Conversation) {
        foreach ($requiredPath in @('services/dialogue/.venv/Scripts/python.exe','tools/dialogue/qwen3-0.6b/Qwen3-0.6B-Q8_0.gguf')) {
            if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $requiredPath))) { throw 'The optional offline CPU conversation environment is missing. See services/dialogue/README.md.' }
        }
        foreach ($modelName in @('whisper-base.en','whisper-small.en')) {
            if (-not (Test-Path -LiteralPath (Join-Path $projectRoot ('tools/speech/'+$modelName+'/model.bin')))) { throw 'Install both local Whisper conversation models. See docs/CONVERSATION.md.' }
        }
    }
    $speechRouter = if ($Conversation) { ('http://127.0.0.1:'+ $ConversationRouterPort + '/status') } else { 'http://127.0.0.1:5005/status' }
    try { Invoke-RestMethod -Uri $speechRouter -TimeoutSec 2 | Out-Null } catch { throw 'Start Start-Rasa.ps1 in a separate terminal first; microphone controls use its local NLU service.' }
}
$controllerProcess = $null
$priorAppData = $env:APPDATA
$priorLocalAppData = $env:LOCALAPPDATA
$serverUrl = 'http://127.0.0.1:' + $Port
try {
    $env:APPDATA = Join-Path $runtimeRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $runtimeRoot 'Local'
    $health = $null
    try { $health = Invoke-RestMethod -Uri ($serverUrl + '/health') -TimeoutSec 1 } catch { }
    if ($null -eq $health) {
        $controllerProcess = Start-Process -FilePath $pythonExe -ArgumentList @('-m','echo_controller','serve','--port',$Port) -WorkingDirectory $serviceRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeRoot ($runId + '-controller.log')) -RedirectStandardError (Join-Path $runtimeRoot ($runId + '-controller-errors.log'))
        for ($attempt = 0; $attempt -lt 30 -and $null -eq $health; $attempt++) {
            Start-Sleep -Milliseconds 200
            try { $health = Invoke-RestMethod -Uri ($serverUrl + '/health') -TimeoutSec 1 } catch { }
            if ($controllerProcess.HasExited) { throw 'The local controller failed to start. Check tools/runtime/*-controller-errors.log.' }
        }
    }
    if ($null -eq $health -or $health.mode -ne 'mock' -or $health.retains_answers -ne $false) { throw 'Expected the local development mock controller on the selected port.' }
    Push-Location $serviceRoot
    try {
        $sessionArgs = @('-m','echo_controller','new-session','--port',$Port,'--condition',$Condition,'--output',$configPath)
        if ($CompanionPreview) { $sessionArgs += '--preview' }
        if ($Conversation) { $sessionArgs += '--conversation' }
        if ($Conversation -and $PushToTalk) { $sessionArgs += '--push-to-talk' }
        if ($Conversation -and $Transcript) { $sessionArgs += '--transcript' }
        if ($SurveyUrl) { $sessionArgs += @('--survey-url',$SurveyUrl) }
        if ($Microphone) { $sessionArgs += @('--speech-config',$speechConfigPath) }
        if ($BridgeSimulator -or $ReachyLite -or $Wireless -or $ReachySimulator -or $ControlSimulator) {
            $outputRoute = if ($BridgeSimulator) { 'bridge_simulator' } elseif ($Wireless) { 'reachy_wireless' } elseif ($ReachySimulator) { 'reachy_mujoco' } elseif ($ControlSimulator) { 'reachy_control_simulator' } else { 'reachy_lite' }
            $sessionArgs += @('--robot-output',$outputRoute,'--robot-config',$robotConfigPath)
        }
        $sessionOutput = @(& $pythonExe @sessionArgs)
        if ($LASTEXITCODE -ne 0) { throw 'Could not create controller session.' }
        $sessionOutput | ForEach-Object { Write-Host $_ }
        $participantId = ($sessionOutput | Select-String -Pattern 'Participant ID: (P\d+)' | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value })
    } finally { Pop-Location }
    if ($Wireless) { Write-Host "Start the on-robot worker over an SSH reverse tunnel before clicking Begin. Its capability file is $robotConfigPath . See docs/WIRELESS.md. No network connection was started automatically." }
    if ($Microphone) {
        $speechArgs = @('-m','echo_controller.speech_worker','--config',('"' + $speechConfigPath + '"'),'--model',('"' + $speechModel + '"'))
        if ($InputDevice -ge 0) { $speechArgs += @('--device',$InputDevice) }
        if ($Conversation) { $speechArgs += @('--rasa-url',('http://127.0.0.1:'+$ConversationRouterPort)) }
        if ($Test) { $speechArgs += @('--test-fixture',('"' + (Join-Path $projectRoot 'tools/speech/fixtures/pause.wav') + '"')) }
        if ($Test -and $Conversation -and -not $FullCompanionTest) { $speechArgs += '--conversation-test-branches' }
        $speechProcess = Start-Process -FilePath $speechPython -ArgumentList $speechArgs -WorkingDirectory $serviceRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeRoot ($runId + '-speech.log')) -RedirectStandardError (Join-Path $runtimeRoot ($runId + '-speech-errors.log'))
        Start-Sleep -Milliseconds 400
        if ($speechProcess.HasExited) { throw 'Speech controls could not start. Check tools/runtime/*-speech-errors.log.' }
    }
    if ($BridgeSimulator -or $ReachyLite -or $ReachySimulator -or $ControlSimulator) {
        $workerPython = if ($BridgeSimulator) { $pythonExe } else { (Resolve-Path -LiteralPath $RobotPython).Path }
        $workerArgs = @('-m','echo_controller.robot_worker','--config',('"' + $robotConfigPath + '"'))
        if ($ReachyLite) { $workerArgs += @('--speaker-name',('"' + $SpeakerName + '"')) }
        if ($Gestures -and $ReachyLite) { $workerArgs += '--gestures' }
        if ($Expressive -and $ReachyLite) { $workerArgs += '--expressive' }
        if ($ReachySimulator -or $ControlSimulator) {
            $workerArgs += @('--simulator-port',$SimulatorPort)
            if ($Test) { $workerArgs += '--mute-simulator-audio' }
        }
        if ($Test) { $workerArgs += @('--simulator-speed','4') }
        $robotProcess = Start-Process -FilePath $workerPython -ArgumentList $workerArgs -WorkingDirectory $serviceRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeRoot ($runId + '-robot.log')) -RedirectStandardError (Join-Path $runtimeRoot ($runId + '-robot-errors.log'))
        Start-Sleep -Milliseconds 400
        if ($robotProcess.HasExited) { throw 'The output adapter could not start. Read tools/runtime/*-robot-errors.log. No fallback was selected.' }
        if ($ReachySimulator -or $ControlSimulator -or $ReachyLite) {
            Write-Host "Waiting for Reachy to get ready (loading voices, about 30 seconds)..."
            $readyConfig=Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
            $bridgeReady=$false
            $adapterStartup=[Diagnostics.Stopwatch]::StartNew()
            while ($adapterStartup.Elapsed.TotalSeconds -lt 180 -and -not $bridgeReady) {
                if ($robotProcess.HasExited) { throw 'Official SDK adapter exited before becoming ready. Check the robot error log.' }
                try { $readyState=Invoke-RestMethod -Uri ($serverUrl+'/companion/context?session_id='+$readyConfig.session_id) -Headers @{'X-Echo-Session-Token'=$readyConfig.token} -TimeoutSec 1; $bridgeReady=$readyState.bridge_ready -eq $true } catch { }
                if (-not $bridgeReady) { Start-Sleep -Milliseconds 250 }
            }
            if (-not $bridgeReady) { throw 'Official SDK adapter did not become ready. The game was not started with a silent fallback.' }
        }
    }
    $engineArgs = @('--path', $projectRoot)
    if ($Test) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/controller_runner.tscn') }
    if ($Test -and $CompanionPreview) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/companion_preview_runner.tscn') }
    if ($Test -and $BridgeSimulator) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/robot_bridge_runner.tscn') }
    if ($Test -and ($ReachySimulator -or $ControlSimulator)) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/robot_bridge_runner.tscn') }
    if ($FullCompanionTest) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/full_companion_runner.tscn') }
    if ($Test -and $Microphone -and -not $FullCompanionTest) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/speech_runner.tscn') }
    if ($Test -and $Conversation -and -not $FullCompanionTest) { $engineArgs = @('--headless','--path',$projectRoot,'res://tests/conversation_runner.tscn') }
    if ($RenderTest) { $engineArgs = @($engineArgs | Where-Object { $_ -ne '--headless' }) }
    if ($Test) { $engineArgs += @('--max-fps','60') }
    $engineArgs += @('--','--controller-config',$configPath)
    if ($Test -and $Condition -eq 'control') { $engineArgs += '--test-jokes-off' }
    if ($Rasa) { $engineArgs += '--test-rasa' }
    if ($RenderTest) { $engineArgs += '--capture-preview' }
    if ($PrestartStop) {
        if (-not $Test) { throw '-PrestartStop requires -Test.' }
        $sessionConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
        Invoke-RestMethod -Method Post -Uri ($serverUrl + '/session/stop?session_id=' + $sessionConfig.session_id) -Headers @{'X-Echo-Session-Token'=$sessionConfig.token} | Out-Null
        $engineArgs += '--test-prestart-stop'
    }
    $ErrorActionPreference = 'Continue'
    if ($RenderTest) {
        $renderLog = Join-Path $runtimeRoot ($runId + '-render.log')
        $renderErrors = Join-Path $runtimeRoot ($runId + '-render-errors.log')
        $quotedEngineArgs = @($engineArgs | ForEach-Object { '"' + $_ + '"' })
        $renderProcess = Start-Process -FilePath $engineExe -ArgumentList $quotedEngineArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $renderLog -RedirectStandardError $renderErrors
        $engineExit = $renderProcess.ExitCode
        $output = @(Get-Content -LiteralPath $renderLog) + @(Get-Content -LiteralPath $renderErrors)
        $output | ForEach-Object { Write-Host $_ }
    } elseif ($Test) {
        $output = & $engineExe @engineArgs 2>&1
        $engineExit = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
    } else {
        # Explicitly show the GUI even when this launcher was started by a hidden
        # editor/helper process. Tests keep their separate silent/headless path.
        $guiEngine = Join-Path $projectRoot 'tools/godot/Godot_v4.5.2-stable_win64.exe'
        if (-not (Test-Path -LiteralPath $guiEngine)) { $guiEngine = $engineExe }
        $visibleArgs = @('--windowed','--screen','0','--position','50,50','--resolution','1280x720') + $engineArgs
        $quotedVisibleArgs = @($visibleArgs | ForEach-Object { '"' + $_ + '"' })
        $gameProcess = Start-Process -FilePath $guiEngine -ArgumentList $quotedVisibleArgs -WorkingDirectory $projectRoot -WindowStyle Normal -Wait -PassThru
        $engineExit = $gameProcess.ExitCode
    }
    $ErrorActionPreference = 'Stop'
    if ($engineExit -ne 0 -or ($Test -and ($output -join "`n") -match 'SCRIPT ERROR|FAIL:')) { throw 'Game/controller integration checks failed.' }
} finally {
    if (Test-Path -LiteralPath $configPath) {
        $sessionConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
        try { Invoke-RestMethod -Method Post -Uri ($serverUrl + '/session/stop?session_id=' + $sessionConfig.session_id) -Headers @{'X-Echo-Session-Token'=$sessionConfig.token} -TimeoutSec 1 | Out-Null } catch { }
        Remove-Item -LiteralPath $configPath -Force
    }
    if ($null -ne $robotProcess) {
        for ($waitAttempt = 0; $waitAttempt -lt 10 -and -not $robotProcess.HasExited; $waitAttempt++) { Start-Sleep -Milliseconds 100 }
        if (-not $robotProcess.HasExited) { Stop-Process -Id $robotProcess.Id -ErrorAction SilentlyContinue }
    }
    if ($null -ne $speechProcess) {
        for ($waitAttempt = 0; $waitAttempt -lt 10 -and -not $speechProcess.HasExited; $waitAttempt++) { Start-Sleep -Milliseconds 100 }
        if (-not $speechProcess.HasExited) { Stop-Process -Id $speechProcess.Id -ErrorAction SilentlyContinue }
    }
    if ($null -ne $controllerProcess -and -not $controllerProcess.HasExited) { Stop-Process -Id $controllerProcess.Id -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $robotConfigPath) { Remove-Item -LiteralPath $robotConfigPath -Force }
    if (Test-Path -LiteralPath $speechConfigPath) { Remove-Item -LiteralPath $speechConfigPath -Force }
    $env:APPDATA = $priorAppData
    $env:LOCALAPPDATA = $priorLocalAppData
}
