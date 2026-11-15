[CmdletBinding()]
param(
    [ValidateSet('App','Phone','Camera','Check','Keyboard')][string]$Action = 'App',
    [string]$Serial = '',
    [ValidateSet(0,90,180,270)][int]$Rotation = 90,
    [switch]$SmokeTest
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\src\Alcatel.Core.ps1"

try {
    $script:Settings = Read-Settings
    if ($Action -ne 'App') {
        $device = Resolve-Device @(Get-Devices) $Serial
        switch ($Action) {
            'Check' { Get-DeviceReport $device.Serial }
            'Keyboard' { Open-KeyboardSettings $device.Serial }
            default {
                $script:Settings.cameraRotation = $Rotation
                $session = Start-Mirror $script:Settings $device.Serial $Action
                $session.WaitForExit()
                if ($session.ExitCode -ne 0) { throw 'scrcpy failed. See the newest files in logs/.' }
            }
        }
        exit 0
    }
    . "$PSScriptRoot\src\Alcatel.App.ps1"
    Show-AlcatelDesktop -SmokeTest:$SmokeTest
    exit 0
} catch {
    if ($Action -eq 'App' -and -not $SmokeTest) {
        $failure = $_.Exception.Message
        $folder = Join-Path $PSScriptRoot 'logs'
        [void][IO.Directory]::CreateDirectory($folder)
        [IO.File]::AppendAllText((Join-Path $folder 'app-errors.log'), ([DateTime]::Now.ToString('s') + ' ' + $failure + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($failure, 'Alcatel USB Desk', 'OK', 'Error')
    } else { Write-Error -ErrorAction Continue $_ }
    exit 1
}
