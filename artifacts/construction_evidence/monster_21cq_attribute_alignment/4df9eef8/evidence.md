# 21CQ monster attribute final closure evidence

## Delivery

- 21CQ attribute implementation: `41b284250825dcc43a5a8bd7782add0f50c9c689`
- Python entrypoint repair: `504e9a18906d55d6dcdcbed22610538ee95c9d1b`
- forbidden-field validation repair: `577dee7983415f59966a3fd2417961c9414db10e`
- anti-stealth runtime closure: `4df9eef8b824550b38d7d0ef5555129e12385100`
- source snapshot: `assets/data/monster_21cq_detail_source_v1.json`
- source snapshot SHA-256: `2F2DC3D1AB733081FD36BFE9608702E13B468A0EE0D8A921DC77501DFA13474F`

## Closed contracts

- `21CQ ATTRIBUTE ALIGNMENT = PASS`: 217 exact-ID source records; 156 active canonical records; 153 runtime-allowed records.
- `MONSTER ACCURACY RUNTIME = PASS`: ordinary melee and physical projectiles use the primary strict `roll < accuracy` rule.
- `ANTI-STEALTH DATA = PASS`: canonical `anti_stealth` matches the exact-ID 21CQ source.
- `ANTI-STEALTH RUNTIME BEHAVIOR = PASS`: canonical ID 38 pursues a hidden target while canonical ID 64 remains stealth-suppressed at the same four-GU distance; both pursue when the target is visible.
- `NO DROP / RESPAWN SCOPE VIOLATION = PASS`: this closure changes only `scripts/enemy.gd`, its behavior test, formal suite registration and this evidence document.

Primary behavior evidence is `dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas` (`not HideMode or CoolEye`) with the monster-table-to-runtime binding in `M2Server/UsrEngn.pas`.

## Final verification

The tracked evidence commit was verified with:

```powershell
tools/run_godot_tests.ps1 -Suite monster -TimeoutSeconds 60
```

Result: `PASS 32/32`, `failed=0`, `engine_log_errors=0`.

All 32 registered monster scenes passed, including:

- `monster_accuracy_runtime_test`
- `monster_anti_stealth_runtime_test`
- `monster_mfc1_attribute_timing_audit_test`

The formal suite is rerun after this result is committed so its runner `git_head` reports the final Git commit containing this document. No GitHub Actions run is claimed; this is the tracked local final-HEAD acceptance record requested during independent review.
