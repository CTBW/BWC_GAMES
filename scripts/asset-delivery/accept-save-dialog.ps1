# Accept the browser's "Save As" dialog for one expected download.
# Finds the dialog (class #32770) on a Chrome or Brave window, checks the
# suggested file name is exactly $Expect (with or without its extension), puts
# $Dir\$Expect in the name box, clicks Save and waits until the file is
# complete on disk. The name box and the Save button are driven with Win32
# messages, since UI Automation reports them as plain panes.
param(
  [Parameter(Mandatory=$true)][string]$Dir,
  [Parameter(Mandatory=$true)][string]$Expect,
  [int]$TimeoutSec = 300
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SaveDlg {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, StringBuilder l);
  [DllImport("user32.dll")]
  public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public static string GetText(IntPtr h) {
    int n = (int)SendMessage(h, 0x000E, IntPtr.Zero, IntPtr.Zero);
    var sb = new StringBuilder(n + 1);
    SendMessage(h, 0x000D, (IntPtr)(n + 1), sb);
    return sb.ToString();
  }
  public static void SetText(IntPtr h, string s) { SendMessage(h, 0x000C, IntPtr.Zero, s); }
  public static void Click(IntPtr h) { SendMessage(h, 0x00F5, IntPtr.Zero, IntPtr.Zero); }
}
'@
$AE = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$root = $AE::RootElement
$browsers = @('chrome', 'brave')
$target = Join-Path $Dir $Expect
if (Test-Path -LiteralPath $target) { throw "Target already exists: $target" }

function Find-SaveDialog {
  $dlgCond = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, '#32770')
  foreach ($w in $root.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    $p = Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue
    if (-not $p -or $p.ProcessName -notin $browsers) { continue }
    if ($w.Current.ClassName -eq '#32770') { return $w }
    $d = $w.FindFirst($Scope::Children, $dlgCond)
    if ($d) { return $d }
  }
  return $null
}

function Find-Control($dlg, [string]$id, [string]$class) {
  $c1 = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, $id)
  $c2 = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, $class)
  $and = New-Object System.Windows.Automation.AndCondition($c1, $c2)
  return $dlg.FindFirst($Scope::Descendants, $and)
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$dlg = $null; $edit = $null; $btn = $null
while ((Get-Date) -lt $deadline) {
  $dlg = Find-SaveDialog
  if ($dlg) {
    $edit = Find-Control $dlg '1001' 'Edit'
    $btn = Find-Control $dlg '1' 'Button'
    if ($edit -and $btn) { break }
  }
  Start-Sleep -Milliseconds 400
}
if (-not ($dlg -and $edit -and $btn)) { throw "No complete save dialog within $TimeoutSec s" }

$hEdit = [IntPtr]$edit.Current.NativeWindowHandle
$hBtn = [IntPtr]$btn.Current.NativeWindowHandle
$suggested = [SaveDlg]::GetText($hEdit)
$bare = [System.IO.Path]::GetFileNameWithoutExtension($Expect)
if ($suggested -ne $Expect -and $suggested -ne $bare) {
  throw "Dialog suggests '$suggested', not '$Expect'; left open"
}
[SaveDlg]::SetText($hEdit, $target)
if ([SaveDlg]::GetText($hEdit) -ne $target) { throw 'Could not set the file name' }
[SaveDlg]::Click($hBtn)

$last = -1
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 700
  if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath "$target.crdownload")) {
    $len = (Get-Item -LiteralPath $target).Length
    if ($len -gt 0 -and $len -eq $last) { break }
    $last = $len
  }
}
if (-not (Test-Path -LiteralPath $target)) { throw "Saved file did not appear: $target" }
[ordered]@{ saved = $target; suggested = $suggested; bytes = (Get-Item -LiteralPath $target).Length } | ConvertTo-Json
