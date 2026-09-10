param([string]$Repo = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4r2')
# R3 perf: A=diagnostics d446beba (production = R2 enemy bff8986c) vs B=prune 49501f19 (enemy f74a044c).
# Order fixed BEFORE any run: untallied pre-run A, untallied pre-run B, then pairs AB BA AB BA AB BA.
# Validity (fixed): exit 0 AND HC_REV07_FULL_FRAME_PASS AND 12-row JSON. Invalid kept + rerun, never dropped.
$ErrorActionPreference = 'Stop'
$plan = @(
    @{ side = 'A'; commit = 'd446beba'; tally = $false }, @{ side = 'B'; commit = '49501f19'; tally = $false },
    @{ side = 'A'; commit = 'd446beba'; tally = $true },  @{ side = 'B'; commit = '49501f19'; tally = $true },
    @{ side = 'B'; commit = '49501f19'; tally = $true },  @{ side = 'A'; commit = 'd446beba'; tally = $true },
    @{ side = 'B'; commit = '49501f19'; tally = $true },  @{ side = 'A'; commit = 'd446beba'; tally = $true },
    @{ side = 'B'; commit = '49501f19'; tally = $true },  @{ side = 'A'; commit = 'd446beba'; tally = $true },
    @{ side = 'B'; commit = '49501f19'; tally = $true },  @{ side = 'A'; commit = 'd446beba'; tally = $true },
    @{ side = 'B'; commit = '49501f19'; tally = $true }
)
$pairNo = 0
$summary = @()
foreach ($step in $plan) {
    git -C $Repo checkout -q $step.commit
    if ((git -C $Repo branch --show-current) -eq '') { git -C $Repo switch -q -C perf-tmp-$($step.side) $step.commit }
    $head = (git -C $Repo rev-parse HEAD).Trim()
    $tag = if ($step.tally) { "r3_{0}_pair{1}" -f $step.side.ToLower(), $pairNo } else { "r3_{0}_prerun" -f $step.side.ToLower() }
    if ($step.tally) { $pairNo++ }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $stdout = Join-Path $Repo "outputs\test_logs\perf_$tag`_$stamp.stdout.log"
    $stderr = Join-Path $Repo "outputs\test_logs\perf_$tag`_$stamp.stderr.log"
    $engineLog = Join-Path $Repo "outputs\test_logs\perf_$tag`_$stamp.godot.log"
    [Environment]::SetEnvironmentVariable('HARDCORE_REV07_HEAD', $head, 'Process')
    [Environment]::SetEnvironmentVariable('HARDCORE_REV07_LABEL', $tag, 'Process')
    [Environment]::SetEnvironmentVariable('APPDATA', (Join-Path $Repo '.godot\runtime_appdata'), 'Process')
    $godot = Join-Path $Repo 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
    Remove-Item $stdout, $stderr, $engineLog -Force -ErrorAction SilentlyContinue
    $launch = '""' + $godot + '" --headless --log-file "' + $engineLog + '" --path . "tests/hc_monster_ai/performance_comparison_test.tscn" > "' + $stdout + '" 2> "' + $stderr + '"'
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $launch) -WorkingDirectory $Repo -WindowStyle Hidden -PassThru
    $exited = $proc.WaitForExit(150000)
    $code = if ($exited) { $proc.ExitCode } else { taskkill /PID $proc.Id /T /F 2>$null | Out-Null; 'TIMEOUT' }
    Start-Sleep -Milliseconds 300
    $pass = Select-String -Path $stdout -Pattern 'HC_REV07_FULL_FRAME_PASS' -Quiet -ErrorAction SilentlyContinue
    $jsonPath = Join-Path $Repo "outputs\hc_monster_ai_package\rev07_$tag.json"
    $json12 = $false
    if (Test-Path $jsonPath) {
        $rows = (python -c "import json;print(len(json.load(open(r'$jsonPath',encoding='utf-8'))['rows']))" 2>$null)
        $json12 = ($rows -eq '12')
    }
    $valid = ($code -eq 0) -and $pass -and $json12
    $summary += [PSCustomObject]@{ tag = $tag; side = $step.side; commit = $step.commit.Substring(0, 8); head = $head; exit = $code; pass = $pass; json12 = $json12; valid = $valid; tallied = $step.tally }
    Write-Output ("PERF_ROUND tag={0} side={1} commit={2} exit={3} pass={4} json12={5} valid={6} tallied={7}" -f $tag, $step.side, $step.commit.Substring(0, 8), $code, $pass, $json12, $valid, $step.tally)
}
$summary | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Repo 'outputs\m30_r4r3\perf_rounds_index.json')
Write-Output 'R3_PERF_DONE'
