# W4 strict A/B evidence — 2026-09-09

## Run identity

- Probe: `tests/audio_w4_full_frame_probe_test.tscn`; formal map `world_wooma_forest`, `map_id=910004`; seed `20260909`.
- Candidate code HEAD: `ef827331c926755e547b5b47f00cde3aff37dc15`.
- Baseline code HEAD: `cf1d2718befdef7e6cc2fb274fd91ce0759d105f` (detached worktree).
- During both runs, probe `.gd` SHA256 was `3FC5419B559163C8B8417434CAA6B1148053964E1F66A0E047B546A98DA764D4`; probe `.tscn` SHA256 was `2E18A7D95C1B85FB388769873F9718F6E05F979FC19A8F1CF435C1375F44ACBD`.
- Both runs used the same fixture bytes, the same 50 then 20 order, 60-physics-tick warmup and 240-physics-tick sample window. Layout signatures matched within each actor-count pair; raw actor coordinates and per-actor proof are in each stdout JSON.
- To equalize headless bootstrap behavior, both runs used the same temporary overlay bytes: `world_bootstrap_coordinator.gd` SHA256 `796C59DE6190516F2CED97252C6E692F1135C25C369C997C89000B268E917199`; `ui_item_texture_cache.gd` SHA256 `8821B38D2A6C7615796C7A7A69AD570BA5C7518023DB346353E32E00EE03E5F5`. The candidate overlay was restored to its original HEAD content after sampling; baseline pre-existing dirty/staged overlay and unrelated staged files were preserved.

## Commands and runner results

Both commands were run serially with no parallel Godot process:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_full_frame_probe_test.tscn -TimeoutSeconds 60
```

- Baseline runner JSON: `C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-audio-baseline-20260909\outputs\test_logs\runner_results_adhoc_20260909_154446_265_1896.json`.
- Candidate runner JSON: `C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-audio-20260909\outputs\test_logs\runner_results_adhoc_20260909_154640_120_10924.json`.
- Each runner reported `passed=1 failed=0 engine_log_errors=0`, `pass_marker_found=true`, `process_exited=true`, `wrapper_exit_code=0`, `effective_exit_code=0`, `timeout=false`, and zero stdout/stderr/engine-log failure counts.

Raw files retained for each tree:

- `audio_w4_full_frame_probe_test.stdout.log`
- `audio_w4_full_frame_probe_test.stderr.log`
- `audio_w4_full_frame_probe_test.godot.log`
- `perf_runner_console_baseline_20260909.log` / `perf_runner_console_candidate_20260909.log`

Both stderr files retain this shutdown output; the runner's resource line is its existing allowlisted exit diagnostic, not raw zero-error output:

```text
WARNING: 3 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2535)
ERROR: 1 resources still in use at exit (run with --verbose for details).
   at: clear (core/io/resource.cpp:822)
```

Both engine logs contain no `ERROR`, `SCRIPT ERROR`, parse, assertion, fatal, crash or segmentation-fault lines. No Godot process remained after either run.

## Condition results

`full_frame_ms` is the probe's adjacent `_process` callback wall-clock interval from `Time.get_ticks_usec()`. `service_wall` is the proxy's observed formal service-call wall duration. `attack_sum` is the sum of per-actor `_audio_attack_sequence` deltas; `req` is the matching `attack_start` request count. The raw JSON contains all per-actor proof, frame samples, delta diagnostic samples, service samples, rejection reasons and metrics.

| Tree | Actors | Condition | Physics | Proofs / delta distribution | attack_sum / req | total req / plays / rejects | full_frame wall p50/p95/p99 ms | service wall p50/p95/p99 ms |
|---|---:|---|---:|---|---:|---:|---|---|
| baseline | 50 | legacy_on | 240 | 50 / `2:50` | 100 / 100 | 158 / 130 / 28 | 6.893 / 12.794 / 15.245 | 0.063 / 0.082 / 0.092 |
| baseline | 50 | legacy_off | 240 | 50 / `1:8, 2:42` | 92 / 92 | 150 / 122 / 28 | 6.999 / 12.391 / 13.691 | 0.057 / 0.084 / 0.119 |
| baseline | 20 | legacy_on | 240 | 20 / `2:20` | 40 / 40 | 65 / 56 / 9 | 6.918 / 9.374 / 9.924 | 0.054 / 0.096 / 0.125 |
| baseline | 20 | legacy_off | 240 | 20 / `1:15, 2:5` | 25 / 25 | 50 / 41 / 9 | 6.918 / 9.333 / 9.835 | 0.053 / 0.084 / 0.097 |
| candidate | 50 | candidate_on | 240 | 50 / `2:50` | 100 / 100 | 110 / 10 / 100 | 6.948 / 12.348 / 14.361 | 0.023 / 0.073 / 0.116 |
| candidate | 50 | candidate_off | 240 | 50 / `2:50` | 100 / 100 | 100 / 0 / 100 | 6.950 / 12.294 / 13.039 | 0.010 / 0.017 / 0.025 |
| candidate | 20 | candidate_on | 240 | 20 / `2:20` | 40 / 40 | 49 / 10 / 39 | 6.925 / 9.305 / 10.252 | 0.025 / 0.112 / 0.124 |
| candidate | 20 | candidate_off | 240 | 20 / `1:5, 2:15` | 35 / 35 | 35 / 0 / 35 | 6.902 / 9.248 / 10.091 | 0.011 / 0.025 / 0.025 |

- Every condition had 240 recorded physics ticks, at least 575 wall process intervals, and every retained actor had `attack_start_delta >= 1` (`bad_proofs=0`). Candidate owner request attribution matched each actor delta; baseline monster/global attribution matched the aggregate.
- Candidate `candidate_off` requests all reached the real service and were rejected as `sfx_disabled`; candidate on rejections were real `monster_polyphony_limit` decisions. Baseline rejections were real `missing_mapping` decisions. No budget or resource path was bypassed.
- The on/off `attack_sum` values are not an audio-performance claim. The probe requires one real attack per actor, then records the natural number of starts in the fixed 240-physics-tick window. Attack timer phase, warmup/window boundary and ordinary runtime scheduling leave some actors with one start and others with two; this accounts for the observed 100/92, 40/25 and 40/35 differences. Per-actor sequence and service-request equality prove that recorded requests correspond to real starts; they do not prove that differing request totals were caused by the SFX switch or indicate a device performance gain.

## Evidence boundary

This is Godot 4.7 headless host evidence from a formal map and real process/physics paths. Wall-clock intervals include host scheduling and process load; service wall duration is not dedicated audio-thread CPU. The run does not measure speaker mix latency, hardware audio threads, GPU timing, Android CPU/GPU or device playback. No device or mixer conclusion is claimed.

### Attack-count interpretation source check

The fixture resets the audio observer, target and placement between conditions but does not reset production `_attack_timer`; it waits real physics/process boundaries and lets the formal attack cadence run. Therefore the 240-tick window can contain one or two starts per actor depending on the timer phase and the exact warmup/window boundary. This preserves a real workload and explains why on/off request totals differ; the table must be read with the per-actor proof and request equality, not as an equal-request throughput comparison.
