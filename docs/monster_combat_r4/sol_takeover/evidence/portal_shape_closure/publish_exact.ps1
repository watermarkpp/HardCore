$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../../'))
$godotPath = Join-Path $repoRoot 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
$logRoot = Join-Path $PSScriptRoot 'publication_remaining'
if (Test-Path -LiteralPath $logRoot) { throw 'Do not overwrite native publication evidence' }
New-Item -ItemType Directory -Path $logRoot | Out-Null
$runtimeData = Join-Path $repoRoot '.godot/runtime_appdata'
[Environment]::SetEnvironmentVariable('APPDATA', $runtimeData, 'Process')
$sourceHead = (& git -C $repoRoot rev-parse HEAD).Trim()
$sourceDiff = (& git -C $repoRoot diff -- tools/map_editor/publish_single_formal_map_release.gd map_editor_workspace/chiyue_valley_secret_passage_a/chiyue_valley_secret_passage_a.editor.json map_editor_workspace/chiyue_valley_secret_passage_b/chiyue_valley_secret_passage_b.editor.json | Out-String)
$sourceDiff | Set-Content -LiteralPath (Join-Path $logRoot 'source_delta.patch') -Encoding utf8
$rows = @()
foreach ($mapKey in @('chiyue_valley_secret_passage_a','chiyue_valley_secret_passage_b')) {
    if (@(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Count -ne 0) { throw 'An engine is active; publication must remain serial' }
    $stdoutPath = Join-Path $logRoot "$mapKey.stdout.log"
    $stderrPath = Join-Path $logRoot "$mapKey.stderr.log"
    $engineLog = Join-Path $logRoot "$mapKey.godot.log"
    $command = '""' + $godotPath + '" --headless --log-file "' + $engineLog + '" --path . "tools/map_editor/publish_single_formal_map_release.tscn" -- --map=' + $mapKey + ' > "' + $stdoutPath + '" 2> "' + $stderrPath + '""'
    $started = Get-Date
    $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $command) -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
    $deadline = $started.AddSeconds(60)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100; $process.Refresh() }
    $timedOut = -not $process.HasExited
    if ($timedOut) { Stop-Process -Id $process.Id -Force; throw "Native publisher timeout: $mapKey (raw logs preserved)" }
    $process.WaitForExit()
    $code = $process.ExitCode
    $outText = Get-Content -LiteralPath $stdoutPath -Raw
    $errText = [string](Get-Content -LiteralPath $stderrPath -Raw)
    $marker = $outText.Contains("PUBLISH_SINGLE_FORMAL_MAP_RELEASE_PASS map=$mapKey ")
    $engineRemaining = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Count
    $ok = $code -eq 0 -and $marker -and $errText -notmatch 'SCRIPT ERROR|PUBLISH_SINGLE_FORMAL_MAP_RELEASE_FAIL|Parse Error' -and $engineRemaining -eq 0
    $rows += [ordered]@{map=$mapKey; source_head=$sourceHead; publisher_sha256=(Get-FileHash -LiteralPath (Join-Path $repoRoot 'tools/map_editor/publish_single_formal_map_release.gd')).Hash; native_exit_code=$code; timeout=$timedOut; marker_found=$marker; engine_remaining=$engineRemaining; started_at=$started.ToString('o'); finished_at=(Get-Date -Format o); status=if($ok){'PASS'}else{'FAIL'}}
    $rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logRoot 'runs.json') -Encoding utf8
    if (-not $ok) { throw "Native publisher failed: $mapKey" }
    Write-Output "EXACT_MAP_PUBLISH_PASS $mapKey native_exit=$code"
}
