# Initial failure evidence index

These runner JSON files are archived because they are the first failure evidence for the real full-frame probe before the final strict pair. They retain the per-attempt HEAD, exit state, failure counts and reason. The runner reused fixed `audio_w4_full_frame_probe_test.stdout.log`, `.stderr.log` and `.godot.log` names on retries; those line-level files were overwritten by later attempts, so this index does not invent missing error text. The final strict raw three-file sets are under `candidate/` and `baseline/`.

## Candidate (`ef827` development series)

- `candidate/runner_results_adhoc_20260909_151242_118_24352.json`: initial GDScript parse failure from adjacent string literal syntax; fixed before the physics-window work.
- `candidate/runner_results_adhoc_20260909_151332_195_7608.json`, `151424_428_17872.json`, `151450_440_4252.json`, `151603_027_17980.json`, `151704_225_1980.json`: early real-probe retries failed before the final physics-frame boundary fix; the process was force-terminated with missing marker and engine/stderr failure counts. The observed root issue was the idle/process-only window not reaching the required real physics ticks; the fixture was changed to await `physics_frame` followed by `process_frame`.
- `candidate/runner_results_adhoc_20260909_151808_872_6864.json`: remaining early retry failure in the multi-GameRoot setup; duplicate HUD viewport signal wiring was removed by using one GameRoot and reusing the 50→20 cohort.

## Baseline (`cf1d` fixture/import series)

- `baseline/runner_results_adhoc_20260909_125748_729_12984.json`: probe started before formal resource import completed; PNG loader/import state was incomplete.
- `baseline/runner_results_adhoc_20260909_130246_204_10216.json`: debug snapshot read a dynamic field absent on the old baseline service/actor shape.
- `baseline/runner_results_adhoc_20260909_130421_574_16180.json`: fixture used a two-argument `Object.get` unsupported by Godot 4.7; changed to typed single-argument reads.

All of these were fixture/import corrections. No production audio behavior was weakened and no assertion was removed. The strict pair's final runner JSON and raw logs are separate from these failures and remain the acceptance evidence.
