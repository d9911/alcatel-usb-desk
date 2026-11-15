[CmdletBinding()]
param([string]$Serial = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\src\Alcatel.Core.ps1"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $script:ProjectRoot 'src\Alcatel.Desktop.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing, System
$device = Resolve-Device @(Get-Devices) $Serial
$directory = Get-ToolDirectory
$logDirectory = Join-Path $script:ProjectRoot 'logs'
[void][IO.Directory]::CreateDirectory($logDirectory)
$prefix = Join-Path $logDirectory ('desktop-usb-test-' + [guid]::NewGuid().ToString('N'))
$title = 'Alcatel UI Process Test ' + [guid]::NewGuid().ToString('N')
$work = [PowerShell]::Create()
$process = $null
try {
    [void]$work.AddScript({
        param($core, $directory, $serial, $prefix, $title)
        $ErrorActionPreference = 'Stop'
        . $core
        $arguments = @("--serial=$serial", '--no-control', '--no-audio', '--no-power-on', '--max-size=640', '--max-fps=5', "--window-title=$title")
        $previousAdb = $env:ADB
        try {
            $env:ADB = Join-Path $directory 'adb.exe'
            $child = Start-Process -FilePath (Join-Path $directory 'scrcpy.exe') -NoNewWindow -ArgumentList (($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ') -WorkingDirectory $directory -RedirectStandardOutput "$prefix.stdout.log" -RedirectStandardError "$prefix.stderr.log" -PassThru
            $child | Add-Member -NotePropertyName LogPrefix -NotePropertyValue $prefix
            $child
        } finally { $env:ADB = $previousAdb }
    }.ToString()).AddArgument((Join-Path $script:ProjectRoot 'src\Alcatel.Core.ps1')).AddArgument($directory).AddArgument($device.Serial).AddArgument($prefix).AddArgument($title)
    $async = $work.BeginInvoke()
    $result = @($work.EndInvoke($async))
    if ($work.Streams.Error.Count -gt 0) { throw $work.Streams.Error[0] }
    if ($result.Count -ne 1) { throw 'Expected exactly one process across the background runspace boundary.' }
    $process = $result[0]
    $work.Dispose(); $work = $null
    if ($process.LogPrefix -ne $prefix) { throw 'Log metadata was lost across the background runspace boundary.' }
    $feed = [Alcatel.Desktop.LogFeed]::new($logDirectory)
    $feed.Attach("$prefix.stdout.log", 'Phone/stdout')
    $feed.Attach("$prefix.stderr.log", 'Phone/stderr')
    $text = ''
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $process.Refresh()
        foreach ($line in $feed.Poll()) { $text += $line.Text + "`n" }
        if ($process.HasExited) { throw "Test scrcpy exited before rendering. $text" }
        if ($process.MainWindowTitle -eq $title -and $process.MainWindowHandle -ne [IntPtr]::Zero -and $text -match 'Texture(?: \([^)]+\))?:') { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($process.MainWindowTitle -ne $title -or $text -notmatch 'Texture(?: \([^)]+\))?:') { throw "No rendered window/live native log within 15 seconds. $text" }
    Write-Host 'PASS USB desktop: background process/metadata, visible scrcpy window, incremental native logs after runspace disposal.'
} finally {
    if ($null -ne $process) {
        if (-not $process.HasExited) {
            [void]$process.CloseMainWindow()
            if (-not $process.WaitForExit(4000)) { $process.Kill(); $process.WaitForExit() }
        }
        $process.Dispose()
    }
    if ($null -ne $work) { $work.Dispose() }
}
