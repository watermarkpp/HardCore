# WALL-P0 local round: lab modes A-D + formal map matrix, then report.
# Results land in outputs/wall_perf/ as JSON files + wall_perf_report.md.
param(
    [int]$Walls = 100,
    [int]$LabSeconds = 20,
    [int]$MapSeconds = 25,
    [switch]$SkipLabs
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
$godot = ".\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
New-Item -ItemType Directory -Force -Path "outputs\wall_perf" | Out-Null
# Same-condition round: previous window JSONs must not mix into this report.
Get-ChildItem "outputs\wall_perf" -Filter "wallperf_*.json" -ErrorAction SilentlyContinue |
    Remove-Item -Force

function Invoke-Lab([string]$Mode) {
    Write-Host "=== LAB mode=$Mode walls=$Walls seconds=$LabSeconds ==="
    & $godot --path . `
        --display-driver windows --rendering-method gl_compatibility `
        --audio-driver Dummy --resolution 1600x900 `
        res://tools/wall_perf_lab.tscn -- `
        "mode=$Mode" "walls=$Walls" "seconds=$LabSeconds" "screenshot=1" `
        2>&1 | Select-String "LAB_VALIDATE|WALL_PERF_SUMMARY|SCREENSHOT|SCRIPT ERROR"
}

foreach ($mode in @("A", "B", "C", "D", "E")) {
    if ($SkipLabs) { break }
    Invoke-Lab $mode
}

Write-Host "=== MATRIX (runner built-in map list) seconds=$MapSeconds ==="
& $godot --path . `
    --display-driver windows --rendering-method gl_compatibility `
    --audio-driver Dummy --resolution 1600x900 `
    res://tools/wall_perf_matrix_runner.tscn -- `
    "seconds=$MapSeconds" "stabilize=8" `
    2>&1 | Select-String "WALL_PERF_MATRIX|WALL_PERF_SUMMARY|SCRIPT ERROR"

Write-Host "=== REPORT ==="
$summaryFiles = Get-ChildItem "outputs\wall_perf" -Filter "wallperf_*.json" |
    Sort-Object LastWriteTime
$json = $summaryFiles | ForEach-Object {
    Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
}
$report = @()
$report += "# WALL-P0 本地基准轮（桌面 GPU，结构对比参考，非设备结论）"
$report += ""
$report += "| 窗口 | 逻辑命令 | Y-sort命令 | 段包装 | 动态子节点 | 可见段 | 静态精灵 | render_obj(avg) | draw_call(avg) | node(avg) | P50(ms) | P95(ms) | P99(ms) |"
$report += "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
foreach ($s in $json) {
    $report += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} |" -f `
        $s.label, $s.logical_total, $s.logical_y_sort, $s.wrapper_count,
        $s.wrapper_dynamic_children, $s.visible_wrappers,
        $s.static_sprite_count, $s.render_objects.avg, $s.draw_calls.avg,
        $s.object_nodes.avg, $s.frame_ms.p50, $s.frame_ms.p95, $s.frame_ms.p99)
}
$reportPath = "outputs\wall_perf\wall_perf_report.md"
$report | Set-Content $reportPath -Encoding UTF8
Write-Host "report written: $reportPath"
Get-Content $reportPath
