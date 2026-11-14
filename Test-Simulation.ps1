param([switch]$SkipRenderedCheck)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$controllerPython = Join-Path $projectRoot 'services/controller/.venv/Scripts/python.exe'
$speechPython = Join-Path $projectRoot 'services/speech/.venv/Scripts/python.exe'
$previousRasaCheck = $env:ECHO_TEST_RASA
try { Invoke-RestMethod -Uri 'http://127.0.0.1:5005/status' -TimeoutSec 2 | Out-Null } catch { throw 'Start Start-Rasa.ps1 in a separate terminal first, then rerun this audit. No microphone or robot is started by this check.' }
$auditId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$logRoot = Join-Path $projectRoot ('artifacts/simulation-audit/' + $auditId)
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$results = New-Object System.Collections.Generic.List[object]
$auditPassed = $false
$baselineCaps = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools/runtime') -File | Where-Object { $_.Name -match '\.(session|robot|speech)\.json$' } | ForEach-Object { $_.FullName })
function Run-Check([string]$Name, [string]$Program, [string[]]$Arguments, [string]$Directory, [string]$SuccessPattern) {
    Write-Host ('Checking: ' + $Name)
    $logFile = Join-Path $logRoot (($results.Count + 1).ToString('00') + '-' + ($Name -replace '[^a-zA-Z0-9]+','-') + '.log')
    Push-Location $Directory
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Program @Arguments 2>&1
        $checkExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
    } finally { Pop-Location }
    $text = $output -join "`n"
    $text | Set-Content -LiteralPath $logFile -Encoding UTF8
    $passed = $checkExit -eq 0 -and $text -notmatch 'SCRIPT ERROR|FAIL:|FAILED\s*\(' -and $text -match $SuccessPattern
    $results.Add([pscustomobject]@{Name=$Name;Passed=$passed;Log=$logFile})
    if (-not $passed) { throw ('Check failed: ' + $Name + '. Read ' + $logFile) }
}
try {
    $env:ECHO_TEST_RASA = '1'
    Run-Check 'Controller and live Rasa unit tests' $controllerPython @('-m','unittest','discover','-s','tests','-v') (Join-Path $projectRoot 'services/controller') '(?m)^OK\s*$'
    Run-Check 'Offline speech model with synthetic fixtures' $speechPython @('-m','unittest','discover','-s','services/speech/tests','-v') $projectRoot '(?m)^OK\s*$'
    Run-Check 'Offline complete game' 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Launch.ps1','-Test') $projectRoot 'ECHO ISLAND: \d+ assertions, 0 failures'
    foreach ($variant in @('control','humour')) {
        Run-Check ('Full simulator campaign ' + $variant) 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-BridgeSimulator','-FullCompanionTest','-Condition',$variant) $projectRoot 'ECHO FULL COMPANION: \d+ assertions, 0 failures'
        Run-Check ('Real Rasa control routing ' + $variant) 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-Rasa','-Condition',$variant) $projectRoot 'ECHO CONTROLLER: \d+ assertions, 0 failures'
    }
    Run-Check 'Bridge disconnect and narrator recovery' 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-BridgeSimulator') $projectRoot 'ECHO ROBOT BRIDGE: \d+ assertions, 0 failures'
    Run-Check 'Full laptop playback campaign' 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-CompanionPreview','-FullCompanionTest') $projectRoot 'ECHO FULL COMPANION: \d+ assertions, 0 failures'
    Run-Check 'Stop before Begin' 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-PrestartStop') $projectRoot 'ECHO CONTROLLER: \d+ assertions, 0 failures'
    Run-Check 'Speech controls replies and cancellation' 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-Microphone') $projectRoot 'ECHO SPEECH CONTROLS: \d+ assertions, 0 failures'
    if (-not $SkipRenderedCheck) {
        Run-Check 'Rendered voice controls and reply panel' 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File','Play-Controller.ps1','-Test','-Microphone','-RenderTest') $projectRoot 'ECHO SPEECH CONTROLS: \d+ assertions, 0 failures'
    }
    Run-Check 'Wireless package rebuild' $controllerPython @('dev/build_wireless_bundle.py') $projectRoot 'EchoIsland-Wireless-Agent.zip'
    Run-Check 'Wireless package integrity' $controllerPython @('dev/check_wireless_bundle.py') $projectRoot 'WIRELESS PACKAGE: PASS'
    $remainingCaps = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools/runtime') -File | Where-Object { $_.Name -match '\.(session|robot|speech)\.json$' -and $_.FullName -notin $baselineCaps })
    if ($remainingCaps.Count -gt 0) { throw 'A temporary session capability was not cleaned up. Inspect tools/runtime before sharing this workspace.' }
    $auditPassed = $true
} finally {
    $env:ECHO_TEST_RASA = $previousRasaCheck
    $report = @('# Simulation audit', '', ('UTC run: ' + $auditId), ('Overall: ' + $(if ($auditPassed) {'PASS'} else {'FAILED OR INCOMPLETE'})), '', 'This audit uses silent simulation, bundled audio playback callbacks and synthetic speech fixtures. It does not open a live microphone or operate a robot.', '', '| Check | Result | Log |', '|---|---|---|')
    foreach ($result in $results) {
        $relativeLog = $result.Log.Substring($projectRoot.Length + 1).Replace('\','/')
        $report += '| ' + $result.Name + ' | ' + $(if ($result.Passed) {'PASS'} else {'FAIL'}) + ' | [' + [IO.Path]::GetFileName($result.Log) + '](' + $relativeLog.Replace('artifacts/','') + ') |'
    }
    $report += @('', 'Physical robot audio/motion, native SDK/GStreamer/SSH, actual microphone devices and human speech accuracy remain unverified. These software checks are preparation for bench testing, not hardware acceptance.')
    $report | Set-Content -LiteralPath (Join-Path $projectRoot 'artifacts/SIMULATION_AUDIT.md') -Encoding UTF8
}
Write-Host ('SIMULATION AUDIT: ' + $results.Count + ' checks passed. See artifacts/SIMULATION_AUDIT.md.')
