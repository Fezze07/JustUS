#Requires -Version 5.1
<#
.SYNOPSIS
    Brings up the configured Android emulator(s) and regenerates the Flutter
    barrel imports.

.DESCRIPTION
    Every machine-specific path is discovered at runtime instead of being
    hardcoded, so this script works from any checkout on any machine:

      * the emulator binary comes from ANDROID_SDK_ROOT / ANDROID_HOME, or is
        resolved from `adb` on PATH;
      * the Flutter project is resolved relative to this script, not from a
        personal absolute path.

    Environment overrides:
      ANDROID_SDK_ROOT / ANDROID_HOME  Android SDK location
      FLUTTER_DIR                      override the Flutter project directory
      EMULATOR_EXTRA_ARGS              extra emulator flags (e.g. "-no-window")

.EXAMPLE
    pwsh ./scripts/init_flutter.ps1
    pwsh ./scripts/init_flutter.ps1 -EmulatorExtraArgs "-no-window -gpu swiftshader_indirect"
#>
[CmdletBinding()]
param(
    [string]$EmulatorExtraArgs = $env:EMULATOR_EXTRA_ARGS,
    [int]$BootTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Locate the Flutter project relative to this script (never a personal path).
# -----------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$flutterDir = if ($env:FLUTTER_DIR) { $env:FLUTTER_DIR } else { Join-Path $repoRoot 'Flutter' }

if (-not (Test-Path -LiteralPath $flutterDir)) {
    Write-Host "ERROR: Flutter project not found at $flutterDir"
    Write-Host "       Set FLUTTER_DIR to override."
    exit 1
}

# -----------------------------------------------------------------------------
# Locate the Android SDK / emulator binary.
# -----------------------------------------------------------------------------
function Resolve-EmulatorPath {
    $candidates = @()

    # 1. Explicit environment variables, in order of convention.
    foreach ($var in @('ANDROID_SDK_ROOT', 'ANDROID_HOME')) {
        $root = [Environment]::GetEnvironmentVariable($var)
        if ($root) {
            $candidates += (Join-Path $root 'emulator\emulator.exe')
            $candidates += (Join-Path $root 'emulator\emulator')
        }
    }

    # 2. Derive it from `adb`, which is usually already on PATH.
    $adb = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($adb) {
        # ...\Android\Sdk\platform-tools\adb.exe -> ...\Android\Sdk\emulator\emulator.exe
        $sdkRoot = Split-Path -Parent (Split-Path -Parent $adb.Source)
        if ($sdkRoot) {
            $candidates += (Join-Path $sdkRoot 'emulator\emulator.exe')
            $candidates += (Join-Path $sdkRoot 'emulator\emulator')
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

Write-Host '------------------------------------------------'
Write-Host 'Checking Emulators...'

$devices = @(
    @{ Avd = 'Partner_Phone'; Port = 5554; Id = 'emulator-5554' }
)

# -----------------------------------------------------------------------------
# Invoke-Adb — run adb and discard its stderr without tripping ErrorActionPreference.
#
# `2>$null` is NOT enough: with $ErrorActionPreference = 'Stop', PowerShell 5.1
# still turns "adb.exe: device offline" (a native command writing to stderr) into
# a terminating NativeCommandError, which aborts the script mid-poll. That is the
# reason this wrapper exists: stderr is routed to the success stream, the
# ErrorRecords are filtered out, and the preference is restored afterwards.
# -----------------------------------------------------------------------------
function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & adb @AdbArgs 2>&1
    }
    finally {
        $ErrorActionPreference = $previous
    }

    return @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
}

function IsDeviceOnline {
    param([string]$id)
    $line = Invoke-Adb devices | Select-String "$id\s+device$"
    return [bool]$line
}

function IsDevicePresent {
    param([string]$id)
    $line = Invoke-Adb devices | Select-String $id
    return [bool]$line
}

function WaitForBoot {
    param(
        [string]$id,
        [int]$TimeoutSeconds = 120
    )
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $bootComplete = Invoke-Adb -s $id shell getprop sys.boot_completed
        if ($bootComplete -and ($bootComplete | Select-Object -First 1).Trim() -eq '1') {
            return $true
        }
        Start-Sleep -Seconds 3
        $elapsed += 3
    }
    return $false
}

function StartEmulator {
    param([string]$avd, [int]$port, [string]$id, [string]$ExtraArgs = '')

    $emulator = Resolve-EmulatorPath
    if (-not $emulator) {
        Write-Host "ERROR: emulator binary not found."
        Write-Host '       Set ANDROID_SDK_ROOT/ANDROID_HOME, or put adb on PATH.'
        return $false
    }

    # ExtraArgs is split into individual flags so a single quoted string such as
    # "-no-window -gpu swiftshader_indirect" becomes two arguments, not one.
    $emulatorArgs = @('-avd', $avd, '-port', $port, '-gpu', 'host')
    if ($ExtraArgs) {
        Write-Host "Extra args: $ExtraArgs"
        $emulatorArgs += ($ExtraArgs -split '\s+' | Where-Object { $_ })
    }

    Write-Host "Starting Emulator $avd on port $port..."
    Start-Process $emulator -ArgumentList $emulatorArgs -ErrorAction Stop

    Write-Host "Waiting for device $id to appear..."
    $elapsed = 0
    while (-not (IsDevicePresent $id) -and $elapsed -lt 60) {
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    if (-not (IsDevicePresent $id)) { return $false }

    Write-Host "Device $id found. Waiting for system boot..."
    return (WaitForBoot -id $id -TimeoutSeconds $bootTimeout)
}

foreach ($device in $devices) {
    $avd = $device.Avd
    $port = $device.Port
    $id = $device.Id

    if (-not (IsDevicePresent $id)) {
        if (-not (StartEmulator $avd $port $id -ExtraArgs $EmulatorExtraArgs)) {
            Write-Host "ERROR: Emulator $avd failed to boot."
            exit 1
        }
    }
    elseif (-not (IsDeviceOnline $id)) {
        Write-Host "Device $id offline, waiting for boot..."
        if (-not (WaitForBoot -id $id -TimeoutSeconds $bootTimeout)) {
            Write-Host "ERROR: Device $id stuck offline. Retrying with cold boot..."
            Invoke-Adb -s $id emu kill | Out-Null
            Start-Sleep -Seconds 2
            if (-not (StartEmulator $avd $port $id -ExtraArgs $EmulatorExtraArgs)) {
                Write-Host "ERROR: Emulator $avd failed to boot after cold boot."
                exit 1
            }
        }
    }
    else {
        Write-Host "Emulator $avd ($id) already online."
    }
}

Write-Host 'All devices are online and ready.'

Write-Host '------------------------------------------------'
Write-Host 'Generating Imports...'
Push-Location $flutterDir
try {
    dart tool/generate_imports.dart
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Import generation failed.'
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}