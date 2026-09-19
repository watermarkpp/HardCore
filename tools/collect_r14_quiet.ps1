# R14-B0 quiet benchmark collector - zero mailbox traffic inside the window.
# Game is already placed by the user into the target combat scenario.
# Flow: wait DeviceLab ready -> context snapshot (before) ->
#       reset_diagnostics(frame_only) -> SLEEP DurationSeconds (NO commands) ->
#       stop_diagnostics (closes gate, returns exact percentiles) ->
#       context snapshot (after) + optional read_diagnostics/snapshot (post-window).
# The stop command's own work lands after the gate closes, so it never pollutes
# the recorded frame window (DeviceLab _process records the frame interval first,
# then polls commands).
param(
    [Parameter(Mandatory=$true)][string]$Label,
    [ValidateSet("frame_only","full")][string]$DetailMode = "frame_only",
    [int]$DurationSeconds = 50,
    [switch]$PostWindowSnapshot
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
    $Nonce = "r14q_{0}_{1}" -f $Action,(Get-Random)
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

function Save-Json {
    param([string]$Name,[string]$Raw)
    if(-not [string]::IsNullOrWhiteSpace($Raw)){ Set-Content (Join-Path $OutDir $Name) $Raw -Encoding UTF8 }
}

function Get-ContextSnapshot {
    param([string]$Name)
    $Snap = Invoke-LabCommand "snapshot"
    if($null -eq $Snap){ Write-Output "WARN: $Name snapshot failed"; return }
    Save-Json $Name $Snap
    try {
        $s = $Snap | ConvertFrom-Json
        $ea = $s.snapshot.enemy_activity
        $ctx = [ordered]@{
            map_id = $s.snapshot.map.mapId
            map_name = $s.snapshot.map.zone
            player_position = $s.snapshot.player.globalPosition
            total_monster_count = $ea.total
            nearby_enemy_count_8gu = $ea.within_8gu
            nearby_enemy_count_16gu = $ea.within_16gu
            engaged_enemy_count = $ea.engaged_count
            moving_enemy_count = $ea.moving_count
            active_visual_count = $ea.visual_resources_active
            timestamp = $s.snapshot.timestamp
        }
        $ctx | ConvertTo-Json -Compress | Set-Content (Join-Path $OutDir ($Name -replace '\.json$','_context.json')) -Encoding UTF8
        Write-Output "CONTEXT_$Name map=$($ctx.map_id) total=$($ctx.total_monster_count) 8gu=$($ctx.nearby_enemy_count_8gu) 16gu=$($ctx.nearby_enemy_count_16gu) engaged=$($ctx.engaged_enemy_count) moving=$($ctx.moving_enemy_count) visual=$($ctx.active_visual_count)"
    } catch {
        Write-Output "WARN: context parse failed for $Name : $($_.Exception.Message)"
    }
}

# 1. Wait DeviceLab ready (game already running, user already placed).
$Ready=$false
for($i=0;$i -lt 60;$i++){
    $Status=Invoke-LabCommand "status"
    if($null -ne $Status){ $Ready=$true; break }
    Start-Sleep -Seconds 2
}
if(-not $Ready){ throw "DeviceLab never became ready (is the game in-world?)" }
Write-Output "DEVICE_LAB_READY"

# 2. Context snapshot before window.
Get-ContextSnapshot "context_before.json"

# 3. reset_diagnostics opens the performance gate (frame_only by default).
$Reset=Invoke-LabCommand "reset_diagnostics" @{detailMode=$DetailMode}
if($null -eq $Reset){ throw "reset_diagnostics timed out" }
Save-Json "reset.json" $Reset
Write-Output "RESET_OK mode=$DetailMode window_start=$(Get-Date -Format 'HH:mm:ss')"

# 4. Quiet window: no mailbox commands at all.
Start-Sleep -Seconds $DurationSeconds

# 5. stop_diagnostics closes the gate and returns the final window snapshot.
$Stop=Invoke-LabCommand "stop_diagnostics"
if($null -eq $Stop){ throw "stop_diagnostics timed out" }
Save-Json "diagnostics_final.json" $Stop
Write-Output "STOP_OK window_end=$(Get-Date -Format 'HH:mm:ss')"

# 6. Context snapshot after window (post-window, not part of performance window).
Get-ContextSnapshot "context_after.json"

# 7. Optional post-window diagnostics read (also outside the gate).
if($PostWindowSnapshot){
    $Diag=Invoke-LabCommand "read_diagnostics"
    if($null -ne $Diag){ Save-Json "diagnostics_post.json" $Diag }
}

# 8. Hard gates from the final window snapshot.
$pd = (Get-Content (Join-Path $OutDir "diagnostics_final.json") -Raw | ConvertFrom-Json).performance_diagnostics
if($null -eq $pd){ throw "no performance_diagnostics in stop result" }
$hard = [ordered]@{
    detail_mode = $pd.detail_mode
    diagnostics_enabled = $pd.diagnostics_enabled
    timing_enabled = $pd.timing_enabled
    frame_count = $pd.frame_count
    frame_samples_dropped = $pd.frame_samples_dropped
    frame_samples_overflowed = $pd.frame_samples_overflowed
    frame_percentiles_exact = $pd.frame_percentiles_exact
    enemy_physics_calls = $pd.enemy_physics_calls
    enemy_projection_calls = $pd.enemy_projection_calls
}
$hard | ConvertTo-Json -Compress | Set-Content (Join-Path $OutDir "hard_gates.json") -Encoding UTF8
$gatePass = ($pd.detail_mode -eq $DetailMode) -and ($pd.enemy_physics_calls -eq 0) -and
            (-not $pd.timing_enabled) -and ($pd.frame_percentiles_exact -eq $true) -and
            ($pd.frame_samples_dropped -eq 0)
Write-Output ("HARD_GATES detail={0} enabled={1} timing={2} frames={3} dropped={4} exact={5} calls={6}" -f `
    $pd.detail_mode, $pd.diagnostics_enabled, $pd.timing_enabled, $pd.frame_count,
    $pd.frame_samples_dropped, $pd.frame_percentiles_exact, $pd.enemy_physics_calls)
Write-Output "HARD_GATES_PASS=$gatePass"
Write-Output "R14Q_COLLECTION_DONE label=$Label detail=$DetailMode outdir=$OutDir"
