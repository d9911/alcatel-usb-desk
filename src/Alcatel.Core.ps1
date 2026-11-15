# Shared by the desktop app, CLI and offline tests. Compatible with Windows PowerShell 5.1.
Set-StrictMode -Version Latest
# A CMD launched from PowerShell 7 may inherit its module search path. Load the
# Windows PowerShell modules by absolute path rather than importing a PS7 version.
foreach ($module in @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility')) {
    Import-Module (Join-Path $PSHOME "Modules\$module\$module.psd1") -ErrorAction Stop
}
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

function Get-Dependency {
    Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'dependencies.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ToolDirectory {
    Join-Path $script:ProjectRoot ('tools\scrcpy-win64-v' + (Get-Dependency).scrcpyVersion)
}

function Assert-Settings($Settings) {
    if ($Settings.language -notin @('ru', 'en', 'es')) { throw 'Invalid interface language.' }
    if ($Settings.enableSpanish -isnot [bool]) { throw 'enableSpanish must be a boolean.' }
    if ($Settings.language -eq 'es' -and -not $Settings.enableSpanish) { throw 'Enable Spanish before selecting it.' }
    if ($Settings.serial -isnot [string] -or $Settings.serial -notmatch '^[A-Za-z0-9_.:-]*$') { throw 'Invalid device serial.' }
    if ($Settings.cameraRotation -notin @(0, 90, 180, 270)) { throw 'Rotation must be 0, 90, 180 or 270.' }
    if ($Settings.cameraCrop -isnot [string] -or ($Settings.cameraCrop -ne '' -and $Settings.cameraCrop -notmatch '^[1-9][0-9]*:[1-9][0-9]*:[0-9]+:[0-9]+$')) { throw 'Crop must be empty or width:height:x:y.' }
    foreach ($key in @('maxFps', 'maxSize')) {
        if ($Settings.$key -isnot [int] -and $Settings.$key -isnot [long]) { throw "$key must be an integer." }
    }
    if ($Settings.maxFps -lt 1 -or $Settings.maxFps -gt 120) { throw 'FPS must be between 1 and 120.' }
    if ($Settings.maxSize -lt 320 -or $Settings.maxSize -gt 8192) { throw 'Maximum size must be between 320 and 8192.' }
}

function Read-Settings([string]$Path = (Join-Path $script:ProjectRoot 'config\settings.local.json')) {
    $settings = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'config\defaults.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (Test-Path -LiteralPath $Path) {
        $overrides = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $overrides.PSObject.Properties) {
            if ($settings.PSObject.Properties.Name -notcontains $property.Name) { throw "Unknown setting: $($property.Name)" }
            $settings.($property.Name) = $property.Value
        }
    }
    Assert-Settings $settings
    $settings
}

function Save-Settings($Settings, [string]$Path = (Join-Path $script:ProjectRoot 'config\settings.local.json')) {
    Assert-Settings $Settings
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Settings | ConvertTo-Json) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

function Save-InterfacePreferences([ValidateSet('en','ru','es')][string]$Language, [bool]$EnableSpanish, [string]$Path = (Join-Path $script:ProjectRoot 'config\settings.local.json')) {
    # Language changes must not commit unrelated, unsaved camera/device edits.
    $settings = Read-Settings $Path
    $settings.language = $Language
    $settings.enableSpanish = $EnableSpanish
    Save-Settings $settings $Path
}

function Get-Strings([string]$Language) {
    if ($Language -notin @('ru', 'en', 'es')) { throw 'Invalid interface language.' }
    Get-Content -LiteralPath (Join-Path $script:ProjectRoot "locales\$Language.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-NativeArgument([AllowEmptyString()][string]$Value) {
    # Windows CommandLineToArgvW quoting, including trailing backslashes.
    '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}

function Invoke-Tool([string]$File, [string[]]$Arguments, [int]$TimeoutSeconds = 15) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw 'Tools are missing. Run Setup.cmd first.' }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Command timed out after $TimeoutSeconds seconds. Check the USB connection."
        }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result.Trim(); Error = $stderr.Result.Trim() }
        if ($result.ExitCode -ne 0) { throw "Tool failed ($($result.ExitCode)): $($result.Error) $($result.Output)" }
        $result
    } finally { $process.Dispose() }
}

function Invoke-Adb([string[]]$Arguments) {
    Invoke-Tool (Join-Path (Get-ToolDirectory) 'adb.exe') $Arguments
}

function ConvertFrom-AdbDevices([string]$Output) {
    foreach ($line in ($Output -split '\r?\n')) {
        if ($line -match '^(\S+)\s+(device|unauthorized|offline|no permissions)\b(.*)$') {
            $serial = $Matches[1]; $state = $Matches[2]; $details = $Matches[3]
            $model = if ($details -match '\bmodel:(\S+)') { $Matches[1] } else { '' }
            [pscustomobject]@{ Serial = $serial; State = $state; Model = $model; Label = "$serial  $model  [$state]" }
        }
    }
}

function Get-Devices { ConvertFrom-AdbDevices (Invoke-Adb @('devices', '-l')).Output }

function Resolve-Device([object[]]$Devices, [string]$Serial = '') {
    if ($Serial) {
        $matches = @($Devices | Where-Object Serial -eq $Serial)
        if ($matches.Count -ne 1) { throw 'Selected device is not connected. Refresh the device list.' }
        if ($matches[0].State -ne 'device') { throw "Device is $($matches[0].State). Unlock it and authorize USB debugging, or reconnect USB." }
        return $matches[0]
    }
    # Never silently redirect commands when several devices are attached.
    if ($Devices.Count -eq 0) { throw 'No Android device. Connect USB and enable USB debugging.' }
    if ($Devices.Count -ne 1) { throw 'Several devices detected. Select a device explicitly.' }
    Resolve-Device $Devices $Devices[0].Serial
}

function Get-MirrorArguments($Settings, [string]$Serial, [ValidateSet('Phone','Camera')][string]$Mode) {
    Assert-Settings $Settings
    if ($Serial -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Invalid device serial.' }
    $arguments = @("--serial=$Serial", "--max-fps=$($Settings.maxFps)", '--no-audio', '--stay-awake')
    if ($Mode -eq 'Phone') {
        $arguments += @('--window-title=Alcatel Phone', '--keyboard=uhid', '--mouse=sdk', "--max-size=$($Settings.maxSize)")
    } else {
        $arguments += @('--window-title=Alcatel Camera USB', '--mouse=disabled', '--keyboard=disabled', "--display-orientation=$($Settings.cameraRotation)")
        if ($Settings.cameraCrop) { $arguments += "--crop=$($Settings.cameraCrop)" }
    }
    $arguments
}

function Start-Mirror($Settings, [string]$Serial, [ValidateSet('Phone','Camera')][string]$Mode) {
    $directory = Get-ToolDirectory
    $exe = Join-Path $directory 'scrcpy.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Tools are missing. Run Setup.cmd first.' }
    if ($Mode -eq 'Phone') {
        Import-Module (Join-Path $PSHOME 'Modules\CimCmdlets\CimCmdlets.psd1') -ErrorAction Stop
        # Two identical virtual keyboards can receive different Android layout identities.
        # Replace only a phone session from this installation targeting the same serial.
        foreach ($phone in @(Get-Process scrcpy -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -and $_.MainWindowTitle -in @('Alcatel Phone', 'Alcatel 5024D - Android') })) {
            $command = (Get-CimInstance Win32_Process -Filter "ProcessId = $($phone.Id)").CommandLine
            if ($command -match ('(?:^|\s|\")--serial=' + [regex]::Escape($Serial) + '(?:\"|\s|$)')) {
                if (-not $phone.CloseMainWindow() -or -not $phone.WaitForExit(5000)) { throw 'Close the previous phone window, then retry.' }
            }
        }
    }
    if ($Mode -eq 'Camera') {
        foreach ($preview in @(Get-Process scrcpy -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -and $_.MainWindowTitle -eq 'Alcatel Camera USB' })) {
            if (-not $preview.CloseMainWindow() -or -not $preview.WaitForExit(5000)) { throw 'Close the previous Alcatel Camera USB window, then retry.' }
        }
        $activity = Invoke-Adb @('-s', $Serial, 'shell', 'am', 'start', '-a', 'android.media.action.VIDEO_CAMERA')
        if (($activity.Output + $activity.Error) -match '(?im)^Error:|Exception') { throw ($activity.Output + $activity.Error) }
    }
    $logDirectory = Join-Path $script:ProjectRoot 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $prefix = Join-Path $logDirectory ($Mode.ToLowerInvariant() + '-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
    $arguments = Get-MirrorArguments $Settings $Serial $Mode
    # Set ADB for this child only; do not alter the user's global environment.
    $oldAdb = $env:ADB
    try {
        $env:ADB = Join-Path $directory 'adb.exe'
        $mirror = Start-Process -FilePath $exe -NoNewWindow -ArgumentList (($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ') -WorkingDirectory $directory -RedirectStandardOutput "$prefix.stdout.log" -RedirectStandardError "$prefix.stderr.log" -PassThru
        $mirror | Add-Member -NotePropertyName LogPrefix -NotePropertyValue $prefix
        if ($Mode -eq 'Phone') {
            try { [void](Start-WheelScroll $mirror.Id $Serial $prefix) }
            catch {
                [void]$mirror.CloseMainWindow()
                throw
            }
        }
        $mirror
    } finally { $env:ADB = $oldAdb }
}

function Start-WheelScroll([int]$MirrorProcessId, [string]$Serial, [string]$LogPrefix) {
    if ($MirrorProcessId -le 0 -or $Serial -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Invalid scroll target.' }
    $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File',
        (Join-Path $script:ProjectRoot 'src\Alcatel.Scroll.ps1'), '-MirrorProcessId', [string]$MirrorProcessId, '-Serial', $Serial)
    Start-Process -FilePath $shell -WindowStyle Hidden -WorkingDirectory $script:ProjectRoot -ArgumentList (($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ') -RedirectStandardOutput "$LogPrefix.scroll.stdout.log" -RedirectStandardError "$LogPrefix.scroll.stderr.log" -PassThru
}

function Open-KeyboardSettings([string]$Serial) {
    $result = Invoke-Adb @('-s', $Serial, 'shell', 'am', 'start', '-a', 'android.settings.HARD_KEYBOARD_SETTINGS')
    if (($result.Output + $result.Error) -match '(?im)^Error:|Exception') { throw ($result.Output + $result.Error) }
    $result.Output
}

function Get-DeviceReport([string]$Serial) {
    foreach ($property in @('ro.product.model', 'ro.product.device', 'ro.build.version.release', 'ro.build.version.security_patch', 'ro.build.display.id')) {
        "$property`: " + (Invoke-Adb @('-s', $Serial, 'shell', 'getprop', $property)).Output
    }
}
