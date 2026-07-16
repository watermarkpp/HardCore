param(
    [Parameter(Mandatory = $true)][string]$Adb,
    [string]$Package = "com.personal.mafaoffline",
    [Parameter(Mandatory = $true)][string]$OutputCsv,
    [int]$DurationSeconds = 600,
    [int]$IntervalSeconds = 30
)

$ErrorActionPreference = "Continue"
if (Test-Path -LiteralPath $OutputCsv) { Remove-Item -LiteralPath $OutputCsv -Force }
$start = Get-Date
$sampleIndex = 0

function Read-Number([string]$Text, [string]$Pattern) {
    if ($Text -match $Pattern) { return [int64]$Matches[1] }
    return 0
}

function Read-SurfaceFps {
    $rawLayers = & $Adb shell dumpsys SurfaceFlinger --list
    $layer = ""
    foreach ($line in $rawLayers) {
        if ($line -match "RequestedLayerState\{(SurfaceView\[$Package.+?\(BLAST\)#\d+) parentId") {
            $layer = $Matches[1]
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($layer)) { return 0.0 }
    $latency = & $Adb shell "dumpsys SurfaceFlinger --latency '$layer'"
    $timestamps = @()
    foreach ($line in $latency | Select-Object -Skip 1) {
        $parts = "$line" -split "\s+"
        if ($parts.Count -ge 1 -and $parts[0] -match "^\d+$") {
            $value = [int64]$parts[0]
            if ($value -gt 0 -and $value -lt [int64]::MaxValue) { $timestamps += $value }
        }
    }
    if ($timestamps.Count -lt 2) { return 0.0 }
    $seconds = ($timestamps[-1] - $timestamps[0]) / 1000000000.0
    if ($seconds -le 0) { return 0.0 }
    return [math]::Round(($timestamps.Count - 1) / $seconds, 1)
}

while ($true) {
    $elapsed = [int]((Get-Date) - $start).TotalSeconds
    $pidValue = (& $Adb shell pidof $Package).Trim()
    $mem = (& $Adb shell dumpsys meminfo $Package) -join "`n"
    $battery = (& $Adb shell dumpsys battery) -join "`n"
    $gfx = (& $Adb shell dumpsys gfxinfo $Package) -join "`n"
    $row = [PSCustomObject]@{
        Sample = $sampleIndex
        ElapsedSeconds = $elapsed
        Timestamp = (Get-Date).ToString("s")
        ProcessAlive = -not [string]::IsNullOrWhiteSpace($pidValue)
        Pid = $pidValue
        PssKb = Read-Number $mem "TOTAL PSS:\s+(\d+)"
        RssKb = Read-Number $mem "TOTAL RSS:\s+(\d+)"
        BatteryLevel = Read-Number $battery "level:\s+(\d+)"
        TemperatureTenthsC = Read-Number $battery "temperature:\s+(\d+)"
        SurfaceFps = Read-SurfaceFps
        TotalUiFrames = Read-Number $gfx "Total frames rendered:\s+(\d+)"
        JankyUiFrames = Read-Number $gfx "Janky frames:\s+(\d+)"
    }
    $row | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding utf8 -Append
    Write-Output ("M6_SAMPLE {0}/{1} elapsed={2}s alive={3} pss={4}KB rss={5}KB temp={6} fps={7}" -f $sampleIndex, [math]::Ceiling($DurationSeconds / $IntervalSeconds), $elapsed, $row.ProcessAlive, $row.PssKb, $row.RssKb, $row.TemperatureTenthsC, $row.SurfaceFps)
    if ($elapsed -ge $DurationSeconds) { break }
    $sampleIndex += 1
    Start-Sleep -Seconds $IntervalSeconds
}
