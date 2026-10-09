# B06 scoped repair disposition, 2026-10-10

The local B06 candidate implements four confirmed persistence/identity repairs. This is not a whole-project audit or Android acceptance. External reports remain unchanged and bound to their original fixed source `d145826b7305ad918893ba0098db2595ae01f53a`; final local source tree is `6f0e68c325cc4256dfdc6d9cb00905afd41ca685`, freeze49 SHA256 `6e2852a906ec2776a2ad529e2304bc293ffd43fff5468e9e10d909cdebe60906`.

| Finding | Resulting behavior | Scoped verification |
|---|---|---|
| B06-001 | GroundService owns one JSON write set for changed chunks, manifest and state. It prepares and verifies bytes before recording intent, recovers before normal reads, and refuses unknown paths, changed manual bytes or incomplete primaries. | Direct42: 29 formal checks, natural native0, valid receipt, empty stderr. Ground source and fixture unchanged afterward. |
| B06-002 | Runtime artifact and release registry share a durable publish intent with separate file hashes and approved build hashes. Recovery is bound to the requested map and candidate; legacy backups recover only when identity, path, schema/checksum and approval agree. Verified selected registry backups may be consumed; byte-identical duplicates may be consumed together. Unknown, changed or conflicting backups are preserved. | Direct48: 60 formal checks plus old restart, source-preservation, fail-closed transaction and approval counterexamples PASS. Direct49: the real 19-check registry restoration test PASS after duplicate cleanup fix. |
| B06-003 | Build/publish require a verified durable document binding. Save stages revision and canonical data, uses the existing official save/load chain, and commits verified content into the original root Dictionary to preserve undo/redo ownership. Failed saves keep edited data and the prior revision. | Direct45 and direct47: 18 formal checks each, natural native0, valid receipt, empty stderr. App source unchanged afterward. Later publish changes affect only verified legacy backup recovery. |
| B06-004 | Readiness and load validate raw source numeric ID before injected runtime ID. Only positive integer or finite integral numeric values are accepted; strings, booleans, fractions and mismatches fail explicitly. | Direct42: 210 formal checks, including all 67 current releases and copied runtime with valid checksum but wrong source ID; native0 and valid receipt. Bridge/fixture unchanged afterward. |
| B06-007 | Current portal authoring footprints pass formal terrain/collision validation without moving any approved endpoint. | Related46: 132 endpoints across 67 maps, no footprint failures. This does not prove 132 actual player traversals. |

Production file SHA256:

| Path | SHA256 |
|---|---|
| `scripts/map_editor/map_editor_ground_service.gd` | `304b8c8fd4cf3d635851d65ecce3443481d30170afc459301d90a88b35005a95` |
| `scripts/map_editor/map_editor_build_runtime_service.gd` | `8aa45021290ff718c0220ce1180d9622ba94fd54884c0beecf3e6d52353afae6` |
| `scripts/map_editor/map_editor_app.gd` | `19fc7a1b7ad50a7731b4d494b4c488d2fa2d78f17b2749e2c182e55a3866035e` |
| `scripts/layers/runtime/map_editor_runtime_bridge.gd` | `57f08eb855ef0e7a908587828e51e2ea285a18b933e35761d448198fa68d3d6f` |

Initial failures are retained, not relabeled. Direct42 exposed an empty-buffer HashingContext error and a fixture type-inference parse error. Direct43 exposed a missing map-type fixture precondition. Direct44 exposed a real durable binding mismatch caused by official JSON/NPC normalization. Related46 and direct47 exposed two legacy recovery regressions. Direct48 exposed byte-identical dual backup cleanup. Fixes kept original assertions and used the official normalization and recovery owners; no load, probability, timeout or gameplay outcome was reduced to obtain a PASS.

Final selected scopes exit naturally with no engine errors or cleanup warnings. Early forcibly terminated failures have cleanup `NOT_RUN`, not clean-exit acceptance. Exact commands, engine hash, input hashes, invocation/run/producer associations, receipts and historical failures are in `B06_NATIVE_VERIFICATION_LEDGER.json`; 284 retained files totaling 5,730,120 bytes are bound in `B06_RAW_EVIDENCE_MANIFEST.json`.

The older worker reviews describe their intermediate static source. Final details take precedence: Ground journal schema accepts canonical finite integral JSON numbers; App save preserves its root object, normalizes through official Types/JsonCodec/Catalog before durable verification, and hashes files with FileAccess; runtime file hash remains distinct from approved build hash. Restoration primitives still preserve their source until verification, while the publish recovery owner may consume only the proven source afterward.

B06-005 abnormal-kill reward durability remains an undefined product boundary; no second loot journal or drop probability was introduced. B06-006 source-hash metadata differences do not prove stale art; no manual map, art, generated data or approved portal location was rewritten. Preview PNG joint recovery, real process-kill/power-loss recovery and Android tests remain `NOT_RUN`. A future runtime guard for portal landing geometry is separate from the passing current authoring footprint check.

Whole-project semantic coverage remains `MISSING`. B06 selected responsibilities do not close its 50 remaining script-function gaps or authoring/art gaps. B07A, B07B and B08 remain `NOT_RUN`; formal109 build and DEVICE TEST remain `NOT_RUN`. Main integration HEAD and raw index are preserved during scoped review publication.
