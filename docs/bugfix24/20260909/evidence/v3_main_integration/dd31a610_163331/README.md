# Noncombat gate and projectile regression

HEAD: dd31a610cdf465b5b41ecd88b810164aae192a2e.
Command: tools/run_godot_tests.ps1 -TestPaths tests/hc_monster_ai/combat_epoch_delivery_test.tscn,tests/monster_physical_projectile_attack_test.tscn -TimeoutSeconds 30.
Result: 2/2 PASS; both natural exit 0; runner engine_log_errors=0. Generic disabled-combat gate and real projectile IDs 50/150/152/206. Exact nine chest data integration is a separate subsequent test.
Correctness only; concurrent disjoint test authoring was permitted. This is not performance or device evidence.

SHA256 | File
---|---
A97EAE9DBAEF3A81446453A4310D1C56206EA4C6535BC2E1D7D0C2CF699C0B50 | runner_results_adhoc_20260909_163331_520_24468.json
05037C289845B44E78ECFA5D64B57B9FCC3F30C82281E0BD7D1557C5A28A732B | combat_epoch_delivery_test.stdout.log
E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | combat_epoch_delivery_test.stderr.log
7F02135CDCD9FEBF20B78D652316138BBB94D05435055577EE76F992E38630F4 | combat_epoch_delivery_test.godot.log
0AEE6D4496F022139FF08474C732820D75CCDDC9C1AE1FC81C3371C6824C41A5 | monster_physical_projectile_attack_test.stdout.log
E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | monster_physical_projectile_attack_test.stderr.log
8CD11A946D773C0379742A82A8A3F9075D7559E8740081A53ED4C73476CF1EB5 | monster_physical_projectile_attack_test.godot.log
