# Pro resource boundary: request sent and formal reply received

2026-10-14 Asia/Shanghai. At 13:14, a new tab in the same Chrome profile restored control of the original conversation https://chatgpt.com/c/6acddd90-6e4c-83e9-86f0-a3932a895d6c . The composer visibly selected Pro. The actual request was sent and the completed 18m02s reply was read at 13:32-13:35. The old tab had a stale control attachment; account credentials were not copied.

Actual request and final reply are saved in `outputs/v115_multicore/root_integration_20261014/PRO_RESOURCE_REQUEST_SENT_20261014.txt` and `PRO_RESOURCE_REPLY_20261014.txt`, each with a PNG screenshot. This is a design decision based on the supplied call chain and its official ResourceLoader research, not an independent source audit of the new local implementation.

The formal recommendation is one S coordinator and budget ledger, M ordered real resource primitives, and reuse of confirmed stable binding facts. Cold status/request/get requires the true result at the original P/H call position. At-most-once transmission must retain the executed prefix, scope wall time includes the bridge once, and pursuit/AI admission cannot pass an unsettled resource scope. No unconditional per-epoch Main barrier or guessed old ready/null. Cold streaming may require every-P rendezvous; the protocol cannot honestly promise this waiting is always rare. Deadline failures remain failures and preserve accepted obligations.

The resource worker has been given the saved formal result. A narrow native status observation entry using the S process epoch is still to implement and verify. Full S assembly, heavy W kernels, Main projection and Android delivery remain open.

## Concrete design question

M owns rendering Nodes, textures and actual visual resources. S owns sole HP, combat action timelines and simulation clock; W uses immutable numeric data. Real external-owner physics and original timer/clock foundation have native evidence. Full production S assembly and W heavy gameplay kernels remain open.

During extraction of original MonsterVisual, 81 of its 97 methods form numeric behavior. These are not all optional cosmetics: Enemy death uses `visible && sprite != null && sprite.texture != null` to choose final-art completion, active resource death frame_count sets duration, and profile readiness and struck queue feed the sole `combat_actions.timeline`. Captured readiness must reflect the real original resource outcome. Neither empty/ready defaults nor an extra H delay is allowed.

The original streaming coordinator's `request_visual_resources` both reads readiness and mutates reservation, lease and eviction state. Repeating it during speculative preview or replay would change policy. The original Main coordinator also charges the same FrameBudget whose owner-local instance is now required by S navigation and decisions. Independent M/S copies would split one original global budget and give extra work.

Please review this narrow boundary and choose an implementable design: preferably move the coordinator's numeric scheduling/lease/eviction authority and shared budget to S, while M executes the exact resource primitives. Specify actual command/reply admission points, resource identity/lifetime, at-most-once operations, visibility/availability qualification and shared budget accounting. Explain whether exact same-phase outcomes can be preserved without coupling every S epoch to M render frames or blocking the display thread. If exact preservation requires a bounded rendezvous for rare resource operations, identify precisely which operations, its deadlines and how it coexists with uninterrupted CPU-heavy simulation; do not recommend synchronous M calls for every actor/epoch.

Keep actual readiness and source hot/cold behavior, one timeline, original scheduler/budget amounts and all cache/eviction limits. A resource primitive result must never be guessed, and failure must retain accepted obligations. If the current exact-phase requirement is internally impossible with independent clocks, state the conflict explicitly and identify the smallest actual gameplay contract affected. This is a design decision request, not a claim that you have audited new local source.

Relevant local fixed deliveries: `outputs/v115_multicore/enemy_owner_services_20261014/batch03/ABI.md`, SOURCE_MAP and SOURCE_DEPENDENCIES; production `scripts/monster_visual.gd` and the original streaming coordinator. The batch01 shared-budget and batch02 path-service deliveries are separately frozen.
