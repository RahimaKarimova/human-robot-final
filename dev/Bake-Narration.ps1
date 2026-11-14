# Optional authoring tool only. The game consumes WAV assets and never invokes this tool.
param([string]$PiperPath, [string]$ModelPath, [string]$GreetingModelPath, [string]$OnlyIds)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $PiperPath) { $PiperPath = Join-Path $projectRoot 'tools/narration/engine/piper/piper.exe' }
if (-not $ModelPath) { $ModelPath = Join-Path $projectRoot 'tools/narration/en_GB-alba-medium.onnx' }
if (-not $GreetingModelPath) { $GreetingModelPath = Join-Path $projectRoot 'tools/narration/en_GB-vctk-medium.onnx' }
if (-not (Test-Path -LiteralPath $PiperPath) -or -not (Test-Path -LiteralPath $ModelPath)) { throw 'The optional standalone Piper authoring binary and Alba model are needed to rebake voices. Neither is needed to play.' }
$gameContent = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $projectRoot 'data/game.json') | ConvertFrom-Json
$presentation = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $projectRoot 'data/presentation.json') | ConvertFrom-Json
$lines = @()
foreach ($stage in $gameContent.stages) {
    if ($stage.letter_id) {
        $lines += @{ id = $stage.letter_id; text = $stage.letter; file = 'narration/' + $stage.letter_id + '.wav' }
        $actor = $presentation.characters.($stage.npc.ToLowerInvariant())
        foreach ($kind in @('greeting','task','success','wrong')) {
            $lines += @{ id = $kind + '_' + $stage.id; text = $actor.$kind; file = 'characters/' + $stage.id + '/' + $kind + '.wav'; speaker = $actor.voice_id; speed = $actor.voice_speed }
        }
    }
}
$lines += @{ id = 'intro'; text = $presentation.intro; file = 'narration/intro.wav' }
$lines += @{ id = 'ending'; text = $gameContent.ending; file = 'narration/ending.wav' }
$manifest = @{}
if ($OnlyIds) {
    $existing = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $projectRoot 'assets/audio/manifest.json') | ConvertFrom-Json
    foreach ($property in $existing.PSObject.Properties) { $manifest[$property.Name] = $property.Value }
    $selectedIds = $OnlyIds.Split(',')
    $lines = @($lines | Where-Object { $_.id -in $selectedIds })
}
foreach ($line in $lines) {
    $destination = Join-Path $projectRoot ('assets/audio/' + $line.file)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $PiperPath
    $selectedModel = $ModelPath
    $speakerOption = ''
    $voiceName = 'en_GB-alba-medium'
    if ($line.ContainsKey('speaker')) {
        if (-not (Test-Path -LiteralPath $GreetingModelPath)) { throw 'The optional VCTK model is needed to rebake NPC greetings.' }
        $selectedModel = $GreetingModelPath
        $speakerOption = ' --speaker ' + $line.speaker
        $voiceName = 'en_GB-vctk-medium speaker ' + $line.speaker
    }
    $lengthScale = '1.06'
    if ($line.ContainsKey('speed')) { $lengthScale = $line.speed.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    $startInfo.Arguments = '--model "' + $selectedModel + '" --output_file "' + $destination + '" --length_scale ' + $lengthScale + ' --sentence_silence 0.3 --noise_scale 0.5 --noise_w 0.65 --quiet' + $speakerOption
    $startInfo.WorkingDirectory = Split-Path -Parent $PiperPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($line.text + "`n")
    $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
    $process.StandardInput.BaseStream.Flush()
    $process.StandardInput.Close()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $destination)) { throw ('Narration failed for ' + $line.id) }
    $process.Dispose()
    $manifest[$line.id] = @{ path = 'res://assets/audio/' + $line.file; text = $line.text; voice = $voiceName }
    Write-Output ('Rendered ' + $line.id)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $projectRoot 'assets/audio/manifest.json')
