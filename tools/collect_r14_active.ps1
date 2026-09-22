# R14-A active-session collector (v2) - does NOT restart the game.
# User enters the scenario and says "start"; then this script only:
#   waits DeviceLab ready -> reset_diagnostics(detailMode) -> sample loop -> final
# No force-stop, no am start. Game process untouched.
param(
    [Parameter(Mandatory=$true)][string]$Label,
    [ValidateSet("frame_only","full")][string]$DetailMode = "frame_only",
    [int]$DurationSeconds = 90,
    [int]$IntervalSeconds = 5
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Split-Path $PSScriptRoot -Parent)).Path
$Adb = "C:\Users\Administrator\AppData\Local\Temp\HardCore-platform-tools\platform-tools\adb.exe"
$Package = "com.personal.mafaoffline"
$ExtInbox = "/sdcard/Android/data/$Package/files/device_lab/inbox"
$IntOutbox = "/data/user/0/$Package/files/device_lab/outbox"
$OutDir = Join-Path $ProjectRoot ("outputs\r14_device\{0}_{1}_{2}" -f $Label,$DetailMode,(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function Invoke-LabCommand {
    param([string]$Action,[hashtable]$Extra=@{})
    $Nonce = "r14v2_{0}_{1}" -f $Action,(Get-Random)
    $Envelope = @{
        schemaVersion=1; nonce=$Nonce; action=$Action;
        allowlist=@("device_lab.v1",$Action)
    }
    foreach($k in $Extra.Keys){ $Envelope[$k]=$Extra[$k] }
    $Json = $Envelope | ConvertTo-Json -Compress -Depth 5
    $Temp = Join-Path $env:TEMP ("dl_{0}.json" -f $Nonce)
    Set-Content -LiteralPath $Temp -Value $Json -Encoding UTF8 -NoNewline
    & $Adb push $Temp "$ExtInbox/pending.json" 2>$null | Out-Null
    Remove-Item $Temp -Force
    for($i=0;$i -lt 30;$i++){
        Start-Sleep -Milliseconds 400
        $Result = & $Adb shell run-as $Package cat "$IntOutbox/result_$Nonce.json" 2>$null
        if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($Result -join ""))){ return ($Result -join "`n") }
    }
    return $null
}

# Wait for DeviceLab ready (game already running; user already in scenario).
$Ready=$false
for($i=0;$i -lt 60;$i++){
    $Status=Invoke-LabCommand "status"
    if($null -ne $Status){ $Ready=$true; break }
    Start-Sleep -Seconds 2
}
if(-not $Ready){ throw "DeviceLab never became ready (is the game in-world?)" }
Write-Output "DEVICE_LAB_READY"

$Reset=Invoke-LabCommand "reset_diagnostics" @{detailMode=$DetailMode}
if($null -eq $Reset){ throw "reset_diagnostics timed out" }
Set-Content (Join-Path $OutDir "reset.json") $Reset -Encoding UTF8
Write-Output "RESET_OK mode=$DetailMode"

$Start=Get-Date; $Index=0
while(((Get-Date)-$Start).TotalSeconds -lt $DurationSeconds){
    $Index++
    $Diag=Invoke-LabCommand "read_diagnostics"
    if($null -ne $Diag){ Set-Content (Join-Path $OutDir ("diagnostics_{0:D2}.json" -f $Index)) $Diag -Encoding UTF8 }
    $Snap=Invoke-LabCommand "snapshot"
    if($null -ne $Snap){ Set-Content (Join-Path $OutDir ("snapshot_{0:D2}.json" -f $Index)) $Snap -Encoding UTF8 }
    Start-Sleep -Seconds $IntervalSeconds
}
$Final=Invoke-LabCommand "read_diagnostics"
if($null -ne $Final){ Set-Content (Join-Path $OutDir "diagnostics_final.json") $Final -Encoding UTF8 }
$FinalSnap=Invoke-LabCommand "snapshot"
if($null -ne $FinalSnap){ Set-Content (Join-Path $OutDir "snapshot_final.json") $FinalSnap -Encoding UTF8 }
Write-Output "R14V2_COLLECTION_DONE label=$Label detail=$DetailMode outdir=$OutDir"
