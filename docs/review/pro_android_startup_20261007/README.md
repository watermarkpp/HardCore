# Android startup / creation repair — active validation

Baseline: `707512fc2fee85e556c1be71ce32fb2e9d454ecd`.
Scope: real v101 creation failure and adjacent Android/export lifecycle defects.
This is not all-project/P6/device-performance acceptance.

## Actual cause

Original v101: 491805682 bytes, SHA256
`65042296603d24b4fa2c900c4da2c2c4771f67a6fb2e795dbea2b8cb02e497a4`.
A diagnostic in the actual Android startup sequence observed an empty healing
record before GameData, followed by correct art and successful fresh declaration
validation after GameData. The cached reader still returned the earlier origin
mismatch. The actual Hall create action returned `character_stats_rejected`.
No different healing record, asset substitution or hash relaxation is needed.

The controlled startup-order native test has 10 checks: old code fails 2 business
checks; the readiness guard passes all 10. Genuine ready-time malformed declarations
remain cached and fail closed. PlayerState no longer compiles against Android's
intentionally deferred data authority; its existing startup-upgrade completion
performs the original recalculation after GameData is ready.

## Other actual defects

- Android verifier predelete called cancel() on a zero-reference self. Android
  logs show the Script error. A native test with an independently retained real
  file fails 1 of 5 checks and logs 2 errors before direct cleanup; all 5 pass
  afterward. The initial test Variant-inference parse failure is separately kept.
- The formal build referenced a missing hook path, did not install its regenerated
  catalogue into the actual stage, and never invoked source-media injection from
  the export hook. Three wiring tests fail before repair and pass afterward;
  they are not native-export acceptance. The callback now returns the hashtable
  required by the hook instead of an incompatible OrderedDictionary.
- A diagnostic package made with Windows PowerShell corrupted Chinese ZIP member
  names during the existing source-injection step: Godot UTF-8 names can omit EFS,
  while the default .NET reader used the local code page. Strict explicit UTF-8
  preserves native paths. The actual production Open expression has a failing
  old-byte .NET roundtrip and a passing corrected roundtrip. An initial test reader
  incorrectly assumed EFS and its failed candidate attempt is retained. All 19316
  existing asset names/size/CRC remain unchanged; only the three declared source
  media members are added. This corruption was observed in our diagnostic export,
  not asserted to exist in the original desktop v101.

## Bounded observed progress

A diagnostic APK with the readiness repair created and persisted a warrior through
actual Android Hall UI. With corrected filename packaging, that same profile
entered the real home world, moved and opened inventory/equipment. That diagnostic
still contained old verifier bytecode; final corrected export requires its own
verification. It must not be distributed as a final source-attributed release.

## Evidence and protection

All original logs, RED/failed attempts, receipts, source backups, screenshots and
APK probes are under `outputs/pro_v101_debug_20261006_231847/` locally.
Early native runs had no content environment value and are not relabelled later;
subsequent runs bind FINAL_SOURCE_BEFORE.json. Diagnostic APKs retain version101
and their inherited build-info, with explicit mutation records.

No real phone data was cleared. The original emulator files archive stays private
and is not committed. First/second worktrees were not modified. The third-tree
index was backed up before registering new tests, without rewriting historical
index continuity. Bootstrap's old unknown-branch routing FAIL remains recorded;
its whitelist was not relaxed. No additional agent/controller was started.

Final native rows, final export and device-smoke result will be appended after
actual completion; this document does not replace those gates.
