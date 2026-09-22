# R13 device collection helper (diagnostics-only, no gameplay behavior).
# Writes one DeviceLab mailbox command into the EXTERNAL mirror inbox
# (/sdcard/Android/data/<pkg>/files/device_lab/inbox) which adb shell can
# write on Huawei devices (internal user:// inbox is SELinux-denied), then
# drains the result from the INTERNAL outbox via run-as. Also captures logcat
# loading markers.
#
# Usage:
#   & tools\collect_r13_device.ps1 -Label A -DurationSeconds 120 -ForceStopBefore -ResetDiagnosticsBefore
#   (scenes D/E/F keep the process alive: omit -ForceStopBefore)
param(
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [int]$DurationSeconds = 90,
    [int]$IntervalSeconds = 5,
    [switch]$ForceStopBefore,
    [switch]$ResetDiagnosticsBefore
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$Adb = "C:\Users\Administrator\AppData\Local\Temp\HardCore-platform-tools\platform-tools\adb.exe"
$Package = "com.personal.mafaoffline"
$ExtInbox = "/sdcard/Android/data/$Package/files/device_lab/inbox"
$IntOutbox = "/data/user/0/$Package/files/device_lab/outbox"

$OutDir = Join-Path $ProjectRoot ("outputs\r13_device\{0}_{1}" -f $Label, (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Write-Output "OUTDIR=$OutDir"

function Invoke-LabCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        [string]$Nonce
    )
    if ([string]::IsNullOrWhiteSpace($Nonce)) {
        $Nonce = "r13_{0}_{1}" -f $Action, (Get-Random)
    }
    $Envelope = @{
        schemaVersion = 1
        nonce = $Nonce
        action = $Action
        allowlist = @("device_lab.v1", $Action)
    } | ConvertTo-Json -Compress -Depth 4
    # Write the envelope via a local temp file + adb push (shell-writable FUSE path).
    $TempFile = Join-Path $env:TEMP ("dl_{0}_{1}.json" -f $Nonce, (Get-Random))
    Set-Content -LiteralPath $TempFile -Value $Envelope -Encoding UTF8 -NoNewline
    & $Adb push $TempFile "$ExtInbox/pending.json" | Out-Null
    Remove-Item -LiteralPath $TempFile -Force
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Milliseconds 500
        $Result = & $Adb shell run-as $Package cat "$IntOutbox/result_$Nonce.json" 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($Result -join ""))) {
            return ($Result -join "`n")
        }
    }
    return $null
}

# Optional cold start: force-stop (never clear data).
if ($ForceStopBefore) {
    & $Adb shell am force-stop $Package | Out-Null
    Start-Sleep -Seconds 2
}
# Ensure the external mirror inbox exists (shell creates it under FUSE).
& $Adb shell mkdir -p $ExtInbox 2>$null | Out-Null
& $Adb logcat -c 2>$null

# Start the game (idempotent if already running).
& $Adb shell am start -n $Package/com.godot.game.GodotAppLauncher | Out-Null

# Wait until the DeviceLab mailbox responds (game_root._ready mounts the
# runtime node only after loading; a reset issued earlier would be lost
# because no service is polling yet).
$Ready = $false
for ($i = 0; $i -lt 90; $i++) {
    $Probe = Invoke-LabCommand -Action "status"
    if ($null -ne $Probe) {
        $Ready = $true
        Write-Output "device_lab ready after ~$($i * 5)s"
        break
    }
    Start-Sleep -Seconds 5
}
if (-not $Ready) {
    Write-Output "WARN: device lab never became ready"
}

if ($ResetDiagnosticsBefore) {
    $Reset = Invoke-LabCommand -Action "reset_diagnostics"
    if ($null -eq $Reset) { Write-Output "WARN: reset_diagnostics timed out" }
}

$Start = Get-Date
$SnapshotIndex = 0
$Diagnostics = @()
while (((Get-Date) - $Start).TotalSeconds -lt $DurationSeconds) {
    $SnapshotIndex++
    $Snapshot = Invoke-LabCommand -Action "snapshot"
    if ($null -ne $Snapshot) {
        $File = Join-Path $OutDir ("snapshot_{0:D2}.json" -f $SnapshotIndex)
        Set-Content -LiteralPath $File -Value $Snapshot -Encoding UTF8
        Write-Output "snapshot ${SnapshotIndex} saved"
    } else {
        Write-Output "snapshot ${SnapshotIndex} timeout"
    }
    $Diag = Invoke-LabCommand -Action "read_diagnostics"
    if ($null -ne $Diag) {
        $DiagFile = Join-Path $OutDir ("diagnostics_{0:D2}.json" -f $SnapshotIndex)
        Set-Content -LiteralPath $DiagFile -Value $Diag -Encoding UTF8
        $Diagnostics += $DiagFile
    }
    Start-Sleep -Seconds $IntervalSeconds
}

# Final diagnostics readout at scene end.
$FinalDiag = Invoke-LabCommand -Action "read_diagnostics"
if ($null -ne $FinalDiag) {
    Set-Content -LiteralPath (Join-Path $OutDir "diagnostics_final.json") -Value $FinalDiag -Encoding UTF8
    Write-Output "final diagnostics saved"
}
$FinalSnap = Invoke-LabCommand -Action "snapshot"
if ($null -ne $FinalSnap) {
    Set-Content -LiteralPath (Join-Path $OutDir "snapshot_final.json") -Value $FinalSnap -Encoding UTF8
    Write-Output "final snapshot saved"
}

# Capture logcat markers (loading totals, prewarm, frame probes, errors).
& $Adb logcat -d 2>$null | Select-String -Pattern "LOADING-TOTAL|LOADING-WORKSET|LOADING-PROBE|SESSION-ID|WorldBootstrapProfile|SCRIPT ERROR|Assertion failed|ERROR|FATAL" |
    Set-Content -LiteralPath (Join-Path $OutDir "logcat_markers.txt") -Encoding UTF8
Write-Output "COLLECTION_DONE label=$Label outdir=$OutDir"
