[CmdletBinding()]
param([string]$Serial = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\src\Alcatel.Core.ps1"
& "$PSScriptRoot\..\src\Alcatel.Scroll.ps1" -Check
$device = Resolve-Device @(Get-Devices) $Serial
$directory = Get-ToolDirectory
function Get-ScrollJars {
    (Invoke-Adb @('-s', $device.Serial, 'shell', 'ls /data/local/tmp/alcatel-scroll-*.jar 2>/dev/null; true')).Output
}
$before = (Invoke-Adb @('-s', $device.Serial, 'forward', '--list')).Output
$jarsBefore = Get-ScrollJars
$control = $null
try {
    $control = New-Object Alcatel.ScrcpyControl((Join-Path $directory 'adb.exe'), $device.Serial, (Get-Dependency).scrcpyVersion)
    $during = (Invoke-Adb @('-s', $device.Serial, 'forward', '--list')).Output
    if ($during -eq $before -or (Get-ScrollJars) -eq $jarsBefore) { throw 'Isolated scroll resources were not created.' }
    Write-Host 'PASS control-only server startup and protocol handshake; no gesture sent.'
} finally {
    if ($null -ne $control) { $control.Dispose() }
}
$after = (Invoke-Adb @('-s', $device.Serial, 'forward', '--list')).Output
if ($after -ne $before -or (Get-ScrollJars) -ne $jarsBefore) { throw 'Temporary scroll resources were not removed or existing resources changed.' }
Write-Host 'PASS control server disposal preserved existing forwards and temporary JARs.'
