# Linux formal runner review candidate

Tested candidate: `43167c51f6ee31cc3fe08647397c0c4ff9c997a6`.
Base: `9f2ffc25b62ad27914b1ee5cae9bbba0229fdd99`.
Raw source-set SHA256:
`d758bb3a1a3b2fc764a817fc19e587f5859c7f0bfd41a419b0aeba368f3d411e`.

Scope is Pro C0: the existing formal runner now launches Linux native Godot while
retaining authoritative receipt, native exit, log, source and producer/cold gates.
C1 also records the user's current world/DOT contract in documentation. Gameplay
implementation C2–C6, Pro independent audit and APK acceptance are still open.

## Actual validation

- Eleven Python self-test methods: PASS,149.539seconds. These include expected
  native failures; they do not mean sixteen gameplay scenes all passed.
- Thirteen native formal self-test attempts, one pre-launch symlink rejection and
  one independent peer engine. Source mutation is deliberately rejected and its
  exact original marker bytes are restored by the test. All attempts begin from
  this candidate/source fingerprint.
- Real journal backup seed→cold→restart: three native processes, PASS, same
  invocation and successful producer associations. They exercise the sole real
  writer and two/130 committed transaction cases, not mocked persistence.
- Suite registration: PASS. Source/branch/commit and engine/shell/launcher remain
  unchanged during successful runs. Windows native validation: NOT_RUN.

Engine: official Linux Godot `4.7.stable.official.5b4e0cb0f`, binary SHA256
`f85bbc6b15e22416c7d797cd60b63286dd67b9cb13498847056c18520ae55a75`.
PowerShell7.5.4 and the actual util-linux setsid binary are fingerprinted in each
before/after record. The engine's own PID must match its full receipt.

Commands, with `/workspace/.hardcore-cloud/activate.sh` sourced:

```bash
python3 -m unittest tools.test_cloud_validation -v
python3 tools/source176_r3_validation.py linux_final_journal_pair --tests tests/framework/item_journal_v2_backup_seed_test.tscn tests/framework/item_journal_v2_backup_cold_test.tscn tests/framework/item_journal_v2_backup_restart_test.tscn --timeout 30
"$HARDCORE_PWSH" -NoProfile -File tools/tests/test_suite_registration.ps1
```

Full native arguments, request JSON, run/invocation/PID, consulted receipts,
producer handoffs, source file hashes and all three logs are in NATIVE_EVIDENCE.zip.
EVIDENCE_MANIFEST.json gives every member's size/raw SHA256 and archive checksum;
all325 members were read back and verified. VALIDATION_SUMMARY.json maps
each current attempt without treating expected FAIL as application acceptance.
Inherited unowned source176 traces, real saves and signing material are excluded.

## Review findings and verified corrections

Internal read-only review is not Pro audit. It identified:

1. Lexical userdata prefixes accepted a symlink leading outside the checkout.
   The actual old runner returned PASS and wrote into a test-owned external
   temporary directory. New admission rejects symlink ancestry before creation
   or native launch; receipt validation checks physical ancestry as well.
2. An engine parent could exit zero while a detached child retained stdout/stderr.
   The original30-second invocation took47.677seconds. Linux now uses a private
   session/group and a subreaper to retain ownership of Godot-detached children.
   It never claims ownership by shared engine filename. Stream draining is bounded.
3. Killing an adopted shell can adopt its child afterward. The actual shell plus
   sleep counterexample initially failed before structured archive generation.
   Cleanup now rescans under one fixed2-second deadline, and cleanup/drain failure
   flags reject PASS while preserving the attempted receipt/result/logs.

Native shell+sleep and another real engine were tested together: orphaned work
was rejected, producer grants remained empty, and the other engine survived.
The final internal follow-up found no further concrete material issue. The full
fixed-SHA suite and journal pair above ran after those corrections.

## Retained failures and limits

The earlier Linux world-generation persistence pair genuinely failed23checks
with `actual world deadline survives the production import`; its cold process
correctly rejected the failed producer. Original raw evidence remains in the ZIP
under preserved_earlier_failures. JSON float precision is a hypothesis, not a
confirmed fix. This C0 candidate does not clear that application/fixture failure.

The original natural sustained six-target failure, real SceneTree immediate
failure, publisher physical replacement and Android seal remain open as recorded
in the handoff. The current DOT contract is documented, not implemented by this
runner change. No first/second-tree work or obsolete first-tree tests were added.

Pro fixed-SHA independent audit: NOT_RUN. The original Pro planning answer was
read; current tools have no sending entry. Fresh cloud Chromium and HTTPS access
to its original conversation both encounter proxy tunnel denial. The chatgpt.com
allowlist draft is saved but is not activated/published by that save. Dots
assistance was withdrawn. See PRO_AUDIT_REQUEST.md for a concrete consultation.

Android export/APK/signature/versionCode: NOT_RUN or MISSING as applicable.
DEVICE TEST: NOT_RUN. Preserve com.personal.mafaoffline, HardCore, original
signature and saves; preset82 is not evidence of the delivered v97 versionCode.
