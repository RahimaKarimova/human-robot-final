param([switch]$Editor, [switch]$Test, [switch]$ResumeMarket, [string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
if (-not $GodotPath) {
    $portable = Join-Path $projectRoot 'tools/godot/Godot_v4.5.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $portable) { $GodotPath = $portable }
    else {
        $installed = Get-Command godot -ErrorAction SilentlyContinue
        if ($installed) { $GodotPath = $installed.Source }
        else { throw 'Godot 4.5+ is needed. Open project.godot in Godot, or use -GodotPath with your executable path.' }
    }
}
# Keep portable engine caches and settings inside this project, including in restricted workspaces.
$runtime = Join-Path $projectRoot 'tools/runtime'
New-Item -ItemType Directory -Force -Path (Join-Path $runtime 'Roaming'),(Join-Path $runtime 'Local') | Out-Null
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $runtime 'Roaming'
    $env:LOCALAPPDATA = Join-Path $runtime 'Local'
    if ($Test) {
        $ErrorActionPreference = 'Continue'
        $output = & $GodotPath --headless --path $projectRoot res://tests/runner.tscn 2>&1
        $engineExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $output | ForEach-Object { Write-Host $_ }
        if ($engineExit -ne 0 -or ($output -join "`n") -match 'SCRIPT ERROR|FAIL:') { throw 'Godot game tests failed.' }
    }
    elseif ($Editor) { & $GodotPath --path $projectRoot --editor }
    elseif ($ResumeMarket) { & $GodotPath --path $projectRoot -- --resume-market }
    else { & $GodotPath --path $projectRoot }
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}
