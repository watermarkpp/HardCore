# Warrior original-material cleanup · verification

## Source and scope

- Repository HEAD at this review: `78a797973409c0ce47590b928f3d26ff067fe567` on `codex/integration`.
- Formal `assets/art/characters/warrior/effects/wide_hit.png`: 1440×1792 RGBA, eight direction rows × six frame columns. Original SHA256 `AA0B29F13D5C9A196C5F2372AD47FEFA75F8B328684D4B8689A70F279C26276C`; user-approved 150% SHA256 `EF9196C3EAA7C9DCB9A01A831D87A4679E6B6D76E5309B7E3526AD236D70CEA4`.
- Formal `assets/art/characters/warrior/effects/power_hit.png`: 1344×1792 RGBA, eight rows × six frames. Original SHA256 `4300CE585417A5EBFCD3AAE77F747E69CE4B878D95AE888F8EB38E056F23A1CB`; user-approved 200% SHA256 `AA1DE8BEF130F307AD6DF12DED3F16E45907AA213BDD2DA6DE807737BAA5B222`.
- Formal `assets/art/characters/warrior/effects/long_hit.png`: 1728×1792 RGBA, original SHA256 `97E558356F1D4C7BBC8C63A7EF1DEDB7F7F397FA7E8385075CDA72169FE864C3`; user-approved 150% SHA256 `B638235AF9CC2BCF7CD6097B5934907E21BDAF7684E1B3E0ED4433F52EC563EC`.
- The four formal fire-sword shards are now the user-approved 30% dark-fire cleanup, each still 1920×1920 RGBA with its original path and 3×4 frame layout. Archived originals retain their four source SHA256 values; approved SHA256 values are `13BD0F9C…7782F0EC`, `6B891619…1DAB2F`, `ABD968E1…3A9EA8` and `198E08A5…972B4FF7` in `d0_f0`, `d0_f1`, `d1_f0`, `d1_f1` order.
- The original bytes are preserved in `tools/half_moon_generator/source/wide_hit_original.png` with the original SHA256. The formal filename, dimensions, cell layout and registration are unchanged; the approved parameters are haze cleanup 1.5, body brightness 1, highlight 0, detail 0 and no direction offsets.
- The existing dirty `AGENTS.md` and unrelated untracked `.uid` files were left untouched.
- The old six-SW-image candidates and their manual offsets remain archived in the ignored local project. The editor now selects `HM_ORIGINAL_WORK` from the archived original atlas.

## Checks

| Check | Status | Evidence |
| --- | --- | --- |
| `py -3.12 -m unittest tools.half_moon_generator.test_fire_editor tools.half_moon_generator.test_thrust_editor tools.half_moon_generator.test_power_editor tools.half_moon_generator.test_hmg -q` | PASS | 44 tests. They cover four independent editors, archive preservation, reset, undo, alpha progression, eight-direction preview and byte identity between all seven approved atlases/shards and formal runtime assets. |
| Original source identity | PASS | Archived authoring sources retain their original SHA256 values. The editor checks them before constructing a working version. |
| Eight-direction, six-frame bake | PASS | Approved 150% bake exports a 1440×1792 RGBA atlas. Original and approved atlases each report the same 30 inherited continuity warnings; the cleanup introduces no new warning. |
| Full warrior effect rebuild in an isolated temporary output directory | PASS | Rebuilt `wide_hit.png`, `power_hit.png`, `long_hit.png` and all four fire shards each match their formal file byte for byte; seven output PNGs were confined to the temporary directory. The generated manifest records approved sources, strengths and hashes. |
| `./tools/run_godot_tests.ps1 -TestPaths tests/warrior_client_art_test.tscn,tests/warrior_visual_test.tscn -TimeoutSeconds 30` | PASS | 2/2 scenes, 0 engine log errors. All original warrior effect paths and dimensions load through the production visual. Latest runner: `outputs/test_logs/runner_results_adhoc_20260924_233014_623_19884.json`. |
| Browser preview | PASS | `HM_ORIGINAL_WORK` remains at `http://127.0.0.1:8765/`; `/power` loads formal 200% and shows the 300% slider limit; `/thrust` initially loaded original 0% and supports reversible trials with the real warrior and ground. |
| Fire-sword preview | PASS | `/fire` shows the real warrior, selected weapon, ground and 48 frame/direction combinations. The saved 30% value and formal fire shards match; `test_fire_editor` passes 4/4. |
| Haze-strength visual preview | PASS | `outputs/half_moon_generator/haze_strength_preview.png` compares current working color settings at 100%, 150%, and 200% for S/SW/N/E on the game ground. Dark haze fades incrementally while the blue-white edge remains visible. |
| AI image-edit study | FAIL | The exploratory output spilled cyan noise across cell boundaries, so it was discarded. No generated pixels entered the working candidate or formal asset. |

## Acceptance and package boundary

The user accepted half-moon 150%, power-hit 200%, thrust 150% and fire-sword 30%, and explicitly requested direct same-name replacement with no animation offset. The approved formal runtime assets are `wide_hit.png`, `power_hit.png`, `long_hit.png` and all four `fire_hit_d*_f*.png` shards. The earlier `outputs/half_moon_generator/HM_ORIGINAL_WORK.png` is a stale development snapshot and is not the approved output.

APK build, package-content verification and device test: **NOT_RUN**. The separate skill-animation worktree has committed laser/lightning/fire-wall changes plus uncommitted beam-position changes; the final APK must be built from a reviewed integrated commit after those changes are resolved. The editor has no automatic Publish action.

The independent editors remain available at `/`, `/power`, `/thrust` and `/fire`. Their saved working slider values can differ from the approved formal settings; no editor action automatically changes game atlases. The power-hit, thrust and fire editors allow values through 300%; the formal values are 200%, 150% and 30% respectively.
