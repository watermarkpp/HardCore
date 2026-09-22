# Monster mixed damage and source status integration

Atomic mixed implementation d6c59a0c; source status implementation 416ebeb4. Tests ran on the prior HEAD with the corresponding staged/working-tree additions, not a clean final HEAD.
170515: mixed + existing summon incoming 2/2 PASS. 170933: source status + mixed + summon incoming 3/3 PASS. 171247: enhanced source status MP shield and pending-attack cancellation assertions 1/1 PASS. Every process naturally exited0; runner engine_log_errors=0.
Raw status logs correspond to 171247; raw mixed/summon logs to 170933. The original 170515 same-name raw logs were overwritten; its runner JSON is retained. Existing ObjectDB cleanup warning text is not removed.
Command: tools/run_godot_tests.ps1 -TestPaths <scenes listed in each runner JSON> -TimeoutSeconds 60.

SHA256 | File
---|---
0AEE573CB35B88550A0A40B4D9C14328CF4FE3992C7C44DCB8A18300940D689F | monster_mixed_damage_atomic_test.godot.log
26E0268E603F5C2CC6A8B554013E3937808D3CF8B666A3093E3047ABF6E377D5 | monster_mixed_damage_atomic_test.stderr.log
9C528A49F7AC0EFF5EE371E9314389B52FA1DD9289E9249ECC8F616A4E53C222 | monster_mixed_damage_atomic_test.stdout.log
152A2485DB277A8494EA89FF7BFBB0F14BFB02B51A2AC2DF522F3E49B590672E | monster_source_status_test.godot.log
26E0268E603F5C2CC6A8B554013E3937808D3CF8B666A3093E3047ABF6E377D5 | monster_source_status_test.stderr.log
1BB85B194BD36C4E62F4F41CCD3F7AA6D136D88577C3C4E532C8B23AFA15CFF6 | monster_source_status_test.stdout.log
CEA17A7878C94BB984DC1A864B5672FE39EE387E1C2754BBB4FFE09EEDB0BC71 | runner_results_adhoc_20260909_170515_385_21840.json
89CD99CC13DDE7BBA8DB6051DFE7219B39A51CF58A310908BC3FE98BE36ABEE0 | runner_results_adhoc_20260909_170933_756_1932.json
C88407EE3CAA71467C0C7161CD3DD8DCFD02747B0005FCC5A58C0DE500CACAC9 | runner_results_adhoc_20260909_171247_486_2308.json
BD84CA1AFA8EE719DD66702808D41426BA777AE442CBDD8824FA1F9E8D704676 | summon_incoming_damage_runtime_test.godot.log
26E0268E603F5C2CC6A8B554013E3937808D3CF8B666A3093E3047ABF6E377D5 | summon_incoming_damage_runtime_test.stderr.log
4683FA9840FA0121A4A49286EB24CC235573B656C40055E731F500AD2007DF4E | summon_incoming_damage_runtime_test.stdout.log
