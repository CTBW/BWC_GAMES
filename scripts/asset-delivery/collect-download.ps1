param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Destination,
  [Parameter(Mandatory=$true)][ValidateSet('PNG','JPEG','FBX','ZIP')][string]$Kind,
  [string]$ExpectedArchiveEntry = ''
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$repoPrefix = $repoRoot.TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$destinationPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Destination))
if (-not $destinationPath.StartsWith($repoPrefix,[System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Destination must stay inside this repository.'
}
$parentPath = [System.IO.Path]::GetDirectoryName($destinationPath)
$ancestorPath = $parentPath
while ($ancestorPath.Length -ge $repoRoot.Length) {
  if (Test-Path -LiteralPath $ancestorPath) {
    $ancestor = Get-Item -LiteralPath $ancestorPath
    if ($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      throw 'Destination ancestors must not be symlinks or junctions.'
    }
  }
  $ancestorPath = [System.IO.Path]::GetDirectoryName($ancestorPath)
  if ([string]::IsNullOrEmpty($ancestorPath)) { break }
}
$sourceFile = Get-Item -LiteralPath $sourcePath
if ($sourceFile.PSIsContainer -or $sourceFile.Length -lt 24) { throw 'Expected a complete, nonempty regular file.' }
if ($sourceFile.Length -gt 268435456) { throw 'File exceeds the 256 MB collector limit; inspect it separately.' }
$bytes = [System.IO.File]::ReadAllBytes($sourcePath)
$stream = New-Object System.IO.MemoryStream(,$bytes)
$details = @{}
try {
  switch ($Kind) {
    'PNG' {
      if ([BitConverter]::ToString($bytes[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A') { throw 'Not a PNG file.' }
    }
    'JPEG' {
      if ($bytes[0] -ne 255 -or $bytes[1] -ne 216) { throw 'Not a JPEG file.' }
    }
    'FBX' {
      if (-not [System.Text.Encoding]::ASCII.GetString($bytes,0,23).StartsWith('Kaydara FBX Binary')) { throw 'Not a binary FBX file.' }
      $details.note = 'Header checked; Blender import is still required.'
    }
    'ZIP' {
      Add-Type -AssemblyName System.IO.Compression
      $archive = New-Object System.IO.Compression.ZipArchive($stream,[System.IO.Compression.ZipArchiveMode]::Read,$true)
      try {
        if ($archive.Entries.Count -eq 0) { throw 'Empty ZIP archive.' }
        $names = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($entry in $archive.Entries) {
          if ([System.IO.Path]::IsPathRooted($entry.FullName) -or $entry.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or $entry.FullName.Contains(':')) { throw 'Unsafe archive entry path.' }
          $entryStream = $entry.Open()
          try { $entryStream.CopyTo([System.IO.Stream]::Null) } finally { $entryStream.Dispose() }
        }
        if ($ExpectedArchiveEntry -and $ExpectedArchiveEntry -notin $names) { throw 'ZIP does not contain the expected model; it may belong to another download.' }
        $details.entries = $names
      } finally { $archive.Dispose() }
    }
  }
  if ($Kind -in @('PNG','JPEG')) {
    Add-Type -AssemblyName System.Drawing
    $decoded = [System.Drawing.Image]::FromStream($stream,$false,$true)
    try { $details.width = $decoded.Width; $details.height = $decoded.Height } finally { $decoded.Dispose() }
  }
} finally { $stream.Dispose() }
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $digest = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') } finally { $sha.Dispose() }
if (Test-Path -LiteralPath $destinationPath) {
  $existing = Get-Item -LiteralPath $destinationPath
  if ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Destination is a symlink or junction.' }
  if ((Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash -ne $digest) { throw 'Destination contains different bytes; choose a new versioned name.' }
  $state = 'already_collected'
} else {
  [System.IO.Directory]::CreateDirectory($parentPath) | Out-Null
  $output = [System.IO.File]::Open($destinationPath,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write)
  try { $output.Write($bytes,0,$bytes.Length) } finally { $output.Dispose() }
  $state = 'collected'
}
[ordered]@{ status=$state; file=$destinationPath.Substring($repoPrefix.Length).Replace('\','/'); kind=$Kind; bytes=$bytes.Length; sha256=$digest; details=$details } | ConvertTo-Json -Depth 4
