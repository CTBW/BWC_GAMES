$ErrorActionPreference = 'Stop'
$MixarWorkspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$MixarInstall = Join-Path $MixarWorkspace '.cache/mixar/app/Mixar'
$MixarExecutable = Join-Path $MixarInstall 'mixar.exe'
$MixarPython = Join-Path $MixarInstall '5.2/python/bin/python.exe'
$MixarBridge = Join-Path $MixarInstall '5.2/scripts/mixar/mcp.py'
if (!(Test-Path -LiteralPath $MixarExecutable) -or !(Test-Path -LiteralPath $MixarBridge)) {
    throw 'Mixar is not installed in this workspace. See knowledge/mixar-setup.md.'
}
$env:MIXAR_USER_RESOURCES = Join-Path $MixarWorkspace '.cache/mixar/profile'
$env:MIXAR_USER_CONFIG = Join-Path $env:MIXAR_USER_RESOURCES 'config'
$env:MIXAR_MCP_DISCOVERY_DIR = Join-Path $MixarWorkspace '.cache/mixar/runtime/mcp'
$env:PYTHONUTF8 = '1'
foreach ($MixarDirectory in @($env:MIXAR_USER_CONFIG, $env:MIXAR_MCP_DISCOVERY_DIR)) {
    New-Item -ItemType Directory -Force -Path $MixarDirectory | Out-Null
}
