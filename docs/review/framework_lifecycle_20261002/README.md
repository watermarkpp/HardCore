# Lifecycle and combined-workload checkpoint — review only

Parent review commit: `211acc30023934ced8160eb5f4dc0a20de5b50b5`. Construction branch remains `codex/pluggable-framework-v2` at `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`; main v97 and the second tree are not integrated or repackaged.

Final native run: 14/14 scenes, 293 individual assertions PASS, actual native exit 0, valid per-run receipts, zero engine/script errors and unchanged source/engine bytes. Full in-situ test fingerprint: `be3e6596fe28f73f6cec59123957494cc2749477c6620502d2db64c2170b5001` (3477 files). Review delivery fingerprint: `847c42a6278f9241551378775697c528742539a9d56fc8f774995236224efe5c` (3472 files). Engine: `4.7.stable.official.5b4e0cb0f`, SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`.

The five-file difference is explicit in EXCLUDED_PREEXISTING_FILES.json: standalone default-root migration fixtures already present at the beginning of this segment. They did not change, are not imported by this increment, and are not included or claimed as executed. The full native manifests retain their hashes. This snapshot never mixes their bytes, unrelated dirty files, original user saves, credentials, caches or engine binaries into the commit.

## Proven changes

1. **Live-world profile ownership.** The actual causal RED directly selected B after A's lethal periodic HP commit but before its deferred death callback: B received XP=1, A received none. The official menu/logout barrier was separately safe. PlayerState now rejects character replacement, same-role selection, creation and deletion while a registered live GameRoot owns gameplay. Root registers at ready and unregisters after exit cleanup; queued deletion still protects the owner, weak references prevent stale ownership, and one world cannot release another's guard. Two direct scenes have 46 checks; nine related scenes pass, including normal logout and an independent cold process. No second payout/save authority, schema change or new entity ID.

2. **Completed queue containers are released.** A continuous producer with only one pending fact retained 510 target ActorRef objects from completed batches. The indexed queue removes each completed batch without shifting live work. Eighteen direct checks and seven related scenes (145 checks) pass. All 514 historical dedup receipts remain, and an old release replay still cannot refresh/reapply effects. This is queue-buffer reclamation, not receipt eviction.

3. **Effects participate in ordinary-frame service.** A 30-target/90-state/360-tick native cohort was more than three full configured periods late (3066667us), despite retaining all damage. Effects only ran in physics and could not reuse the fair turn that resource/death process consumers released later. GameRoot now pumps the same runtime after resource service in process as well; physics alone advances the existing simulation clock, and the same frame budget is never reset. The identical cohort then had maximum lateness 750000us. Final read-only service-age instrumentation and 14-scene regression confirm no lost target, tick, death, reward or persistence receipt.

Final cohort: 90 independent states of the existing ignite handler, 360 periodic settlements, 1800 actual HP loss, 30 canonical rewards, five real threaded textures, durable save and independent cold reload. 686 raw wall-frame samples: P95 7612us, P99 8739us. Death drain 794152us; resource completion 28344us. Runnable service ages are included separately from continuous pending-owner age; the latter is not request latency.

## Evidence limits and remaining gates

The P6 cohort fixes receiver autonomous updates explicitly while retaining real Root clocks/pumps, HP/death/resource/persistence paths. It is three legitimate source identities of one existing mechanic, not three new effect types, GPU/device testing or a broad R3 movement/performance claim. The under-one-configured-period test is a bounded workload acceptance check, not a new global gameplay or device guarantee. The initial fixture failure and the real timing RED remain available; no failed run was relabeled PASS. Native ObjectDB exit warnings remain in raw logs.

Complete preacceptance effect capacity remains FAIL. Receipt retirement at 65536 and persistent journal64 are different contracts: no TTL/LRU, receipt deletion or journal compression was introduced. Pro review must still prove old identity cannot re-enter and producer/consumer/async ownership has ended before proposing retirement. Exact v97 B-profile failure input remains MISSING; fresh three-role and archived v90-on-v97 tests do not close that reported backpack defect. Remaining identity pricing paths, full P6 release/long-run gates, R3 performance failure, main integration, APK/signature/install and DEVICE TEST remain unfinished.

## Reproduction and bytes

Reconstruct the prior review's native source in an isolated inspection directory, apply NATIVE_DELTA_FROM_211ACC300.zip under source/, then verify every entry in REVIEW_SOURCE_MANIFEST.json. TESTED_SOURCE_MANIFEST.json describes the larger local test census including the five excluded, unexecuted files; do not claim the delivery is byte-identical to that larger set. SOURCE_INCREMENT.diff and the 12 source/test paths are the entire new code scope.

Use the existing tools/source176_r3_validation.py wrapper and commands saved in RUN_INDEX.json. Set HARDCORE_AUDIT_RUNTIME_APPDATA to a new owned directory before the process starts. Combined live and cold tests must run in order in the same isolated directory. Do not run any test against real user data. All new mechanics remain default OFF; no APK is produced by this checkpoint.
