# B07 local build and runner review

## Scope and source binding

This is a static review of the current working-tree helpers. No Android build,
Godot run, APK installation, or device test was performed. The repository has
no `tools/build_android.ps1`; the production entry documented by
`docs/ANDROID_BUILD_ENVIRONMENT.md` is `tools/build_android_isolated.ps1`.

Reviewed source SHA256:

| Path | SHA256 |
|---|---|
| `tools/build_android_isolated.ps1` | `2AEBD1F5C4ADDBCE811C8836B1E3E7A174976A55792668131CFBAC316A8A4448` |
| `tools/verify_android_build.ps1` | static source reviewed; hash was not required by this narrow runner slice |
| `tools/android_seal/bridge/android_two_pass_export_hook.ps1` | static source reviewed; hash was not required by this narrow runner slice |
| `tools/android_java_environment.ps1` | `55207F47B2794395550867DE18C423C58C56435D139F536BDDBB92160A8D6837` |
| `tools/run_godot_tests.ps1` | `7942F83AF625A03BD44A3891F627136E2D3299404C44E5E8BF8ED798FEE0906B` |
| `tools/test_framework_receipt.ps1` | `7BD3BD68E97B358F5102B8B95133960EC623A15B4F2D3BE768D20FDAE49B7C21` |
| `tests/framework/helpers/check_receipt.gd` | `EA0D6CEE9986EC8E379DB005CFE70BA21E9130DD5A0D536B4D027AF4C17EA59F` |

## Confirmed controls

`build_android_isolated.ps1` resolves the requested commit and reads its
version/configuration from Git before staging (lines 219-245). A supplied
stage must be a separate worktree at that exact commit, clean, and free of a
`.godot` import cache. It validates the configured engine, baseline APK and
Android root before staging (lines 18-47), then performs raw-byte identity
registry checks before import/export (lines 404-430). Java/Android paths are
entered through `android_java_environment.ps1` and evidence is written under
the stage (lines 357-363).

The two-pass export hook binds source catalogue/plan/producer, template and
APK hashes, rejects changed generated metadata, and compares first/final
signer certificates. `verify_android_build.ps1` compares candidate and
baseline signer certificate digests, package name, and requires a higher
version code for direct update. These are source and package identity gates;
they do not establish installation or device execution.

`run_godot_tests.ps1` uses a per-worktree mutex and per-run APPDATA/runtime
directory, validates adhoc test paths remain under `tests/` and are Git
tracked, and uses the explicit `-TimeoutSeconds` value. It monitors stdout,
stderr, engine log and child processes. A PASS marker alone is insufficient:
the process must naturally exit, have an effective exit code of zero, no
unallowlisted errors, and no timeout/orphaned child. Framework receipts are
then checked for exact run ID, scene ID, source content hash, schema, ordered
checks, counts and `PASS` status. Evidence is archived by run ID before later
attempts can overwrite the common receipt path.

## Boundary findings

The local controls are adequate for source/runtime identity at their stated
boundaries. The meaningful remaining gaps are acceptance gaps rather than a
fresh confirmed defect:

1. The Android helper verifies an APK and signing identity but does not install
   it or prove a real device launch, input, rendering, save compatibility, or
   sustained frame timing. Those must remain `DEVICE TEST: NOT_RUN` until a
   device run supplies evidence.
2. `check_receipt.gd` creates a valid receipt only when the process environment
   supplies the runner run ID and all recorded checks pass. The PowerShell
   runner is the authority for native exit, stderr and runtime-directory
   checks; a child receipt copied by hand is not sufficient.
3. The runner permits known allowlisted headless teardown messages (for
   example normal delayed resource-release lines), so a future new teardown
   error must be classified against the allowlist rather than silently
   ignored. This is a review boundary, not evidence of a current failure.
4. The current B05 fixture now defers receipt writing until after its owned
   Root is queued for deletion; its native result remains `NOT_RUN` here.

No new production defect was confirmed in this narrow B07 source review.
