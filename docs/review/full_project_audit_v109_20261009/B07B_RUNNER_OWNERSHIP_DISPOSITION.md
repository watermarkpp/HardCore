# B07B runner ownership disposition

Baseline source: `b09ac5c2c41517ed516f11b91d09e435813465f2`; current integration head reference: `215f0b2`.

## Scope

Windows process ownership and physical output/user-data path boundaries only. Godot/native/Android execution is **NOT_RUN**. Linux behavior was not exercised.

## Implementation

- Windows launches `cmd.exe` suspended through `CreateProcessW` with `CREATE_SUSPENDED | CREATE_NO_WINDOW`.
- A new Job Object is created before process launch, configured with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, assigned while the root remains suspended, then resumed.
- Cleanup terminates only the invocation-owned Job Object. The previous executable-directory and baseline-PID discovery path is removed from Windows ownership decisions.
- Job accounting is used to retain detached children after the wrapper exits.
- `Assert-WindowsOwnedPath` validates workspace containment and rejects reparse points in workspace-to-root and root-to-target traversal before directory creation, APPDATA assignment or artifact cleanup.

## Controlled evidence

Command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/runner_windows_ownership_20261010_test.ps1`
Exit: `0`
Receipt: `outputs/wake_drop_v108_review_followup_20261009/b07b_runner_ownership/runner_windows_ownership_test.json`
Receipt SHA256: `34bebe66eb104a93d5d600c7aef354f94be914ec655c51ad4ac47e2704300434`

| Case | Result |
|---|---|
| `same_executable_foreign_peer` | `PASS`  |
| `owned_termination_foreign_survives` | `PASS`  |
| `wrapper_early_exit_child_retained` | `PASS`  |
| `owned_job_kill_on_timeout` | `PASS`  |
| `create_process_failure_closes_handles` | `PASS`  |
| `path_escape_rejected` | `PASS`  |
| `junction_escape_rejected` | `PASS`  |

## Boundaries

- **No Windows PID reuse was forced in this run; the Job Object boundary removes PID/path ownership inference but PID-reuse behavior remains NOT_RUN.**
- **The invalid CreateProcess case passed and exercised startup failure cleanup; AssignProcessToJobObject failure injection was not run.**
- **No Godot process was launched.**
- **Linux branch was not executed.**

No production Godot result is claimed from this helper receipt. The controlled ownership result is separate from native runner acceptance.
