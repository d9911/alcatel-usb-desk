[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\src\Alcatel.Core.ps1"
$script:Passed = 0
$script:Failed = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Work, [string]$Pattern) {
    try { & $Work } catch { Assert ($_.Exception.Message -match $Pattern) "Unexpected failure: $_"; return }
    throw "Expected failure matching $Pattern"
}
function Test([string]$Name, [scriptblock]$Work) {
    try { & $Work; $script:Passed++; Write-Host "PASS $Name" }
    catch { $script:Failed++; Write-Host "FAIL $Name`: $_" }
}
$testRoot = Join-Path $script:ProjectRoot 'TestResults'
[void][IO.Directory]::CreateDirectory($testRoot)
$temporary = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    Test 'All PowerShell source parses under the current runtime' {
        foreach ($file in Get-ChildItem -LiteralPath $script:ProjectRoot -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\(tools|downloads|logs|TestResults)\\' }) {
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            Assert ($errors.Count -eq 0) "$($file.Name): $errors"
        }
    }
    Test 'English first-run defaults, Russian available, Spanish opt-in' {
        $settings = Read-Settings (Join-Path $temporary 'absent.json')
        Assert ($settings.language -eq 'en' -and -not $settings.enableSpanish -and $settings.serial -eq '') 'Unexpected first-run defaults.'
        $keys = @((Get-Strings 'en').PSObject.Properties.Name | Sort-Object)
        foreach ($language in @('ru','en','es')) {
            $strings = Get-Strings $language
            Assert ((Compare-Object $keys @($strings.PSObject.Properties.Name | Sort-Object) | Measure-Object).Count -eq 0) "$language is incomplete."
            foreach ($value in $strings.PSObject.Properties.Value) { Assert (-not [string]::IsNullOrWhiteSpace($value)) "$language has an empty translation." }
        }
    }
    Test 'Embedded journal follows appended UTF-8 lines without repeats or broken characters' {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -Path (Join-Path $script:ProjectRoot 'src\Alcatel.Desktop.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing, System
        $feed = [Alcatel.Desktop.LogFeed]::new($temporary)
        $path = Join-Path $temporary 'live.log'
        $feed.Attach($path, 'Phone')
        Assert ($feed.Poll().Count -eq 0) 'A not-yet-created log caused output.'
        $bytes = [Text.Encoding]::UTF8.GetBytes("Связь установлена`r`n")
        [IO.File]::WriteAllBytes($path, $bytes[0..0])
        Assert ($feed.Poll().Count -eq 0) 'An incomplete UTF-8 character was emitted.'
        $stream = [IO.File]::Open($path, [IO.FileMode]::Append)
        try { $stream.Write($bytes, 1, $bytes.Length - 1) } finally { $stream.Dispose() }
        $lines = $feed.Poll()
        Assert ($lines.Count -eq 1 -and $lines[0].Text -ceq 'Связь установлена' -and $lines[0].Source -eq 'Phone') 'UTF-8 or source metadata was lost.'
        Assert ($feed.Poll().Count -eq 0) 'A completed line was emitted twice.'
        [IO.File]::AppendAllText($path, 'partial', [Text.Encoding]::UTF8)
        Assert ($feed.Poll().Count -eq 0) 'An incomplete line was emitted.'
        [IO.File]::AppendAllText($path, " line`n", [Text.Encoding]::UTF8)
        Assert ($feed.Poll()[0].Text -ceq 'partial line') 'An appended line was split or lost.'
    }
    Test 'Journal handles truncated logs, strips terminal escapes and rejects paths outside its log directory' {
        $feed = [Alcatel.Desktop.LogFeed]::new($temporary)
        $path = Join-Path $temporary 'rotated.log'
        $feed.Attach($path, 'Camera')
        [IO.File]::WriteAllText($path, "older log with a pending suffix", [Text.Encoding]::UTF8)
        [void]$feed.Poll()
        [IO.File]::WriteAllText($path, ([char]27 + "[31mERROR" + [char]27 + "[0m`n"), [Text.UTF8Encoding]::new($false))
        $lines = $feed.Poll()
        Assert ($lines.Count -eq 1 -and $lines[0].Text -ceq 'ERROR') 'Truncation retained stale text or ANSI sequences.'
        Assert-Throws { $feed.Attach((Join-Path $temporary '..\outside.log'), 'USB') } 'inside'
    }
    Test 'Settings round-trip preserves Unicode paths and local device choice' {
        $settings = Read-Settings (Join-Path $temporary 'absent.json')
        $path = Join-Path $temporary 'настройки.json'
        $settings.serial = 'example-device'
        $settings.language = 'en'
        Save-Settings $settings $path
        $settings.language = 'ru'
        Save-Settings $settings $path
        $actual = Read-Settings $path
        Assert ($actual.language -eq 'ru' -and $actual.serial -eq 'example-device') 'Saved preferences were lost.'
    }
    Test 'Language autosave survives restart without saving unrelated in-memory edits' {
        $path = Join-Path $temporary 'language-cache.json'
        $settings = Read-Settings $path
        $settings.serial = 'saved-device'
        $settings.cameraRotation = 270
        Save-Settings $settings $path
        $settings.serial = 'unsaved-device'
        $settings.cameraCrop = 'invalid unsaved crop'
        Save-InterfacePreferences 'ru' $false $path
        $restored = Read-Settings $path
        Assert ($restored.language -eq 'ru') 'Russian was not restored on restart.'
        Assert ($restored.serial -eq 'saved-device' -and $restored.cameraRotation -eq 270 -and $restored.cameraCrop -ne $settings.cameraCrop) 'Language switching saved unrelated edits.'
        Save-InterfacePreferences 'es' $true $path
        $restored = Read-Settings $path
        Assert ($restored.language -eq 'es' -and $restored.enableSpanish) 'Optional Spanish was not restored.'
        Save-InterfacePreferences 'en' $false $path
        $restored = Read-Settings $path
        Assert ($restored.language -eq 'en' -and -not $restored.enableSpanish) 'English fallback was not saved.'
    }
    Test 'Reject invalid and unknown configuration without overwriting it' {
        $path = Join-Path $temporary 'bad.json'
        [IO.File]::WriteAllText($path, '{"cameraRotation":45}')
        Assert-Throws { Read-Settings $path } 'Rotation'
        [IO.File]::WriteAllText($path, '{"command":"anything"}')
        Assert-Throws { Read-Settings $path } 'Unknown setting'
        [IO.File]::WriteAllText($path, '{"language":"es"}')
        Assert-Throws { Read-Settings $path } 'Enable Spanish'
        [IO.File]::WriteAllText($path, '{broken')
        Assert-Throws { Read-Settings $path } 'JSON|Invalid|Unexpected'
    }
    Test 'Handle ADB device, offline and authorization states' {
        $devices = @(ConvertFrom-AdbDevices "List of devices attached`r`nalpha device product:x model:5024D_RU`r`nbeta unauthorized`r`ngamma offline`r`n")
        Assert ($devices.Count -eq 3) 'Lost device states.'
        Assert ((Resolve-Device $devices 'alpha').Model -eq '5024D_RU') 'Wrong device selected.'
        Assert-Throws { Resolve-Device $devices 'beta' } 'unauthorized'
        Assert-Throws { Resolve-Device $devices 'gamma' } 'offline'
        Assert-Throws { Resolve-Device $devices 'missing' } 'not connected'
    }
    Test 'Never redirect to another device when selection is ambiguous or stale' {
        $devices = @(ConvertFrom-AdbDevices "one device`ntwo device")
        Assert-Throws { Resolve-Device $devices } 'Several devices'
        Assert-Throws { Resolve-Device @() } 'No Android'
        Assert-Throws { Resolve-Device @($devices[1]) 'one' } 'not connected'
        Assert ((Resolve-Device @($devices[0])).Serial -eq 'one') 'Single-device selection failed.'
    }
    Test 'Phone uses HID for Cyrillic; preview cannot receive keyboard or mouse input' {
        $settings = Read-Settings (Join-Path $temporary 'absent.json')
        $phone = @(Get-MirrorArguments $settings 'example' 'Phone')
        $camera = @(Get-MirrorArguments $settings 'example' 'Camera')
        Assert ($phone -contains '--keyboard=uhid') 'Phone does not use a physical keyboard.'
        Assert ($phone -contains '--mouse=sdk') 'Phone should retain absolute pointer/drag control.'
        Assert ($camera -contains '--keyboard=disabled' -and $camera -contains '--mouse=disabled') 'Camera allows accidental input.'
        Assert ($camera -contains '--window-title=Alcatel Camera USB') 'OBS window title changed.'
        Assert ($phone -contains '--serial=example' -and $camera -contains '--serial=example') 'Device targeting was lost.'
        $settings.cameraCrop = ''
        Assert (-not ((Get-MirrorArguments $settings 'example' 'Camera') -match '^--crop=')) 'Full-screen preview still crops.'
        $settings.serial = 'bad" & command'
        Assert-Throws { Get-MirrorArguments $settings 'example' 'Phone' } 'serial'
    }
    Test 'Wheel support compiles without downloaded developer packages' {
        & (Join-Path $script:ProjectRoot 'src\Alcatel.Scroll.ps1') -Check
        Assert ($null -ne ('Alcatel.ScrollMath' -as [type])) 'Wheel support was not compiled.'
    }
    Test 'Wheel down reveals lower content, wheel up reveals upper content' {
        $display = [Alcatel.DisplaySize]::new(720, 1440)
        $down = [Alcatel.ScrollMath]::Plan($display, 0.5, 0.5, -1)
        $up = [Alcatel.ScrollMath]::Plan($display, 0.5, 0.5, 1)
        Assert ($down.EndY -lt $down.StartY) 'Down wheel does not swipe upward.'
        Assert ($up.EndY -gt $up.StartY) 'Up wheel does not swipe downward.'
        Assert ($down.X -eq $up.X) 'A vertical gesture changed horizontal position.'
        [Alcatel.ScrollMath]::ValidateSerial('example-device')
        Assert-Throws { [Alcatel.ScrollMath]::ValidateSerial('bad;command') } 'serial'
    }
    Test 'Touch packets match the pinned scrcpy control protocol' {
        $display = [Alcatel.DisplaySize]::new(720, 1440)
        $down = [Alcatel.ScrollMath]::TouchPacket($display, 0, 360, 720)
        Assert ([BitConverter]::ToString($down) -eq '02-00-FF-FF-FF-FF-FF-FF-FF-FE-00-00-01-68-00-00-02-D0-02-D0-05-A0-FF-FF-00-00-00-00-00-00-00-00') 'Touch packet differs from the 32-byte network-order contract.'
        $up = [Alcatel.ScrollMath]::TouchPacket($display, 1, 360, 720)
        Assert ($up[1] -eq 1 -and $up[22] -eq 0 -and $up[23] -eq 0) 'Finger release is not encoded.'
        Assert-Throws { [Alcatel.ScrollMath]::TouchPacket($display, 2, 720, 1440) } 'packet'
    }
    Test 'Control stream sends moves then release, and cancels interrupted gestures without a tap' {
        $display = [Alcatel.DisplaySize]::new(720, 1440)
        $swipe = [Alcatel.ScrollMath]::Plan($display, 0.5, 0.5, -1)
        $stream = New-Object IO.MemoryStream
        try {
            [Alcatel.ScrollMath]::WriteSwipe($stream, $display, $swipe, [Func[bool]]{ $false }, [Action[int]]{ param($milliseconds) })
            $bytes = $stream.ToArray()
            Assert ($bytes.Length -eq 320 -and $bytes[1] -eq 0 -and $bytes[289] -eq 1) 'Complete gesture does not contain DOWN, eight MOVEs, UP.'
            for ($i = 1; $i -le 8; $i++) { Assert ($bytes[$i * 32 + 1] -eq 2) 'A movement packet has the wrong action.' }
        } finally { $stream.Dispose() }
        $stream = New-Object IO.MemoryStream
        $script:CancelWheel = $false
        try {
            [Alcatel.ScrollMath]::WriteSwipe($stream, $display, $swipe, [Func[bool]]{ $script:CancelWheel }, [Action[int]]{ param($milliseconds); $script:CancelWheel = $true })
            $bytes = $stream.ToArray()
            Assert ($bytes.Length -eq 64 -and $bytes[33] -eq 3 -and $bytes[54] -eq 0 -and $bytes[55] -eq 0) 'Interrupted gesture did not send CANCEL with zero pressure.'
        } finally { $stream.Dispose() }
    }
    Test 'Wheel bursts are bounded, fractional deltas accumulate and reversal drops stale work' {
        $queue = [Alcatel.WheelAccumulator]::new()
        $queue.Add(40); $queue.Add(40)
        Assert ($queue.Take() -eq 0) 'Fractional wheel input was rounded up.'
        $queue.Add(40)
        Assert ($queue.Take() -eq 1) 'Fractional wheel input was lost.'
        $queue.Add(12000)
        Assert ($queue.Take() -eq 3 -and $queue.Take() -eq 0) 'Wheel queue is unbounded or repeats gestures.'
        $queue.Add(240); $queue.Add(-120)
        Assert ($queue.Take() -eq -1) 'Reversing direction kept stale down/up gestures.'
    }
    Test 'Viewport mapping excludes black bars and reads rotated Android dimensions' {
        $portrait = [Alcatel.ScrollMath]::ParseDisplay('Viewport: displayId=0, orientation=0, logicalFrame=[0, 0, 720, 1440]')
        $landscape = [Alcatel.ScrollMath]::ParseDisplay('Viewport: displayId=0, orientation=1, logicalFrame=[0, 0, 1440, 720]')
        Assert ($landscape.Width -eq 1440 -and $landscape.Height -eq 720) 'Rotation was ignored.'
        [double]$x = 0; [double]$y = 0
        Assert (-not [Alcatel.ScrollMath]::MapPointer(800, 800, $portrait, 10, 400, [ref]$x, [ref]$y)) 'Letterbox margin accepts scroll.'
        Assert ([Alcatel.ScrollMath]::MapPointer(800, 800, $portrait, 400, 400, [ref]$x, [ref]$y)) 'Phone viewport rejects scroll.'
        Assert ($x -eq 0.5 -and $y -eq 0.5) 'Resized window maps to the wrong point.'
        foreach ($display in @($portrait, $landscape)) {
            foreach ($notches in @(-3, 3)) {
                foreach ($position in @(0.0, 1.0)) {
                    $swipe = [Alcatel.ScrollMath]::Plan($display, $position, $position, $notches)
                    Assert ($swipe.X -ge 0 -and $swipe.X -lt $display.Width -and $swipe.StartY -gt 0 -and $swipe.EndY -gt 0 -and $swipe.StartY -lt $display.Height -and $swipe.EndY -lt $display.Height) 'Swipe escaped the screen.'
                }
            }
        }
        Assert-Throws { [Alcatel.ScrollMath]::ParseDisplay('displayId=1, logicalFrame=[0, 0, 720, 1440]') } 'viewport'
    }
    Test 'Real native process receives spaces, quotes, Cyrillic and trailing slashes' {
        $helper = Join-Path $temporary 'аргументы.ps1'
        [IO.File]::WriteAllText($helper, '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); ConvertTo-Json -InputObject @($args) -Compress', [Text.UTF8Encoding]::new($true))
        $expected = @('plain', 'two words', 'Привет', 'a"b', 'C:\space path\', '')
        $result = Invoke-Tool "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$helper) + $expected)
        $actual = $result.Output | ConvertFrom-Json
        Assert ($actual.Count -eq $expected.Count) "Argument count changed: $($result.Output)"
        for ($i = 0; $i -lt $expected.Count; $i++) { Assert ($actual[$i] -ceq $expected[$i]) "Argument $i changed: $($actual[$i])" }
    }
    Test 'Inherited module search paths do not break Windows PowerShell helpers' {
        $helper = Join-Path $temporary 'module-path.ps1'
        $core = (Join-Path $script:ProjectRoot 'src\Alcatel.Core.ps1').Replace("'", "''")
        [IO.File]::WriteAllText($helper, ". '$core'; (Get-FileHash -LiteralPath `$PSCommandPath -Algorithm SHA256).Hash", [Text.UTF8Encoding]::new($true))
        $previousModulePath = $env:PSModulePath
        try {
            $env:PSModulePath = Join-Path $temporary 'unrelated-modules'
            $result = Invoke-Tool "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-ExecutionPolicy','Bypass','-File',$helper)
            Assert ($result.Output -match '^[A-Fa-f0-9]{64}$') 'Hashing failed with an inherited custom module path.'
        } finally { $env:PSModulePath = $previousModulePath }
    }
    Test 'Native failure and timeout surface actionable errors' {
        $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        Assert-Throws { Invoke-Tool $shell @('-NoProfile','-Command','exit 7') } 'Tool failed \(7\)'
        Assert-Throws { Invoke-Tool $shell @('-NoProfile','-Command','Start-Sleep -Seconds 10') 1 } 'timed out'
        Assert-Throws { Invoke-Tool (Join-Path $temporary 'missing.exe') @() } 'Setup.cmd'
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($testRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "$script:Passed passed; $script:Failed failed."
if ($script:Failed -gt 0) { exit 1 }
