# Cloud native validation implementation plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan in the existing cloud continuation branch. Steps use checkboxes for durable tracking.

**Goal:** Run the existing formal source/receipt/native-producer validation on Linux without bypassing its gates.

**Architecture:** Retain `run_godot_tests.ps1` as the single suite, timeout and verdict owner. Add a Linux native-process transport and a structured request entry point; extend the existing source fingerprint driver to select the real platform engine and shell. Production gameplay remains governed by the handoff and latest user decisions.

**Tech Stack:** Python 3.12, PowerShell 7.5, Godot 4.7 stable Linux (`5b4e0cb0f`).

**Spec:** `docs/handoffs/cloud_20261005/README.md`; original RFC `docs/architecture/pluggable_framework/RFC_V2_USER_SOURCE_20260930.md`; original Pro planning response saved with provenance in `outputs/cloud_continuation_20261005/pro/PLANNING_TRANSCRIPT.md`.

## Global constraints

- Third-tree starting SHA: `4685d5ec76227509d53d4ff542f9d60cb4b8b626`. No first/second-tree merges or old first-tree tests.
- Native exit, full receipt, exact source/run/invocation, successful producer and cold association remain mandatory.
- Ordinary process windows remain 30s; known heavy scenes retain 60s; only the existing explicitly authorized live diagnostics may use 90s, with their cold scenes at 30s. Business deadlines and workloads remain unchanged.
- Preserve existing raw source, historical FAIL, save data and signing credentials. Never normalize reviewed source for a cosmetic diff check.
- Push fixed candidates for original Pro GitHub review; a push alone is not an audit result. The user has withdrawn dots assistance and requested direct Pro contact. Current tools can read the original Pro conversation but cannot send to it; the fresh cloud browser also encounters a network proxy denial. Record actual delivery and reply separately from candidate publication.

## Review focus

- PASS text followed by nonzero exit or a live process at deadline must fail.
- False/zero-check/missing receipts and wrong invocation must fail even with native exit zero.
- A failed live attempt cannot inherit a prior producer, including a repeated scene in one invocation.
- Linux userdata must be confined to the invocation-owned project test directory, not real saves.
- Shared Linux engine installation must not authorize killing another checkout's processes.

### Task 1: Platform-native runner and immutable evidence

**Files:**
- Modify: `tools/run_godot_tests.ps1`, `tools/source176_r3_validation.py`
- Create: `tools/run_godot_tests_request.ps1`
- Test: `tools/test_cloud_validation.py`; existing `tests/framework/fixtures/proof_*` and cold receipt gate scenes

**Interfaces:**
- Consumes: existing `Test-FrameworkReceipt(Path, ExpectedRunId, ExpectedSceneId, ExpectedContentSha256)` and runner-owned native handoff JSON.
- Produces: unchanged source driver CLI (`label --tests paths... --timeout seconds`), structured request `{tests: string[], timeout: int}` or `{suite: string, timeout: int}`; archived `before.json`, `after.json`, `runner_results.json`, per-run native logs/receipts and `validation.json`.
- Linux engine/shell come from explicit `HARDCORE_GODOT`/`HARDCORE_PWSH`; platform and binary SHA are recorded. The engine must report `4.7.stable.official.5b4e0cb0f`.

- [x] Write/run a real positive-control test through the source driver; establish its failure on the missing Windows-only engine.
- [x] Use a structured PowerShell request, preserve all existing suite/path/timeout admission, select the Linux engine, launch/observe/kill only the owned native process, capture its real exit code and all three logs.
- [x] Set APPDATA and XDG_DATA_HOME to one invocation-owned `.godot/runtime_appdata` child before the native launch; verify framework receipt native PID, root and userdata ownership.
- [x] Extend source fingerprint/evidence collection to include the request adapter and actual platform engine/shell. Keep before/after stable-source checking and full producer/cold gates.
- [x] Run positive, false marker, zero checks and marker-only native fixtures. Verify negative cases fail and never create a producer grant.
- [x] Add real native transport fixtures for post-PASS nonzero, post-PASS timeout and post-PASS engine error; keep the old BOM-bearing Windows fixtures unchanged.
- [x] Run the existing cold receipt counterexample gate and one actual live/cold pair. Archive exact associations and preserve all failed attempts.
- [x] Review the diff, verify no unintended source changes, commit the concrete runner increment and push the continuation branch.

Completion evidence: candidate `43167c51f6ee31cc3fe08647397c0c4ff9c997a6`,
source `d758bb3a1a3b2fc764a817fc19e587f5859c7f0bfd41a419b0aeba368f3d411e`.
Eleven Python methods PASS149.539seconds, thirteen formal native self-test attempts
plus three actual journal live/cold/restart processes and one independent peer.
Expected negative outcomes remain FAIL; the suite verifies their rejection.
Internal review findings were reproduced, fixed and retested, including symlink
escape and detached multigeneration pipe ownership. Source commits and remote
branch were actually pushed and checked with ls-remote. Review evidence is in
`docs/review/cloud_runner_20261005`; independent Pro audit remains NOT_RUN.

## Following architecture work

This plan implements Pro stage C0 only. Continue C1–C6 against the existing `USER_SCOPE_LEDGER.md` and `FRAMEWORK_PROGRESS.md`: current product contract, complete birth closure, DOT replacement/lifecycle capacity, real resource handoffs, causally classified sustained failure, final combinations/Pro review/APK. Concrete production plans follow source mapping; this runner increment does not claim those stages complete.
