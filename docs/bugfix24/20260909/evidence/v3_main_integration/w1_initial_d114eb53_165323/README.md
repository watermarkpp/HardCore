# W1 exact ranged and noncombat initial matrix

Production: d114eb53; final test had two working-tree reacquisition fixes, now committed as 51f17301. Full root cause and scope: ../../../W1_EXACT_RANGED_TEST.md.
Final 1/1 PASS, natural exit0, engine_log_errors=0. All three attempts retain raw stdout/stderr/engine and runner JSON. The middle failed attempt printed PASS but was correctly rejected for its script assertion.
Command: tools/run_godot_tests.ps1 -TestPaths tests/w1_exact_ranged_delivery_test.tscn -TimeoutSeconds 60.
Actor methods are exercised directly with real PlayerCharacter and real WORLD physics bodies. This is neither the entire W1 special-family acceptance nor natural whole-game timing/device proof.

SHA256 | File
---|---
9693EB0D7C1603A54AEC3ACACB9D90D115A29703642AD0764906AF23FC22F924 | magic_epoch_failure.godot.log
78ABCA91DAE1C0FC4EF127F366D540A32FAC18E5B87992183A4BC19BC83014C5 | magic_epoch_failure.stderr.log
4C39EC11567CF3DBD25DA21C3A286EBE61D25F7137D81D82CF5E224A7054977A | magic_epoch_failure.stdout.log
F9FAB480DAD3751063FFE3236D839137FE61D2C3EB346F05CAAB6504A41AAF22 | pass.godot.log
E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | pass.stderr.log
4C39EC11567CF3DBD25DA21C3A286EBE61D25F7137D81D82CF5E224A7054977A | pass.stdout.log
8263B75B51947BE9A44D183F3B0A7E13DB3D5B34C17167E934CEF292A2BFC4F4 | physical_epoch_failure.godot.log
95A1582EA6B3713C47EF2421E2265AE21175327F7DBF6AAAAA3DF9EC42326096 | physical_epoch_failure.stderr.log
8F21FE8002B2059A5678ED9DCEC2FB497428FEBF94480EFCF73D72AC05FB13FA | physical_epoch_failure.stdout.log
9E1581F5BAF8BCD9E56D7D09980BDAA2A3747A6EFA1D5AA290976AAA27A8FEF0 | runner_results_adhoc_20260909_165152_613_15408.json
6D2ECAE7D165EE3A452F6431A5F9CFADBC0EBCF29A719541DA6FF14D0283A550 | runner_results_adhoc_20260909_165225_232_17404.json
9590F7F2EEBEF6C288BFECCDAD549649331DBFD0A0F7D4899F88CA2948706B70 | runner_results_adhoc_20260909_165323_920_2428.json
