param([string]$File)
. "$PSScriptRoot/environment.ps1"
if ($File) {
    $MixarFile = (Resolve-Path -LiteralPath $File).Path
    Start-Process -FilePath $MixarExecutable -ArgumentList ('"' + $MixarFile + '"') -WorkingDirectory $MixarWorkspace | Out-Null
} else {
    Start-Process -FilePath $MixarExecutable -WorkingDirectory $MixarWorkspace | Out-Null
}
