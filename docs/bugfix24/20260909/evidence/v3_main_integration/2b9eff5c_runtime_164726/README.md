# Ordinary Boss cadence regression

Main dcf98d24 integrates source da323fce: ordinary Boss ID162 keeps the 1.8/1.99/2.0 GU cadence assertions. Later 2b9eff5c only changes docs and adds the unrelated T30 critical entry.
First run with TimeoutSeconds30 timed out after catalog loading, no PASS marker. All raw logs retained. TimeoutSeconds60 rerun: 1/1 PASS, HC_RUNTIME_PASS checks=80, natural exit0, runner engine_log_errors=0. No test assertion or production source changed between runs.
Command: tools/run_godot_tests.ps1 -TestPaths tests/hc_monster_ai/runtime_test.tscn -TimeoutSeconds60.
Concurrent independent worker activity means this is correctness evidence, not performance evidence. Do not infer a timeout root cause from the successful rerun.

SHA256 | File
---|---
0DD77F2F16B0A05E0A82C22913709EC0E25C75AF9658D73F24C90744A3E90A36 | pass.godot.log
E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | pass.stderr.log
70720036ABAC4B135D37D15FA91C4814F23CB040DA43D0C774178A5DD18D5786 | pass.stdout.log
BA9403312C6CF3224684AB73012D301548F3B5795FE06DA76AF261C90BD58781 | runner_results_adhoc_20260909_164606_940_23904.json
4F6B2CC5F7D024C74EA50A8120AE4A15B403D2AB785FFD381B1877840107F8AF | runner_results_adhoc_20260909_164726_879_8416.json
C44997026DBCF0B2EB061571F05CE46B18BB112F7ECCA99C555CFF335563A517 | timeout30.godot.log
E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | timeout30.stderr.log
3046D3D514EAFCC981015F47361C534B4C55F078A6C3475B46AEAE49A4157DE9 | timeout30.stdout.log
