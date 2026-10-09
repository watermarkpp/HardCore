# Contact-check diagnostic, 2026-10-09 10:54 CST

Native diagnostic: PASS. Source-only review: PASS. Optimization candidate: NOT_RUN. DEVICE TEST: NOT_RUN. The original 50% improvement goal is still unmet.

Current accepted main behavior was copied into an isolated stock107-based workspace. Pure wrappers count and time the original functions; the algorithm, cadence, clock, movement, damage, animation, and original full diagnostics remain active. Existing attack-start comparison is in immediate mode. Source snapshot and INPUTS bind 9,521 files and both actual engine executables; PRELOAD_BINDING is PASS. Producer: 01d5c57b-b03a-40cd-ba6b-5dc211671ab6. Runner invocation: cf9b9361-4a35-43f3-8c9c-99a59407fbc0. Native exit 0, no engine errors, no timeout. Actual command: tools/run_godot_tests.ps1 -TestPaths tests/crowd_attack_contact_diagnostic_20261009.tscn -TimeoutSeconds 60; fixed_fps=0, Engine.max_fps=60.

The preserved window has 34 alive actors, 30 engaged, 48 loot, 300 real physics ticks, and 10,200 Enemy callbacks. Process/physics counter alignment is true. Player moved 156 ticks / 2.67829444965923 GU. It includes 18 new attacks and 18 settlements, with 2 committed actions unfinished at the boundary; total_starts=21 includes three pre-window starts. Damage is 257. Decision queue ended empty with no open scopes and max wait one physics frame. Diagnostic context stack ended empty/balanced.

| Existing function | Calls | Inclusive milliseconds |
|---|---:|---:|
| Full attack access |937|94.333|
| Frontline inside access |937|21.375|
| Movement endpoint check |14,878|132.562|
| Observation refresh entry |17,094|321.946|
| Target usable |10,265|89.422|
| World-between entry |2,573|112.729|
| Melee tick parent |8,561|1,815.746|
| Actual attack-start entry |18|11.160|

These are nested inclusive times with diagnostic overhead, not additive cost buckets or a forecast of achievable savings. Observation entry counts include early cadence returns; 17,094 calls do not mean 17,094 full scans. Enemy CPU 2,657.719 ms includes wrappers and their bookkeeping and must not be scored against uninstrumented A/B or fixed107.

Full access results: all 937 CLEAR; 896 calls with cooldown still active and 41 with attack ready. Parent counts: melee tick 865, movement endpoint 54, actual attack-start 18. Movement endpoint returned false 14,824 times and true 54 times. Thus distant movement already short-circuits before full access, while legal-contact cooldown repeatedly invokes the full access path. The same-stack duplicate at actual start exists but is only 18 checks in this window. Every full access invoked its original frontline and world path. World-between boolean true must retain its original clear-segment meaning; it is not a count of blocked paths.

The user's newer design changes the reaction contract: scope eligibility detection through a shared range/contact state and scheduling, then use the existing actor-owned attack clocks. Range enter may awaken an eligible first attack; range exit retires future starts but does not cancel committed actions. Reenter must not reset a running cooldown. Only currently legal delivery-specific range, obstacle, target identity, concealment, and control checks may authorize a new action. A universal eight-attacker cap or universal circle would change the existing reach contract and is not implied.

This diagnostic supports removing repeated full checks during a legal-contact cooldown; it does not show that attack checks dominate the whole monster cost. The larger observation/movement entry work must also be considered. Do not add one Area2D per monster, call full access while pruning a queue, or reproduce all old scans in radar maintenance. No passive contact service or new cadence was implemented in this diagnostic. Main Enemy SHA remains 121e33cdadcbc5ebc4abf7796952f2c47eb9bb13fc965d819f6898cd29ece102; main raw index remains ddacea4eed570faed0a6003c87352552e74e902874b5dee61d8863a2316e29d7.

Evidence is in contact_diagnostic_01/raw_report.json, INPUTS.json, PRELOAD_BINDING.json, source_snapshot, and native_logs. This is a new attribution run because previous attack-submission A/B never measured these checks; unchanged validation was not repeated.
