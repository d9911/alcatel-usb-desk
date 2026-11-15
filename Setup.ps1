[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\src\Alcatel.Core.ps1"
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Archive\Microsoft.PowerShell.Archive.psd1') -ErrorAction Stop

try {
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        throw 'This package targets Windows x64 (Intel/AMD).'
    }
    $dependency = Get-Dependency
    $downloads = Join-Path $PSScriptRoot 'downloads'
    [void][IO.Directory]::CreateDirectory($downloads)
    $archive = Join-Path $downloads $dependency.archive
    if (-not (Test-Path -LiteralPath $archive)) {
        $temporary = $archive + '.partial'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Write-Host "Downloading scrcpy $($dependency.scrcpyVersion) and bundled ADB from Genymobile..."
            Invoke-WebRequest -Uri $dependency.url -OutFile $temporary -UseBasicParsing -TimeoutSec 180
            if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $dependency.sha256) { throw 'Download checksum mismatch. Nothing was installed.' }
            Move-Item -LiteralPath $temporary -Destination $archive
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $dependency.sha256) {
        throw 'Cached archive checksum mismatch. Remove the damaged ZIP from downloads and run Setup.cmd again.'
    }
    $tools = Join-Path $PSScriptRoot 'tools'
    [void][IO.Directory]::CreateDirectory($tools)
    $stage = Join-Path $tools ('.setup-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $stage
        $name = 'scrcpy-win64-v' + $dependency.scrcpyVersion
        $source = Join-Path $stage $name
        foreach ($required in @('scrcpy.exe', 'adb.exe', 'scrcpy-server', 'SDL3.dll', 'LICENSE.txt')) {
            if (-not (Test-Path -LiteralPath (Join-Path $source $required))) { throw "Archive is missing $required." }
        }
        $destination = Get-ToolDirectory
        if (Test-Path -LiteralPath $destination) {
            # Idempotence also detects damaged or modified installations, not just missing EXEs.
            foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
                $relative = $file.FullName.Substring($source.Length + 1)
                $installed = Join-Path $destination $relative
                if (-not (Test-Path -LiteralPath $installed) -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
                    throw "Installed file differs: $relative. Rename the existing tools\$name folder, then run Setup.cmd again."
                }
            }
            Write-Host 'Existing scrcpy installation matches the verified archive.'
        } else { Move-Item -LiteralPath $source -Destination $destination }
    } finally {
        # Only this invocation's GUID staging directory, resolved under this project's tools.
        $resolvedStage = [IO.Path]::GetFullPath($stage)
        if (-not $resolvedStage.StartsWith([IO.Path]::GetFullPath($tools) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path.' }
        if (Test-Path -LiteralPath $resolvedStage) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
    }
    Write-Host (Invoke-Tool (Join-Path (Get-ToolDirectory) 'scrcpy.exe') @('--version')).Output
    & (Join-Path $PSScriptRoot 'src\Alcatel.Scroll.ps1') -Check
    Write-Host 'Ready. Run Start.cmd. No Android app, Python, Node.js or administrator rights are required.'
    exit 0
} catch { Write-Error -ErrorAction Continue $_; exit 1 }
