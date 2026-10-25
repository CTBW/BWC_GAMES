param([switch]$SkipCapture, [switch]$Baseline)
$ErrorActionPreference = 'Stop'
$motionProject = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$motionRepo = (Resolve-Path (Join-Path $motionProject '../../../..')).Path
$motionOutput = Join-Path $motionRepo 'workspace/2026-10-20_meridius/motion-study'
$motionRaw = Join-Path $motionProject 'tests/visual/out/motion-study'
$motionFfmpeg = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe'
$motionBash = 'C:/Program Files/Git/bin/bash.exe'
New-Item -ItemType Directory -Force -Path $motionOutput | Out-Null
Push-Location $motionProject
try {
    if (-not $SkipCapture) {
        & $motionBash tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy -s res://tests/visual/footman_motion_study.gd -- capture
        if ($LASTEXITCODE -ne 0) { throw 'Native motion capture failed' }
    }
    $motionPosters = @{move='0040'; attack='0025'; shield_bash='0026'; charge='0102'}
    foreach ($motionClip in @('move','attack','shield_bash','charge')) {
        & $motionFfmpeg -hide_banner -loglevel error -y -framerate 30 -i (Join-Path $motionRaw "$motionClip/%04d.png") -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an (Join-Path $motionOutput "$motionClip.mp4")
        if ($LASTEXITCODE -ne 0) { throw "Encoding failed: $motionClip" }
        Copy-Item -LiteralPath (Join-Path $motionRaw "$motionClip/$($motionPosters[$motionClip]).png") -Destination (Join-Path $motionOutput "$motionClip.png")
        Write-Output "DELIVERED $motionClip.mp4"
    }
    Copy-Item -LiteralPath (Join-Path $motionRaw 'manifest.json') -Destination (Join-Path $motionOutput 'manifest.json')
    if ($Baseline) {
        & $motionBash tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy -s res://tests/visual/footman_lab.gd -- march melee
        if ($LASTEXITCODE -ne 0) { throw 'Baseline capture failed' }
        foreach ($motionCase in @('march','melee_ne','melee_sw')) {
            & $motionFfmpeg -hide_banner -loglevel error -y -framerate 20 -i "tests/visual/out/footman_${motionCase}_%03d.png" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an (Join-Path $motionOutput "baseline_$motionCase.mp4")
            if ($LASTEXITCODE -ne 0) { throw "Baseline encoding failed: $motionCase" }
        }
    }
} finally { Pop-Location }
