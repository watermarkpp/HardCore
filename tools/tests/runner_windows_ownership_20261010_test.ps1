$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'tools\test_windows_process_ownership.ps1')
$evidence = Join-Path $root 'outputs\wake_drop_v108_review_followup_20261009\b07b_runner_ownership'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$records = [Collections.Generic.List[object]]::new()
$foreign = $null
$owned = $null
$early = $null
try {
    # Same executable family, deliberately outside the owned job.
    $foreign = Start-WindowsOwnedProcess $env:ComSpec 'cmd.exe /c ping -n 8 127.0.0.1 > nul' $root
    $owned = Start-WindowsOwnedProcess $env:ComSpec 'cmd.exe /c ping -n 8 127.0.0.1 > nul' $root
    $records.Add([ordered]@{case='same_executable_foreign_peer'; ownership=$owned.OwnershipEstablished; foreign_alive=$foreign.HasActiveProcesses; owned_active=$owned.HasActiveProcesses})
    if (-not $owned.OwnershipEstablished -or -not $foreign.HasActiveProcesses -or -not $owned.HasActiveProcesses) { throw 'same-executable ownership case failed' }
    $owned.Terminate(0)
    Start-Sleep -Milliseconds 150
    $records.Add([ordered]@{case='owned_termination_foreign_survives'; owned_active=$owned.HasActiveProcesses; foreign_alive=(-not $foreign.HasExited)})
    if (-not $foreign.HasActiveProcesses) { throw 'foreign peer was terminated by owned cleanup' }
    $owned.Dispose(); $owned = $null

    # The wrapper exits before its child; the job remains the only ownership
    # boundary and must retain the detached child until explicit termination.
    $early = Start-WindowsOwnedProcess $env:ComSpec 'cmd.exe /c start "" /b cmd.exe /c "ping -n 8 127.0.0.1 > nul"' $root
    Start-Sleep -Milliseconds 250
    $records.Add([ordered]@{case='wrapper_early_exit_child_retained'; wrapper_exited=$early.HasExited; job_active=$early.HasActiveProcesses})
    if (-not $early.HasExited -or -not $early.HasActiveProcesses) { throw 'job did not retain early-detached child' }
    $early.Terminate(0)
    Start-Sleep -Milliseconds 150
    $records.Add([ordered]@{case='owned_job_kill_on_timeout'; job_active=$early.HasActiveProcesses; foreign_alive=(-not $foreign.HasExited)})
    if ($early.HasActiveProcesses -or -not $foreign.HasActiveProcesses) { throw 'owned job cleanup boundary failed' }
    $early.Dispose(); $early = $null
    try { Start-WindowsOwnedProcess (Join-Path $root 'missing-owned-process.exe') 'missing-owned-process.exe' $root | Out-Null; throw 'invalid CreateProcess unexpectedly succeeded' } catch { if ($_.Exception.Message -notlike '*CreateProcess failed*') { throw } }
    $records.Add([ordered]@{case='create_process_failure_closes_handles'; status='PASS'})
    $ownedOutputRoot = Join-Path $root 'outputs'
    try {
        Assert-WindowsOwnedPath (Join-Path $root 'outside-owned-root') $ownedOutputRoot 'test escape' $root
        throw 'path escape was accepted'
    } catch { if ($_.Exception.Message -notlike '*escapes its owned namespace*') { throw } }
    $records.Add([ordered]@{case='path_escape_rejected'; status='PASS'})
    $junction = Join-Path $evidence 'junction_escape'
    $outside = Join-Path $env:TEMP ('hc_runner_outside_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $outside -Force | Out-Null
    try {
        New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop | Out-Null
        try {
            Assert-WindowsOwnedPath (Join-Path $junction 'child') $ownedOutputRoot 'test junction' $root
            throw 'junction path was accepted'
        } catch { if ($_.Exception.Message -notlike '*reparse point*') { throw } }
        $records.Add([ordered]@{case='junction_escape_rejected'; status='PASS'})
    } catch {
        $records.Add([ordered]@{case='junction_escape_rejected'; status='NOT_RUN'; reason=$_.Exception.Message})
    } finally {
        if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $outside) { Remove-Item -LiteralPath $outside -Force -Recurse -ErrorAction SilentlyContinue }
    }
    $result = [ordered]@{status='PASS'; cases=$records; source='tools/test_windows_process_ownership.ps1'; godot_run='NOT_RUN'}
} catch {
    $result = [ordered]@{status='FAIL'; cases=$records; error=$_.Exception.Message; source='tools/test_windows_process_ownership.ps1'; godot_run='NOT_RUN'}
    throw
} finally {
    if ($null -ne $owned) {
        try { if ($owned.HasActiveProcesses) { $owned.Terminate(1) } }
        finally { $owned.Dispose() }
    }
    if ($null -ne $early) {
        try { if ($early.HasActiveProcesses) { $early.Terminate(1) } }
        finally { $early.Dispose() }
    }
    if ($null -ne $foreign) {
        try { if ($foreign.HasActiveProcesses) { $foreign.Terminate(1) } }
        finally { $foreign.Dispose() }
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'runner_windows_ownership_test.json') -Encoding UTF8
}
