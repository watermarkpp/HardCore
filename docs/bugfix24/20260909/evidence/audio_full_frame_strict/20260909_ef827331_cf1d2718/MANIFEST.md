# W4 strict A/B archive manifest

- Archive version: `20260909_ef827331_cf1d2718`
- Candidate runtime/test HEAD: `ef827331c926755e547b5b47f00cde3aff37dc15`
- Baseline runtime/test HEAD: `cf1d2718befdef7e6cc2fb274fd91ce0759d105f`
- Formal map: `world_wooma_forest`, `map_id=910004`
- Seed: `20260909`
- Sampling: 50 then 20 actors; 60 real physics tick warmup and 240 real physics tick window per condition
- Conditions: baseline `legacy_on`, `legacy_off`; candidate `candidate_on`, `candidate_off`; 8 records total
- Runner command: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_full_frame_probe_test.tscn -TimeoutSeconds 60`

## Byte identity and temporary overlays

- Probe `.gd` SHA256 in both trees: `3FC5419B559163C8B8417434CAA6B1148053964E1F66A0E047B546A98DA764D4`
- Probe `.tscn` SHA256 in both trees: `2E18A7D95C1B85FB388769873F9718F6E05F979FC19A8F1CF435C1375F44ACBD`
- Headless compatibility overlay used in both runs: `world_bootstrap_coordinator.gd` SHA256 `796C59DE6190516F2CED97252C6E692F1135C25C369C997C89000B268E917199`; `ui_item_texture_cache.gd` SHA256 `8821B38D2A6C7615796C7A7A69AD570BA5C7518023DB346353E32E00EE03E5F5`
- Candidate overlay source hashes before temporary copy: `world_bootstrap_coordinator.gd` `E279F0AAC43B52BBEA1CCE0BCE5AFB3D423258123E727416C1EEF1031C4D5A76`; `ui_item_texture_cache.gd` `D39BDB97E02F88146B1792BB56989872B8CBF74FADB845619D0E8CE7108FD6CB`
- Candidate temporary overlay was restored after sampling; candidate worktree returned clean. Baseline detached worktree retained its pre-existing dirty/staged overlay and unrelated staged files.
- No `tests/audio_w4_full_frame_probe_test.gd.uid` existed in either tree at capture time; no UID was added.

## Archived files

| SHA256 | Relative path | Bytes |
|---|---|---:|
| `B5FE55E21841A2F068F0B4194903C6F3ACD5EEA377C838C95ADE464F73B8CFEA` | `baseline/audio_w4_full_frame_probe_test.godot.log` | 162707 |
| `C97498A987672E08CC50B133A61A5E626AC5841E865AFC32AFA14342F6E6A874` | `baseline/audio_w4_full_frame_probe_test.stderr.log` | 249 |
| `23280E553677F64E9988F493E65B0F811710810006C1C0139380E9238C7820D4` | `baseline/audio_w4_full_frame_probe_test.stdout.log` | 162715 |
| `5B00F7AEA7D59F2D94B10EEA37F47B13DAD33D0282C8FF4D7761B82ADAF10FAF` | `baseline/environment_manifest.txt` | 1010 |
| `B723647A6EC33A27BAA80967A25C671F0B1A6BCF2D8C376AD44BAB1CE5611F9F` | `baseline/perf_runner_console_baseline_20260909.log` | 278 |
| `38FB65AB1B1D9941330538B84163AE2B41FF2367473A14DEDF0A51C561F8EDD2` | `baseline/runner_results_adhoc_20260909_154446_265_1896.json` | 1040 |
| `2B403703BD7E7A98F1E8E19D5BB901445AF2C52CD1A4F5C75E21CBF333651A16` | `candidate/audio_w4_full_frame_probe_test.godot.log` | 172145 |
| `C97498A987672E08CC50B133A61A5E626AC5841E865AFC32AFA14342F6E6A874` | `candidate/audio_w4_full_frame_probe_test.stderr.log` | 249 |
| `79137CAECA065D23BBFA8BEE2198F11775A00A836150C2FD71479B2330D168AE` | `candidate/audio_w4_full_frame_probe_test.stdout.log` | 172153 |
| `F5F19BFD3AA894D35052016BA357706F60D3086E283C1B8F3920FDCEEC174332` | `candidate/environment_manifest.txt` | 744 |
| `5A561337DC561910D868B01A866173958B56DE111C7895C7B5D2203121364A22` | `candidate/perf_runner_console_candidate_20260909.log` | 270 |
| `DB4E542C19EE2E552265CA8D1F98A39C4D77F1A09735BA6B02895A1D02985363` | `candidate/runner_results_adhoc_20260909_154640_120_10924.json` | 1040 |
| `F52DB27B8F951603B09425991EDC5BC1DDAB1D8F7FF0D29CEBA652C20DA57206` | `initial_failures/baseline/runner_results_adhoc_20260909_125748_729_12984.json` | 1179 |
| `9B9600F9B10DC93F7640926E973AB1E4933B3CF6D206A26B0E3874A81464F173` | `initial_failures/baseline/runner_results_adhoc_20260909_130246_204_10216.json` | 1158 |
| `3B29F5037266952E053FB964159F6DDCE0C5159DC8C7F9B1C7CD78B1A8C9F2FB` | `initial_failures/baseline/runner_results_adhoc_20260909_130421_574_16180.json` | 1179 |
| `114FF1ED163D84D75E4F9DFAF41FB54970D2CA43FA20E85D84AA5AB74C10E92E` | `initial_failures/candidate/runner_results_adhoc_20260909_151242_118_24352.json` | 1177 |
| `3094E6F73F0D33B52794DF8525D650C65A4D8F78FDEBACB64263FA4AFF84421A` | `initial_failures/candidate/runner_results_adhoc_20260909_151332_195_7608.json` | 1177 |
| `017B51E29392BE4A7E2B3D7E7E8BB472391A7B1BE8EC570A3E0840E8131AB179` | `initial_failures/candidate/runner_results_adhoc_20260909_151424_428_17872.json` | 1177 |
| `C89A37E5EA865F20710BAB83F72EC3E319EBC4B87FCD4E807ACA299BDDC25F98` | `initial_failures/candidate/runner_results_adhoc_20260909_151450_440_4252.json` | 1177 |
| `523AF1DC6D727512AD927D9381A72FB0DA82A38B7242C9C6F70BE2605029AB03` | `initial_failures/candidate/runner_results_adhoc_20260909_151603_027_17980.json` | 1177 |
| `A1EA3CCE84DA82E4F5F6413A11A7D85868A8187FC40B92666C97C2F78E31FB3A` | `initial_failures/candidate/runner_results_adhoc_20260909_151704_225_1980.json` | 1177 |
| `50BDEA33C0137E3ACFEB3688125DD4660EE78ED58826A212395E2E22D32F8706` | `initial_failures/candidate/runner_results_adhoc_20260909_151808_872_6864.json` | 1079 |
| `26F031885D8E6E741C0E58CB53E6050F59642F6A9C7E3813A70166B5200F4D83` | `initial_failures/INDEX.md` | 2273 |
| `B4D8F5F85452EE6268C126154AF3F1F6E5856D4816EB6F12272E2623025ACC08` | `STRICT_SUMMARY.md` | 6809 |

## Runner outcome

- Baseline result JSON records natural exit, effective exit code 0, PASS marker, timeout false, and zero runner failure counts.
- Candidate result JSON records natural exit, effective exit code 0, PASS marker, timeout false, and zero runner failure counts.
- Both stderr files intentionally retain 3 ObjectDB leak warning lines and `ERROR: 1 resources still in use at exit`; the existing runner allowlist accepted the teardown line. Engine logs contain no script/parse/assertion/fatal/crash failure.
- `initial_failures/` contains the selected pre-final runner JSON outcomes; the runner reused fixed stdout/stderr/Godot filenames, so later retries replaced their line-level logs. The JSON result records are preserved without inventing missing log text.

## Evidence interpretation

- `full_frame_ms` is adjacent `_process` wall-clock interval; `audio_service_wall_ms` is observed formal service-call wall duration; neither is dedicated audio-thread CPU.
- Per-actor attack sequence and service-request equality are the workload proof. Attack totals vary because production `_attack_timer` is deliberately not reset between real windows; the difference is not a claimed audio gain.
- This archive is headless host evidence only; no Android/device/mixer claim.
