param(
    [Parameter(Mandatory=$true)][string]$Label,
    [ValidateSet("frame_only","full")][string]$DetailMode = "frame_only",
    [int]$DurationSeconds = 30,
    [int]$IntervalSeconds = 5,
    [switch]$ForceStopBefore
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
    $Nonce = "r14_{0}_{1}" -f $Action,(Get-Random)
    $Envelope = @{
        schemaVersion=1; nonce=$Nonce; action=$Action;
        allowlist=@("device_lab.v1",$Action)
    }
    foreach($k in $Extra.Keys){ $Envelope[$k]=$Extra[$k] }
    $Json = $Envelope | ConvertTo-Json -Compress -Depth 5
    $Temp = Join-Path $env:TEMP ("dl_{0}.json" -f $Nonce)
    Set-Content -LiteralPath $Temp -Value $Json -Encoding UTF8 -NoNewline
    & $Adb push $Temp "$ExtInbox/pending.json" | Out-Null
    Remove-Item $Temp -Force
    for($i=0;$i -lt 30;$i++){
        Start-Sleep -Milliseconds 400
        $Result = & $Adb shell run-as $Package cat "$IntOutbox/result_$Nonce.json" 2>$null
        if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($Result -join ""))){ return ($Result -join "`n") }
    }
    return $null
}

if($ForceStopBefore){ & $Adb shell am force-stop $Package | Out-Null; Start-Sleep -Seconds 1 }
& $Adb shell mkdir -p $ExtInbox 2>$null | Out-Null
& $Adb logcat -c 2>$null

# Continuous log owner starts before app launch. This avoids OEM ring-buffer
# rollover deleting LOADING-TOTAL / LOADING-WORKSET / SESSION-ID.
$LiveLog = Join-Path $OutDir "logcat_live.txt"
$LiveErr = Join-Path $OutDir "logcat_live.err.txt"
$LogProc = Start-Process -FilePath $Adb -ArgumentList @("logcat","-v","threadtime","godot:I","*:S") -RedirectStandardOutput $LiveLog -RedirectStandardError $LiveErr -PassThru -NoNewWindow
try {
    & $Adb shell am start -n $Package/com.godot.game.GodotAppLauncher | Out-Null
    $Ready=$false
    for($i=0;$i -lt 90;$i++){
        $Status=Invoke-LabCommand "status"
        if($null -ne $Status){ $Ready=$true; break }
        Start-Sleep -Seconds 2
    }
    if(-not $Ready){ throw "DeviceLab never became ready" }

    $Reset=Invoke-LabCommand "reset_diagnostics" @{detailMode=$DetailMode}
    if($null -eq $Reset){ throw "reset_diagnostics timed out" }
    Set-Content (Join-Path $OutDir "reset.json") $Reset -Encoding UTF8

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
}
finally {
    if($null -ne $LogProc -and -not $LogProc.HasExited){ Stop-Process -Id $LogProc.Id -Force }
}

Select-String -Path $LiveLog -Pattern "LOADING-TOTAL|LOADING-WORKSET|SESSION-ID|WorldBootstrapProfile|FRAME-STALL|SCRIPT ERROR|ERROR|FATAL" |
    Set-Content (Join-Path $OutDir "logcat_markers.txt") -Encoding UTF8
Write-Output "R14_COLLECTION_DONE label=$Label detail=$DetailMode outdir=$OutDir"
