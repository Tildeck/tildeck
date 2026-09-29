<#
.SYNOPSIS
    Build and run the Tildeck Windows desktop client.

.DESCRIPTION
    Flutter cannot build Windows desktop apps from WSL or Linux, so this is the
    one workflow script that runs on Windows itself (PowerShell 7 or Windows
    PowerShell 5.1). Everything else runs in WSL with Docker.

      scripts\windows.ps1           run the client in debug mode (hot reload)
      scripts\windows.ps1 run       the same
      scripts\windows.ps1 build     release build into out\windows\
      scripts\windows.ps1 check     only check the prerequisites

    Requires Flutter on PATH (the same version as the toolchain pin in
    scripts\toolchain\Dockerfile) and Visual Studio or Build Tools with the
    "Desktop development with C++" workload.

.EXAMPLE
    pwsh -File scripts\windows.ps1 build
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'build', 'check')]
    [string]$Command = 'run'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root 'app'

function Write-Step([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Stop-WithError([string]$Message) {
    Write-Host $Message -ForegroundColor Red
    exit 1
}

# The Flutter version every other build uses, from the toolchain pin.
function Get-PinnedFlutterVersion {
    $pins = Get-Content (Join-Path $Root 'scripts\toolchain\Dockerfile')
    foreach ($line in $pins) {
        if ($line -match '^FROM ghcr\.io/cirruslabs/flutter:([0-9.]+)@\S+ AS flutter$') { return $Matches[1] }
    }
    Stop-WithError 'No Flutter pin found in scripts\toolchain\Dockerfile.'
}

function Test-Prerequisites {
    $problems = @()

    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutter) {
        $problems += 'Flutter is not installed or not on PATH. Install it from https://docs.flutter.dev/get-started/install/windows/desktop and reopen the terminal.'
    }

    # Visual Studio or Build Tools with the C++ desktop toolchain. vswhere
    # ships with every Visual Studio installer.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vcTools = $null
    if (Test-Path $vswhere) {
        $vcTools = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
    if (-not $vcTools) {
        $problems += 'Visual Studio build tools with the "Desktop development with C++" workload are missing. Install them from https://visualstudio.microsoft.com/visual-cpp-build-tools/ and select that workload.'
    }

    if ($problems.Count -gt 0) {
        Write-Host 'The Windows client cannot be built on this machine:' -ForegroundColor Red
        foreach ($problem in $problems) { Write-Host "  - $problem" -ForegroundColor Red }
        exit 1
    }

    $pinned = Get-PinnedFlutterVersion
    $installed = (& flutter --version --machine | ConvertFrom-Json).frameworkVersion
    if ($installed -ne $pinned) {
        Write-Host "Warning: Flutter $installed is installed; the other builds use $pinned. Results may differ." -ForegroundColor Yellow
    }
    Write-Step "Prerequisites OK: Flutter $installed, C++ tools at $vcTools"
}

function Invoke-Flutter([string[]]$Arguments) {
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) { Stop-WithError "flutter $($Arguments -join ' ') failed (exit $LASTEXITCODE)." }
}

Test-Prerequisites
if ($Command -eq 'check') { exit 0 }

$Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()
Push-Location $App
try {
    # The committed pubspec.lock must be current, as in every other build.
    Invoke-Flutter @('pub', 'get', '--enforce-lockfile')
    switch ($Command) {
        'run' {
            Write-Step "Running the Windows client (version $Version, debug) ..."
            Invoke-Flutter @('run', '-d', 'windows')
        }
        'build' {
            Write-Step "Building the Windows client (version $Version, release) ..."
            Invoke-Flutter @('build', 'windows', '--release', "--build-name=$Version")
            $out = Join-Path $Root 'out\windows'
            if (Test-Path $out) { Remove-Item -Recurse -Force $out }
            Copy-Item -Recurse (Join-Path $App 'build\windows\x64\runner\Release') $out
            Write-Step "Built $out\tildeck.exe"
        }
    }
}
finally {
    Pop-Location
}
