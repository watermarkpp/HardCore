# B06 ground transaction local review

Root finalization: this worker review records an intermediate static stage. Final source hashes, corrections, native evidence and reuse boundaries are in [B06_FINAL_DISPOSITION.md](B06_FINAL_DISPOSITION.md) and [B06_NATIVE_VERIFICATION_LEDGER.json](B06_NATIVE_VERIFICATION_LEDGER.json).

## Scope and source binding

This is the B06-001 implementation against the published baseline `d145826b7305ad918893ba0098db2595ae01f53a`. The GroundService transaction source now has SHA256 `7631AE6A0BF757E71F34F26B88447F7F49ACC3F1BEAAD34AFB0061A6360E583A`; no other production file was changed and no Godot/native run was performed.

## Confirmed ownership and write order

`scripts/map_editor/map_editor_ground_service.gd` is the active authoring owner for the three ground artifacts:

- `initialize()` at lines 10-43 reads `ground_manifest.json` and `ground_state.json`, applies coordinate and blank-policy migration, and independently writes manifest first (lines 35-38) and state second (lines 39-42).
- `_record_operation()` at lines 166-214 and `_record_tile_batch()` at lines 65-114 mutate the in-memory manifest/state, write each changed `ground/chunks/<chunk>.json` first (lines 107-109 and 207-210), then call `save_manifest_and_state()`.
- `save_manifest_and_state()` at lines 159-164 writes the manifest and then the state as two independent atomic replacements.
- `_write_json_atomic()` at lines 411-443 verifies a temporary JSON file, renames the current file to `.bak`, promotes `.tmp` to the target, and deletes `.bak` after promotion. This is atomic replacement per file, not a multi-file commit.

The editor consumer is `scripts/map_editor/map_editor_app.gd`: `_adopt_new_document()` (around lines 1201-1207) and `_open_document_path()` (around lines 1313-1329) call GroundService initialization before displaying the loaded state. `_save_current_document()` (around lines 1300-1320) initializes/coordinates the ground artifacts first, then writes the editor document through `MapEditorSaveService.save_document()`. Ground paint commands at `_on_ground_paint_requested()` (around lines 1738-1743) write chunk/manifest/state during command execution, while the editor document save is a separate later action.

The bake owner is `scripts/map_editor/map_editor_chunk_bake_service.gd`: `bake_dirty_chunks()` writes each preview PNG, writes the preview manifest, then calls `save_manifest_and_state()` (lines 6-68). Runtime validation and binding read the same artifacts through `scripts/map_editor/map_editor_build_runtime_service.gd` (`validate_for_runtime()` around lines 1064-1072 and `document_binding()` around lines 1120-1140). `scripts/layers/runtime/map_editor_runtime_bridge.gd` consumes the published manifest path; it is not an authoring transaction owner.

## Failure and recovery findings

Per-file promotion has a useful rollback on a failed rename: if target promotion fails, the `.bak` is renamed back (GroundService lines 429-440). Temporary JSON is removed when temporary parsing fails. That closes a single-file replacement failure.

The implementation now gives the JSON write set an explicit generation journal at `ground/.ground_write_set.json`. Changed chunks plus manifest/state are staged and JSON-verified before the journal is written; recovery runs at the start of `initialize()` and promotes only entries whose current bytes are the proven base or intended new hash. Every journal entry is checked before any promotion: map identity, generation token, allowed relative target (`ground_manifest.json`, `ground_state.json`, or one-level `chunks/*.json`), duplicate target, exact generation-derived temp/backup names, and explicit base/new hashes (`MISSING` is the only allowed absent-base marker). A third version, corrupt journal identity, path traversal, arbitrary temp/backup, missing intended staging, or incomplete pair returns an explicit error and leaves newer manual bytes untouched. Existing per-file `.bak` behavior remains outside this journal; no blind `.bak` or `.tmp` fallback is used. Bake preview PNG/preview manifest remain the existing separate bake owner and are intentionally outside this narrow JSON transaction.

`_read_json_checked()` now distinguishes missing from unreadable/malformed JSON. `initialize()` allows a blank workspace only when both primaries are absent and no other ground artifacts exist; an existing corrupt or incomplete primary pair returns an explicit error rather than reinitializing. The current editor document loader still does not repair ground artifacts because `MapEditorLoadService.load_document()` only loads the editor JSON.

The existing `MapEditorSaveService` transaction/recovery machinery is authoritative for editor-document delete/restore operations, but it does not own GroundService's manifest/state/chunk set. Reusing its document `.bak` behavior alone would not close this B06 gap and must not overwrite a newer manual ground workspace with an older backup.

## Implemented repair seam

GroundService is the sole transaction owner and uses a journal/commit record under the existing ground workspace, without changing the document schema. A ground mutation now:

1. writes and JSON-verifies complete changed chunk, manifest, and state payloads;
2. records base/new SHA256 values and staged paths in one generation journal;
3. promotes each staged file only after all entries are proven; and
4. on open, resumes only base-to-intended transitions and removes the journal after every target is intended.

The journal compares map identity and every target's base/new bytes before replacing current files. An incomplete generation is left diagnosable, never promoted over a newer valid manual generation. Existing per-file `.bak` rollback remains the final replace primitive. This keeps the authoring document schema and runtime binding unchanged while giving GroundService one recovery authority.

An even smaller compatible variant can use a manifest/state generation and a commit marker, but it must include changed chunk and bake-preview membership in the same generation proof; merely writing a second `transaction.json` after the current two-file sequence would not make the sequence recoverable.

## Focused validation seam

`tests/framework/map_editor_ground_transaction_20261010_test.gd/.tscn` exercises the real GroundService in a user workspace: a real batch mutation, partial manifest promotion, repeated recovery, missing primary with a valid intent backup, explicit third-version blocking, path traversal, arbitrary absolute temp, changed-backup, wrong `entries` shape, duplicate-target rejection, and preservation of newer manual bytes. Its hand-built intent uses the same absolute temp/backup paths emitted in production. It does not claim power-loss durability and does not cover preview PNG joint recovery.

Current static status: JSON manifest/state/chunk write-set implementation `PASS` pending root's frozen-source run; third-version/newer-manual guard `PASS` static; preview joint recovery `NOT_RUN`; focused Godot regression `NOT_RUN`; device/editor crash recovery `NOT_RUN`.
