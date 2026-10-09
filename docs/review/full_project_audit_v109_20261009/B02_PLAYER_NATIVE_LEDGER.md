# B02 Player native ledger

This ledger records only the B02 Player evidence retained under `evidence/B02_player/`. It does not claim a full-project or device PASS.

## Fixed source and engine records

| Stage | Freeze record | Candidate tree | `scripts/player.gd` SHA256 | Engine SHA256 |
|---|---|---|---|---|
| direct16 | `B02_PLAYER_FREEZE_16.json` | `a0996b7921222fcf89ef70ed63f0aa1982aa368b` | `40CE84D019E1B5770A5749A5384C49572F7F7666A5FF581D3DB9B9BD05E718D3` | `D8055FB8C7E7F5010D7439EC69BE051554055DAE55A265F8647BD7301C34161C` |
| direct17 | `B02_PLAYER_FREEZE_17.json` | `e999954641acc49b45c1798bb179578e177fb522` | `40CE84D019E1B5770A5749A5384C49572F7F7666A5FF581D3DB9B9BD05E718D3` | `D8055FB8C7E7F5010D7439EC69BE051554055DAE55A265F8647BD7301C34161C` |
| related18 | same Player freeze family; runner retained in `related18_player_boundaries` | source binding not repeated in runner | same as above by freeze records | same as above |

The runner JSONs report `git_head=215f0b2f651a51e6855ee813ddd99221690311a1`; direct16/17 framework receipts have `source_content_sha256` empty (the related18 runner has no framework receipt). This is retained as a source-binding limitation rather than silently promoted to PASS.

## Runs

| Run | Command / scene | Result | Native / runner evidence | Receipt |
|---|---|---|---|---|
| direct16 Player | `tools/run_godot_tests.ps1` adhoc runner; `tests/framework/player_pause_movement_contract_20261009_test.tscn` | PASS, 14/14, exit 0, engine log errors 0 | `evidence/B02_player/direct16_player_pause_stealth/logs/runner_results_adhoc_20261009_231417_013_12600.json` plus copied raw logs | `framework_receipt_player_pause_movement_contract_20261009_test.result.json`, run_id `598af74c-dde7-4c03-9255-9efe581ec7fa` |
| direct16 equipment | same adhoc invocation; `tests/framework/equipment_stealth_rearm_contract_20261009_test.tscn` | FAIL: parse error at line 25, no pass marker, forced termination; stderr and engine errors retained | same direct16 runner JSON and `logs/equipment_stealth_rearm_contract_20261009_test.*` | MISSING/invalid by design; no substitute receipt |
| direct17 equipment | adhoc runner; `tests/framework/equipment_stealth_rearm_contract_20261009_test.tscn` | PASS, 10/10, exit 0, engine log errors 0 | `evidence/B02_player/direct17_equipment_stealth_fix/logs/runner_results_adhoc_20261009_231543_805_12264.json` and per-run evidence | result receipt run_id `0d1ffaee-b0de-450a-940f-9dc3dda26f0a` |
| related18 | adhoc runner; five scenes listed in disposition | PASS, 5/5, exit 0, engine log errors 0 | `evidence/B02_player/related18_player_boundaries/logs/runner_results_adhoc_20261009_231928_743_22944.json` and five UUID evidence directories | No framework receipt; runner per-scene evidence retained |

The direct16 Player framework receipt was matched by its runner `framework_run_id` and copied from `outputs/test_logs/framework`; no unrelated receipt was substituted.

## Evidence policy

Copied evidence is byte-preserving from the listed output paths. The original direct16 parse failure remains present. `DEVICE TEST: NOT_RUN`. No claim here covers APK signing, installation, sustained production load, or the full B02 audit.

## Referenced path existence check

All paths named in the tables above were checked after flattening the evidence layout and exist under `evidence/B02_player`:

- `direct16_player_pause_stealth/logs/runner_results_adhoc_20261009_231417_013_12600.json`: PRESENT
- `direct16_player_pause_stealth/framework_receipt_player_pause_movement_contract_20261009_test.result.json`: PRESENT; run_id matches `598af74c-dde7-4c03-9255-9efe581ec7fa`
- `direct16_player_pause_stealth/logs/equipment_stealth_rearm_contract_20261009_test.stderr.log`: PRESENT; original parse failure retained
- `direct17_equipment_stealth_fix/logs/runner_results_adhoc_20261009_231543_805_12264.json`: PRESENT
- `direct17_equipment_stealth_fix/evidence/0d1ffaee-b0de-450a-940f-9dc3dda26f0a/equipment_stealth_rearm_contract_20261009_test.result.json`: PRESENT; run_id matches
- `related18_player_boundaries/logs/runner_results_adhoc_20261009_231928_743_22944.json`: PRESENT
- `related18_player_boundaries/evidence/{eb6c0fbb-bc8a-430d-bc03-8e8bbb4d9cb0,cc4f1cdc-8716-4780-b5ca-a841049c1d1a,8963ea8d-de7f-40eb-8aa2-36ce93390cf9,ce0a4a1f-ab7e-4d40-b4d4-270e8cd357cb,1a7232bd-ccbe-44a4-9af7-cc225dc1a396}/`: PRESENT

No receipt from another run was used for a missing or invalid direct16 equipment result.
