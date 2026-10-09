# B06 Runtime Release Transaction Local Review

Root finalization: this worker review records an intermediate static stage. Final source hashes, corrections, native evidence and reuse boundaries are in [B06_FINAL_DISPOSITION.md](B06_FINAL_DISPOSITION.md) and [B06_NATIVE_VERIFICATION_LEDGER.json](B06_NATIVE_VERIFICATION_LEDGER.json).

## Review boundary and source binding

This began as a read-only B06-001 review. The authorized service and framework fixture implementation delta below was then applied; no registry, map, engine, or Godot/native run was performed. The requested external B06 finding artifact is not present in this worktree (`docs/review/full_project_audit_v109_20261009/external/B06/FINDINGS.json` is MISSING), so the provisional transaction concern was checked against the actual source and existing tests rather than treated as an external result.

The inspected current bytes are bound as follows; the service preimage is preserved at `outputs/release_v108_20261009/B06_runtime_release_recovery/preimage/map_editor_build_runtime_service.gd` with SHA256 `6A87066A8DD10C123C2F6B2A1849D9BB35EA479FCBA63D03BC7BC7EB226A899E`.

| File | Responsibility | SHA256 |
|---|---|---|
| `scripts/map_editor/map_editor_build_runtime_service.gd` | candidate validation, formal runtime promotion, registry commit, rollback | `97662E8D89FA41DC41101BC40E0B302763BA978D3DE52A1298669583EACF6ACD` |
| `scripts/layers/runtime/map_editor_runtime_bridge.gd` | release registry load, readiness and approved-hash admission | `6322AAF98410F7578FCD7DD59B33C20FF34CC17A77463EDC20A4115B31784EF5` |
| `scripts/map_editor/map_editor_app.gd` | editor publish caller | current worktree bytes reviewed; not changed in this task |
| `tests/map_registry_fail_closed_transaction_test.gd` | returned-error rollback and registry preservation | `A66D9CCE28E1D6B14E2E3C870F406C418EA1C4F467203CFCA50F065AE4BC72F3` |
| `tests/map_registry_restore_entry_test.gd` | registry `.bak`/`.restore_bak` restart cases | `E07DA2604EBF55197F716C15C7064EA86B029FE165ABCD30440BC18D19ABE66D` |
| `tests/map_registry_restore_source_preserved_test.gd` | source-backup preservation during restore | `CAE59CE1A0A48D6080103CCDFC6D02965E6E6690659D42E7C4C7D0B0C652EA26` |
| `tests/build_candidate_does_not_mutate_release_test.gd` | candidate isolation and restart/readiness checks | `45CDF88A4904CFB69455B34BBE4E7A0FC419617534C0B419502D4562E84B74E9` |

The worktree is dirty with unrelated B01-B05 and release changes. These hashes describe the bytes actually read, not a claim that the whole worktree is clean or that the fixed external B06 baseline is available locally.

## Actual publish and load topology

The editor entry point is `scripts/map_editor/map_editor_app.gd:_on_publish_runtime_pressed()` around lines 2288-2353. It validates the document identity and the last candidate, then calls `MapEditorBuildRuntimeService.publish_runtime_release()` with the candidate path, runtime map ID, current document binding, default registry path, and map key. The editor only clears its candidate after the publisher returns success; render-plan publication happens afterward and is a separate post-publish operation.

The publisher validates the candidate, spawn identities, document binding, UI projection, and the complete prospective registry before touching either published artifact (`scripts/map_editor/map_editor_build_runtime_service.gd:117-253`). The commit order is:

1. `_promote_runtime(candidate_runtime_path, formal_path)` at lines 254-262.
2. `_write_registry_atomic()` or `_write_registry_atomic_preserving_existing_entries()` at lines 263-276.
3. Cache invalidation and formal-playability/hash verification at lines 285-294.
4. On a returned registry or post-verification failure, `_restore_runtime()` and, for post-verification failure, `_restore_registry_bytes()` at lines 276-313.

`_promote_runtime()` writes and validates `formal_path.publish_tmp`, renames the old formal file to `formal_path.bak`, then renames the temporary candidate into the formal path (`:355-434`). `_write_registry_atomic()` similarly writes and parses `registry.tmp`, renames the old registry to `registry.bak`, promotes the temp file, then removes the backup (`:852-904`). The single-map-preserving writer uses `.restore_bak` through `_write_registry_text_atomic()` (`:907-939`, `:1007-1052`). These are individually checked replacements; there is no journal or commit marker linking the runtime rename to the registry rename.

The runtime consumer is fail-closed. `MapEditorRuntimeBridge._load_release_registry()` (`scripts/layers/runtime/map_editor_runtime_bridge.gd:73-114`) rejects a missing, unparsable, or schema-invalid registry before exposing entries. `_compute_readiness()` (`:213-246`) requires an implemented-playable entry, an existing/loadable runtime file, equality between `approved_build_sha256` and the loaded runtime `build_sha256` (`:238-241`), and a matching source map key. `has_runtime_map()` and `is_formal_playable()` delegate to that readiness result (`:255-301`). Thus a mismatched pair is rejected as intended, but the source does not provide a durable pair-recovery decision after an ungraceful exit.

## Findings

### B06-001 — source-proven crash window between the two published artifacts

**Status: CONFIRMED SOURCE RISK; PRODUCTION FAILURE: NOT_OBSERVED.**

After `_promote_runtime()` returns at `map_editor_build_runtime_service.gd:418-434`, the new formal runtime is already visible while the registry still contains the old approved hash. A process termination, power loss, or host kill in this interval leaves a possible state of:

- new formal runtime bytes;
- old main registry bytes (or an intermediate registry backup/temp depending on where termination occurs);
- a `.bak` containing the old formal runtime; and
- no durable transaction identity telling the next process whether to complete the registry commit or roll the runtime back.

The next loader follows the old registry, compares its approved hash with the new runtime hash, and fails closed at `map_editor_runtime_bridge.gd:238-241`. That is safe admission behavior, but it is an availability failure until a later publish or manual recovery. The currently inspected source and retained reports do not prove that this crash has occurred in production, so this must not be reported as an observed data-loss incident.

The recovery logic closes only narrower cases. `_read_registry()` (`map_editor_build_runtime_service.gd:471-591`) can reconstruct a **missing** registry from a valid `.bak` or `.restore_bak`, with conflict checks. When the old registry main file is still present and valid, it does not inspect a companion backup or compare the registry entry with a runtime `.bak`; it simply reads the main registry. Therefore the exact state “runtime promoted, registry commit not begun” has no pair-aware recovery path. The existing per-call rollback at `:276-313` cannot run after process termination.

There is also a retry hazard in `_promote_runtime()` (`:386-412`): if both a stale `.bak` and a formal file exist, the code deletes the backup before moving the current formal file to `.bak`. This is safe for a clean completed publish where the backup is intentionally stale, but after the crash state above it can discard the only old formal copy before a retry has proven which registry version is authoritative. This is a source-level recovery risk, not evidence of an observed production overwrite.

### B06-002 — existing tests cover returned failures and registry-only recovery, not process-crash pair recovery

**Status: PARTIAL COVERAGE; IMPLEMENTATION PRESENT, CONTRACT EXECUTION NOT_RUN.**

The existing contracts provide useful but narrower evidence:

- `tests/map_registry_fail_closed_transaction_test.gd:113-157` publishes A, injects `test_fail_post_publish_verify`, and proves exact registry/runtime rollback for a normal returned failure.
- `tests/map_registry_restore_entry_test.gd:83-109` exercises a missing-main-registry restart with `.restore_bak`; `:134-212` covers identical and conflicting registry backups; `:236-274` keeps corrupt/no-backup cases fail-closed; `:281-303` covers registry commit failure and runtime restoration; `:305-337` preserves unrelated registry bytes during a single-map splice.
- `tests/map_registry_restore_source_preserved_test.gd:42-68` proves a registry backup source remains available through restore success/failure.
- `tests/build_candidate_does_not_mutate_release_test.gd:34-79` proves a failed candidate does not mutate the published A pair and that a restart can still read A.
- `tests/map_runtime_release_registry_contract_test.gd` and `tests/release_registry_consumer_validation_test.gd` cover schema, duplicate identity, missing hash, and fail-closed consumer admission.

The injected booleans (`test_fail_runtime_promote`, `test_fail_registry_commit`, and `test_fail_post_publish_verify`) fail inside the same process and allow the caller's rollback code to run. They do not terminate between the runtime rename at `:418` and the registry rename/promote at `:897`, and they do not exercise a subsequent process reopening the exact mixed pair. No current test proves preservation of a newer manual runtime/registry artifact in that state.

## Initial minimal durable repair proposal (superseded by the implementation delta below)

The smallest safe repair is a transaction record owned by `MapEditorBuildRuntimeService`, adjacent to the exact formal runtime and exact release registry. It must be pair-scoped by `runtime_map_id`, `map_key`, canonical runtime path, registry path, candidate hash, old runtime hash, old registry hash, prior approval revision, and a unique transaction ID. It should record phases such as `prepared`, `runtime_promoted`, `registry_promoted`, `verified`, and `aborted`. The record is metadata for recovery; it must not become a second runtime or registry authority.

A publish should write and validate candidate/registry temporaries, then persist the prepared record before the first rename. After each rename it should advance the phase and flush the record. On startup or before the next publish/read admission, recovery should inspect only the exact paths named by the record:

1. If the record says `runtime_promoted`, the runtime hash equals the recorded candidate hash, the registry still equals the recorded old registry hash, and the staged/new registry validates and names that same candidate, complete the registry promotion. Otherwise do not guess.
2. If the record says `runtime_promoted` but the registry is still old and the formal file is neither the recorded candidate nor the recorded old runtime, preserve every artifact and fail closed.
3. If the registry is new but the runtime is old, complete runtime promotion only when the record, candidate hash, map key, approval revision, and exact target path all match. Otherwise preserve and fail closed.
4. If both sides are ambiguous, or a manual edit changed any file after the record was written, preserve the newer/manual bytes and retain the transaction evidence. Do not select by mtime, filename, or “latest” backup.
5. Once both sides validate and the loader observes the exact approved hash, mark the record verified and remove only transaction-owned temporary/backup files. Unrelated registry entries must remain byte-identical.

The recovery must never overwrite a newer manually saved runtime or registry. A safe implementation should compare the current bytes/hashes against the journal's expected old/new hashes before any destructive rename. If neither expected hash matches, recovery is `FAIL_CLOSED` with the journal and all conflicting artifacts retained. This is preferable to silently restoring an older `.bak` and losing a newer authoring result.

A process-crash seam can be introduced only for tests, not as a production kill switch: stop after the actual runtime rename, stop after the registry main-to-backup rename, and stop after registry temp promotion. The test then creates a fresh service/bridge process state and invokes the real recovery/read-admission entry. The seam must not replace real filesystem rename semantics or bypass the formal validator.

This proposal is intentionally exact-target. It does not scan or rewrite all maps, merge registries, change the runtime schema, alter editor save ownership, or make the loader accept a hash mismatch. Registry backup conflict selection (`_select_registry_backup_by_approval_evidence()` around `:594-701`) remains useful for registry-only ambiguity but cannot prove a runtime/registry pair transaction.

## Required focused validation

The following cases are necessary before calling this gap closed:

| Case | Required evidence | Expected result |
|---|---|---|
| crash after runtime promotion | fresh process, old registry + candidate runtime + old runtime backup + prepared journal | either complete the exact candidate pair or restore old pair; no hash-mismatch playable state |
| crash during whole-registry commit | fresh process with registry main missing and `.bak`/`.tmp` state | recover only a validated exact transaction; preserve conflicting backups |
| crash during single-map splice | fresh process with `.restore_bak` and unrelated entries | target entry recovers, unrelated map bytes remain unchanged |
| newer manual runtime edit | runtime bytes do not match journal old/new hash | fail closed, preserve manual bytes and journal; no overwrite |
| newer manual registry edit | registry bytes do not match journal old/new hash | fail closed, preserve manual registry and all backups |
| candidate invalid/identity mismatch | malformed or wrong map/key/hash candidate | no promotion and no transaction completion |
| repeated recovery | invoke recovery twice after successful completion | idempotent; no duplicate revision and no second destructive rename |
| ordinary returned failures | existing injected registry/post-verify failures | retain current rollback behavior and exact error reasons |

The receipt for each case must bind source hashes, engine hash, exact runtime/registry paths, transaction ID, old/new artifact hashes, phase observed, fresh-process/restart boundary, native exit, and the final loader readiness/hash result. A test that merely creates `.bak` files or calls `_restore_registry_bytes()` is useful for registry mechanics but does not prove pair crash recovery.

## Disposition

- Per-file temporary/backup replacement and returned-error rollback: **PASS within current scope**.
- Registry schema and approved-hash fail-closed admission: **PASS within current scope**.
- Runtime + registry ungraceful-exit atomicity: **FAIL (source-proven window)**.
- Pair-aware recovery after a process crash: **IMPLEMENTED STATICALLY / NOT_RUN**.
- Preservation of newer manual runtime/registry data during recovery: **IMPLEMENTED STATICALLY / NOT_RUN**.
- Observed production crash or data loss: **NOT_OBSERVED**.
- Device/editor crash recovery: **NOT_RUN**.

## Authorized implementation delta (static only)

The service owner has now added an exact-target intent sidecar and recovery path in
`scripts/map_editor/map_editor_build_runtime_service.gd`. The intent records the
runtime map ID/key, canonical runtime and registry paths, old runtime file
bytes/hash plus its approved build hash, the candidate file hash and approved
build hash, the staged registry text/hash, approval revision, and a phase. It is written before runtime promotion; recovery runs at
the start of the next publish call and can only discard an unpromoted intent,
recognize an already committed exact pair, or complete the registry side when
the current runtime is the recorded candidate and the registry is still the
recorded old state. A third hash, target mismatch, malformed intent, or other
unproven state returns `publish_recovery_ambiguous_pair` and preserves artifacts.
The recovery does not change `MapEditorRuntimeBridge` readiness or accept an
unregistered runtime. Expected-hash checks guard cleanup of old `.bak` files.

The new exclusive contract fixture is
`tests/framework/map_editor_release_recovery_20261010_test.gd/.tscn`; it covers
the runtime-promoted-before-registry boundary, the registry-main-to-backup
boundary, repeat recovery, and preservation of an unrelated registry entry.
It has not been run in this review. The crash seams are test-only filesystem
boundary seams that leave the intent and files in place; they are not a claim
that a real process kill has already been simulated by the engine.

Current implementation bytes after the authorized edit:

| File | SHA256 |
|---|---|
| `scripts/map_editor/map_editor_build_runtime_service.gd` | `62D115CFF5DB3C57A31B2C19DB27C5C7ACC9E21E43E39EBEEEA73B9FC5B8DF65` |
| `tests/framework/map_editor_release_recovery_20261010_test.gd` | `FCC303780E3C6183C899F7088CC31B2731E54F7C447058CC312FB726657D0935` |
| `tests/framework/map_editor_release_recovery_20261010_test.tscn` | `C98D45051CFA319B2F1D745D72BF932D21BD65321A2ED9941B4B78F8BE833938` |

The implementation remains `NOT_RUN` until the owner freezes the exact source
and runs the dedicated contract. Native/device crash recovery is still
`NOT_RUN`; no production success or runtime-file durability claim is made.

## Legacy no-intent restart compatibility delta

The existing restart contract predates the intent sidecar and can leave a
valid approved registry entry with the formal primary missing and its old
runtime in `formal_path.bak`. `publish_runtime_release()` now invokes
`_recover_legacy_formal_backup()` immediately after a valid registry read and
before preparing a new intent. It restores only when the primary is absent,
the backup loads through `RuntimeMapService`, the runtime source map key and
strict numeric runtime ID match the registry entry, the registry path is the
canonical map path, and the runtime build hash equals the registry approved
hash. It invalidates the bridge cache after the rename.

A primary-plus-backup state, a noncanonical path, a wrong approved hash, a
wrong source identity, an invalid backup, or a registry entry mismatch fails
closed and preserves both artifacts. This compatibility path is intentionally
separate from intent recovery and never replaces an existing primary. The
framework fixture adds these checks while the original restart fixture remains
unchanged. Execution remains `NOT_RUN`.

Registry-only restart compatibility is also preserved. `_read_registry()` now consumes only the selected `.bak` or `.restore_bak` after `_restore_registry_bytes()` has verified that the restored primary bytes equal the selected backup bytes and the selected backup still has the original hash. Unselected backups, unknown files, and unresolved conflicts remain untouched; the registry writer has no unconditional backup deletion path.
