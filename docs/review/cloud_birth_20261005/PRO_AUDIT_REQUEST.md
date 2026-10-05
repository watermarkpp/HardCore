# Pro review request: published birth closure

This is a prepared request, not a received review. Audit fixed code SHA **67aaa55f46d34fe793e17bce7cc016b799dc8430** in `watermarkpp/HardCore`; parent **ff000d78071c7cccc7a068038704da3e2606f76f**. Compare the code with the user's latest current-world rule: only the complete actually published base plan and registered original SummonQueue jobs qualify, including accepted pre-freeze descriptors and normal same-slot respawn. Keep sole HP/planner/writer, RNG, movement and save authority.

Start with `scripts/features/adapters/world_target_bound.gd`, `scripts/game_root.gd`, its world-load coordinator and environment pipeline consumers, `scripts/monster_ai_package/m30/summon_queue.gd`, the enemy setup consumer and the new published-world framework tests. Follow actual entry points rather than interpreting filenames as a proof. Use the README and manifest in this directory to verify all raw evidence; do not mix earlier dirty stages with the fixed candidate.

Specific review questions:

1. Can any READY factory, original descriptor accepted before freeze, Timer callback or original summon job reach queue/counter/serial/actor side effects without sealed complete-world admission? Identify an executable counterexample if so.
2. Does consuming the original job ordinal before callbacks preserve legitimate old-life accepted work while rejecting copied jobs, replay and reentrant claims, without creating another issuance registry?
3. Can any old queue consumer, handler continuation, failure recovery or outer load pipeline mutate or publish the replacement world's state after generation takeover? The included RED reproduces an old consumer stealing the new shared queue; inspect the whole continuation chain.
4. Are immutable setup snapshots complete for actual behavior, appearance and drop consumers, and can a live config mutation bypass them?
5. Do the actual five-second startup failure and two-frame assertion require a production optimization, a contract-correct fixture migration, or both? They remain FAIL. Do not endorse relaxing deadlines or dropping actors to pass them.

Direct fixed-SHA native results: 11 scenes / 210 checks PASS; uncontended heavy mixed scenario 380 checks PASS. Overall related gate FAIL; missing historical empty-extension baseline remains MISSING. This request does not ask you to certify later DOT changes, the natural 35-second six-target failures, Android export or device behavior. Report assumptions, blocking findings with concrete chains, and scope-limited conclusions tied to this full SHA.
