param([switch]$Stills, [switch]$EncodeOnly)
$ErrorActionPreference = 'Stop'
$motionProject = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$motionRepo = (Resolve-Path (Join-Path $motionProject '../../../..')).Path
$motionOutput = Join-Path $motionRepo 'workspace/2026-10-20_meridius/motion-study/mixamo'
$motionRaw = Join-Path $motionProject 'tests/visual/out/mixamo-attack'
$motionFfmpeg = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe'
Push-Location $motionProject
try {
    if (-not $EncodeOnly) {
        $motionMode = if ($Stills) { 'stills' } else { 'capture' }
        & 'C:/Program Files/Git/bin/bash.exe' tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy -s res://tests/visual/mixamo_attack_study.gd -- $motionMode
        if ($LASTEXITCODE -ne 0) { throw 'Mixamo capture failed' }
    }
    if (-not $Stills) {
        foreach ($motionClip in @('stab','slash')) {
            & $motionFfmpeg -hide_banner -loglevel error -y -framerate 30 -i (Join-Path $motionRaw "$motionClip/%04d.png") -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an (Join-Path $motionOutput "$motionClip.mp4")
            if ($LASTEXITCODE -ne 0) { throw 'Mixamo encoding failed' }
            $motionPoster = if ($motionClip -eq 'stab') { '0024.png' } else { '0026.png' }
            Copy-Item -LiteralPath (Join-Path $motionRaw "$motionClip/$motionPoster") -Destination (Join-Path $motionOutput "$motionClip.png")
        }
    }
} finally { Pop-Location }
