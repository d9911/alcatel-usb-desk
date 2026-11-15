[CmdletBinding()]
param(
    [switch]$Check,
    [int]$MirrorProcessId,
    [string]$Serial = ''
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Alcatel.Core.ps1"
Add-Type -Path (Join-Path $PSScriptRoot 'Alcatel.Scroll.cs') -ReferencedAssemblies System.Windows.Forms, System
if ($Check) { Write-Host 'Wheel scroll support compiles.'; return }
$session = $null
try {
    $directory = Get-ToolDirectory
    $session = New-Object Alcatel.WheelScrollSession($MirrorProcessId, (Join-Path $directory 'scrcpy.exe'), (Join-Path $directory 'adb.exe'), $Serial, (Get-Dependency).scrcpyVersion)
    $session.Run()
} finally {
    if ($null -ne $session) { $session.Dispose() }
}
