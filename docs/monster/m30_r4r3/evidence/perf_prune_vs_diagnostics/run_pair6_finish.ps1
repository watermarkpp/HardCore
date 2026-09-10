$ErrorActionPreference = 'Stop'
$Repo = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4r2'
# Complete the pre-declared pair 6 (B,A): the missing final A round, same invocation
# path as run_r3_perf.ps1 (13 successful rounds this session).
git -C $Repo switch -q -c perf-tmp-a d446beba 2>$null
git -C $Repo checkout -q d446beba
$head = (git -C $Repo rev-parse HEAD).Trim()
$tag = 'r3_a_pair11'
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
$rows = 0
if (Test-Path $jsonPath) { $rows = (Get-Content $jsonPath -Raw | ConvertFrom-Json).rows.Count }
Write-Output ("PERF_ROUND tag=$tag side=A commit=d446beba exit=$code pass=$pass json12=($rows) head=$($head.Substring(0, 8))")
git -C $Repo switch -q codex/m30-r4r3-prune
git -C $Repo branch -D perf-tmp-a 2>$null | Out-Null
Write-Output 'PAIR6_COMPLETED'
