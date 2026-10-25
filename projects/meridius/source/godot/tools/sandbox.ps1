## Opens the 3D unit sandbox (prototypes/sandbox3d) in its own maximized window.
## The Workspace's Sandbox card and "Meridius Sandbox.cmd" in the repository root
## start it. A sandbox that is already open is brought to the front instead.
## Godot is found as tools/godot.sh finds it (GODOT overrides), without its console.
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$scene = 'res://prototypes/sandbox3d/scenes/sandbox3d.tscn'
$fromApp = [bool]$env:MRMAK_LAUNCHER

function Fail([string]$message) {
  if ($fromApp) { [Console]::Error.WriteLine($message) }
  else {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($message, 'Meridius sandbox', 'OK', 'Warning')
  }
  exit 1
}

function Find-Godot {
  $candidates = @()
  if ($env:GODOT) {
    $windows = $env:GODOT -replace '^/([a-zA-Z])/', '$1:/'
    # The window build next to a console build: no console behind the game.
    $candidates += $windows -replace '_console\.exe$', '.exe'
    $candidates += $windows
  }
  $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $winget) {
    $candidates += Get-ChildItem $winget -Directory -Filter 'GodotEngine.GodotEngine*' |
      ForEach-Object { Join-Path $_.FullName 'Godot_v4.7.2-stable_win64.exe' }
  }
  $onPath = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($onPath) { $candidates += $onPath.Source }
  return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

$open = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" |
  Where-Object { $_.CommandLine -and $_.CommandLine.Contains('sandbox3d.tscn') } | Select-Object -First 1
if ($open) {
  $shell = New-Object -ComObject WScript.Shell
  [void]$shell.AppActivate([int]$open.ProcessId)
  Write-Output "The sandbox is already open (process $($open.ProcessId)): brought to the front."
  exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $project 'prototypes\sandbox3d\scenes\sandbox3d.tscn'))) {
  Fail "The sandbox scene is missing from $project."
}
$godot = Find-Godot
if (-not $godot) {
  Fail 'Godot 4.7.2 was not found. Install it with "winget install GodotEngine.GodotEngine" or set GODOT to its executable.'
}
$process = Start-Process -FilePath $godot -WorkingDirectory $project -PassThru `
  -ArgumentList @('--path', "`"$project`"", '--maximized', $scene)
Write-Output "Started the sandbox (process $($process.Id))."
