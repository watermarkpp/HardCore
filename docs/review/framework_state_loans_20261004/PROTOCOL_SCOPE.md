# Returned origin state loans: scoped implementation and outstanding proof

Parent: `800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e`.

This increment covers already-supported finite direct/child chains. It does not open periodic facts or the periodic death-child compiler contract. The ordinary four-argument periodic HP route, RNG, duration, phase, historical credit, HP writer, planner and world factory remain unchanged.

## Storage invariant

For each accepted chain root r, reserve `N_r * S_r` state loans. Each distinct state has exactly one immutable origin r; refresh roots join `chain_owners` but do not take over its storage or original source/credit. While r exists:

`remaining origin loans + origin-owned handles = N_r * S_r`.

Allocation exchanges one reserved loan for one state. Stop removes the state and heap entry, returns that single loan to the still-existing origin, then retires presentation and all shared owners. A fully terminal root releases only its remaining promises. Its state owners and queued/producing branches prevent earlier retirement. Non-chain reservations retain their existing lifetime.

Old invalid life tails may remain within these paid loans until normal service. When accepted new-life work needs a loan and its pool is full, scan only that origin's handles and stop one whose ActorRef no longer resolves. Do not evict valid states, queued fatal facts, child branches or receipts. For a fixed legal world bound N and fixed persistent bindings S, a missing handle with all N*S origin loans occupied implies an invalid old tail: no more than N distinct qualified current lives can each carry S of the root's state types. Return that loan before materializing the replacement. This proof depends on the actual legal world/factory bound, not a count of the targets hit by one release.

Presentation stop can synchronously clear the runtime. Reclamation captures dispatch generation and rechecks it, the original reservation and target qualification after stop. An old command cannot use the returned loan after its owner has been retired. The native stop-port clear probe retains already-committed child HP, closes the outer public consumer and leaves state/heap/cue/loan/receipt ownership empty.

## Existing world bound and API boundary

Root collects the authored actor plan with `_collecting_staged_actor_plan` before materialization and READY (`game_root.gd` 3532 onward); `_spawn_enemy` declares every stable base slot while collecting (4985 onward). Editor/authored/outskirts producers enumerate their whole plan at world loading; the staged descriptor later materializes the same slots. Respawn reuses its declared slot. Current base guard forbids two unqueued bodies per slot; queued/dead ActorRef qualifications end immediately. The existing summon queue bounds combined live/reserved children by stable summoner slot, including owner replacement; nested summon lifetimes remain explicitly unproved/refused by WorldTargetBound. No extra quantity cap is introduced.

The Root native probe creates its three controlled test slots BEFORE acceptance. Its actual full world bound is85, not3. It uses actual Player acceptance/windup, original Root planner/release geometry, HP/fact capture and real child execution. Root process and AI are intentionally stopped and a private fact-consumption observation boundary is explicit. It is a controlled production API test, not natural combat or OS/UI end-to-end. Queued same-slot replacement after acceptance keeps the original bound and the child queries current lives. A separate two-allowance real-HP runtime unit forces the loan pool to fill and then reclaim an invalid old tail.

Private direct factory calls can add arbitrary NEW test base slots after acceptance. This increment does not claim an unlimited dynamic-authoring API or gameplay contract for them. Production world source paths above, declared replacement and finite summons are the covered bounds; future new spawn producers must enter the existing declaration contract and acceptance proof.

## Cumulative work is separate

Original `compile` and conservative `compile_serial_residency` contracts remain. The new cost records `total_state_creations` as the old F*S value, plus `state_residency=returned_origin_loans`; original geometric total facts/receipts, full child frontier, serial fact and receipt storage are preserved. Returning a state loan does not replenish `total_fact_space` or child quota. For N85/B1/G2/L2/S1, proof retains621435 facts,1242870 cumulative receipts,621435 potential creations and7310 children, while resident promises are170 facts/340 receipts/85 states. Exact and one-slot-short boundaries have native assertions.

Multi-root native refresh evidence covers A10, weak B1, stronger C20, original A source/credit, source destruction/withdrawal, one shared state and all three roots retained through terminal. These are ordinary periodic HP semantics; future periodic fact identities, refreshed cumulative tick grants and their child obligations are still outstanding. Never use this state storage result alone to open that producer.

## Counterexample boundaries

Original valid lifetime RED:28 checks/6 failures. Initial GREEN:29 checks, because a successful85 admission executes one additional loan-count assertion; no claim of identical check totals. The later clear probe adds checks without a separate old-byte RED. Early parse/registry/source-epoch attempts remain fixture FAIL and are not production cause evidence.

Actual Root parent control switches ONLY exact runtime and capacity-proof parent bytes, keeps the new Root test unchanged, then restores the candidate in finally. Actual bound85 yields `child_state_capacity`, complete9-check receipt/one FAIL, native exit1, stable control bytes. Candidate Root run proceeds through25 checks. This is not a full parent checkout, natural respawn or periodic-child proof.

## Audit corrections preserved

Pro800 full body was read at2026-10-04 08:05:59 UTC. Dot800 full independently authored outbound report body was directly read at08:19:07 UTC from its own original thread; original delivery FAIL and interrupted turn remain recorded. Both bodies support scoped prior two-fix closure. Dot repeated ambiguous authoring203 wording: local log and Pro verify203 is the TOTAL number of slots needing policy, not mapID203. Natural `ticks >= 360` means at least360 deliveries, not exactly360. Prior immutable reports/logs are retained as written; current interpretation is corrected here.

## Still open

Periodic fatal tick-to-child-to-ignite, cumulative refresh grants/unique tick identities, sustained fact/due child deadlines, worst atomic quantum, actual cue/audio/subeffect resource consumption, templates/generated combinations and full natural P6R3 remain work. Original map policy gate remains FAIL and exact original v97B input MISSING. Device/GPU/full power-loss matrix, source integration, APK/signature/installation acceptance are independent. Current shared ownership is not a total-memory or unlimited endurance proof.
