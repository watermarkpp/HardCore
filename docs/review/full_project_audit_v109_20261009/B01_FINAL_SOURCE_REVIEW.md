# B01 final source review against the frozen private index

## Scope and binding

This is a read-only comparison against `outputs/wake_drop_v108_review_followup_20261009/b01_final_review.index`, the private index for candidate tree `93d989012c55e087fa73486c56120ce01ce9fa8f`. Later mixed-worktree Player/B02 changes are outside this review. No native run was repeated.

The generated binding record is `outputs/wake_drop_v108_review_followup_20261009/B01_GIT_WORKTREE_BINDING.json`. It compares raw frozen bytes, Git blob bytes, and newline-normalized bytes for all 19 indexed files. Every `raw_frozen_equal` and `newline_normalized_equal` field is `true`. Apparent Git SHA differences are CRLF/LF representation differences only, not source drift.

Representative rows:

| path | raw frozen SHA-256 | private-index Git blob SHA-256 | relation |
|---|---|---|---|
| `scripts/game_root.gd` | `706c754bd41d3cf39f5ef2308f7d4dbf2d7a281728c0d08408cf95c1d52a82a0` | same | exact bytes |
| `scripts/world_bootstrap_coordinator.gd` | `43544704faddcbdcfbf75c59fa9914f9f54ba68a971dd63eac59b36407190db2` | same | exact bytes |
| `scripts/features/runtime/feature_resource_preparation.gd` | `302338e03ab3ad3d38052469ed65330708047dab8b93876057ac1f770e389493` | `32ea180bbcae9f386d3a306c5163db7dc588b9d402b97ccb3b1b6db49500e61f` | raw equal; newline-only Git difference |
| `scripts/layers/runtime/content_layer_registry.gd` | `fadfdff4772dd5806f6bccc058533d95f13d728bbb284cbe35220e18deedbf33` | `46bf79294282ad8646a22ab2bbf2710bc2083b0d75908fe2f304cfa996d9e8ba` | raw equal; newline-only Git difference |
| `scripts/monster_visual_streaming_coordinator.gd` | `70e936b9a64e76361ce624019b08f7df88dcc05d6adf9b68939e523ef4f06319` | same | exact bytes |
| `scripts/monster_source_frames.gd` | `18299833c62a2eaf231ecd267cc9878ed30eb8c180a667d2bba5cc11a651e917` | same | exact bytes |
| `scripts/startup_loading.gd` | `25a5d7e789a4ba1797da5b5e73b0c7887ec56fbe824e23944e1a730edeaf5a33` | same | exact bytes |
| `tests/retired_threaded_resource_claims_20261009.gd` | `e8c3188216f8b1130c292a861f9666d2eab846d1f1254553d6105b42490d17dd` | `1a4797fa318b83d40f5f4e47786b8896227abaca4409cb7731dfc0a52af54fe6` | raw equal; newline-only Git difference |
| `tests/framework/monster_visual_streaming_terminal_get_contract_test.gd` | `7b7f85bf2c58c308d3827bda06de8332b05f4fe1c6707b2a6ef08189c287434d` | `7c5ba2fd51e8c6be5adfd6361ee85f21638406a65d89597a86639962b14166fc` | raw equal; newline-only Git difference |
| `tests/framework/startup_loading_terminal_get_contract_test.gd` | `6e74b4d8fac408bd2ee6970170cf03a7a68bcfd35cf655fd93c31cbfded1355b` | `d25768cf9fd0b6d90518dd247354d3d3ff1943c4256324c2e478fc624c859fa6` | raw equal; newline-only Git difference |

The earlier apparent five-file drift was a comparison-method error: raw CRLF snapshots were compared directly with normalized Git blobs. There is no confirmed exact-source blocker from these hashes. Native evidence remains scoped to its receipts and does not become whole-project or Android evidence.

## Confirmed source findings

1. `scripts/monster_source_frames.gd:82-85` says terminal claims are “consumed here,” but `retire_pending_threaded_claims()` at lines 86-102 transfers LOADED, FAILED, and IN_PROGRESS claims to `ContentLayers`; the service performs the eventual bounded `get`. INVALID is correctly erased without `get`. This is a stale comment, not a runtime ownership defect.

2. `scripts/world_bootstrap_coordinator.gd:833-834` defines `_poll_retired_threaded_requests()`, but the private-index source has no call site. The active retirement path calls `_retire_pending_threaded_requests()` and `_transfer_retired_threaded_claims()` directly. This is dead private surface; root may remove it before build, but doing so creates a source delta that must be reflected in the tested-source binding.

3. The retirement service in `scripts/features/runtime/feature_resource_preparation.gd:113-126` only adopts already-issued claims and never calls `load_threaded_request`. Its rotating queue (`:167-205`) gives retirement a bounded opportunity, and `_step_threaded_claim_retirement` (`:346-370`) polls IN_PROGRESS and joins one terminal claim per granted quantum. Global `_exit_tree` joining is separate (`:736-763`). This supports the claimed fairness and bounded get behavior.

4. The private-index fixture contains concrete same-path two-claim, foreign-owner retention, separate two-claim transfer, one-get-per-quantum, and INVALID-without-get assertions. This is the behavior exercised by the retained direct12 marker.

## Negative and coverage boundaries

The native ledger remains bounded: direct12 retained `3 PASS / 2 FAIL`; direct13 reran two changed functional probes; related14 passed six resource/lifecycle probes; integration15 passed real initial-world startup. The direct12 visual/startup failures remain historical failures, and the direct13/related14 cleanup warnings remain visible. An engine-accepted `THREAD_LOAD_FAILED` request and the separate 60-second asynchronous race remain `NOT_RUN`; the fixture observes an unrequested INVALID path without making a rejected native request; this only proves INVALID recording.

The private index contains five new B01 lifecycle fixtures and safe-logout runner changes, but their presence is not a native result. Safe-logout evidence is a separate lifecycle scope and must not be counted as additional ResourceLoader claim coverage. No whole-project, Android, or performance PASS follows from B01's seven scoped native source changes.

## Disposition

Status is `PASS` for private-index/raw-source binding, with native evidence remaining scoped to its recorded receipts. No confirmed behavioral blocker was found in the bounded handoff path. The stale comment and unused helper are P2 source-hygiene items; neither justifies changing frozen production code during this review.
