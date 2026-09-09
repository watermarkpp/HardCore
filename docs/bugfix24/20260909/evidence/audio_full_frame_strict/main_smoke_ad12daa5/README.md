# Main integration functional smoke

Code anchor: ad12daa5. Documentation and archive attributes were dirty; production source was unchanged.
Command: tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_full_frame_probe_test.tscn -TimeoutSeconds 60
Runner: runner_results_adhoc_20260909_160126_352_12236.json; natural exit, PASS, 1/1.
This was NOT a quiet performance run. V3 work ran concurrently in another tree. Its timing values must not replace the strict paired comparison.
Original stderr and engine log are retained; runner allowlist counts do not imply raw zero errors.

SHA256 | File
---|---
C28EC6D70A10F7376D1ACF9C289ADF0E8E5B09267897E8D2A4FBABA45DD871FF | audio_w4_full_frame_probe_test.stdout.log
C97498A987672E08CC50B133A61A5E626AC5841E865AFC32AFA14342F6E6A874 | audio_w4_full_frame_probe_test.stderr.log
205C2DDC94BDE3D299FAFB28CB361F97A7AE38683DF5427A6865E03C372974C4 | audio_w4_full_frame_probe_test.godot.log
60024FE9ACB03357971AB3EDBDD0AC4DA21A7FB00A9DD708F5DA980FE8629E3D | runner_results_adhoc_20260909_160126_352_12236.json