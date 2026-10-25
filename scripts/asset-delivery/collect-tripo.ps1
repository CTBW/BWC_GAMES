param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$Character,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$Asset,
  [ValidateRange(1,99)][int]$Take = 1,
  [ValidateSet('ZIP','FBX')][string]$Kind = 'ZIP',
  [string]$ExpectedArchiveEntry = '',
  [switch]$Boss
)
$ErrorActionPreference = 'Stop'
$library = 'projects/meridius/references/characters'
if ($Boss) { $library += '/bosses' }
$filename = '{0}__take-{1:D2}.{2}' -f $Asset,$Take,$Kind.ToLowerInvariant()
$destination = "$library/tripo/$Character/$filename"
& (Join-Path $PSScriptRoot 'collect-download.ps1') -Source $Source -Destination $destination -Kind $Kind -ExpectedArchiveEntry $ExpectedArchiveEntry
