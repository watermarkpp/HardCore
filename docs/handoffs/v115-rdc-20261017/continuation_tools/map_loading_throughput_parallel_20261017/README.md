# Map loading roundtrip diagnostic candidate

This is a one-file, default-off Source diagnostic candidate. It does not claim a
throughput fix or a completed World. Parent owns integration and actual World.

Production target: `scripts/gameplay/world/world_map_loading_transport.gd`.
The exact preimage is retained in `preimage/`; the complete candidate is in
`candidate/`; `map_loading_trace.patch` contains the minimal production diff.
Use the final SHA binding, rather than any earlier message's intermediate SHA.

The existing Source-published `hardcore/diagnostics/main_boot_trace` setting is
read through `world.clock_ports.get_setting` during existing owner configure.
No global ProjectSettings access is added on Source. False is the default.

Each exchange owns one bounded diagnostic dictionary of scalars and short text.
It is cleared on the original exchange return. No request, prefix, event, reply,
Resource or Source owner is retained in it. Status counter keys use nine fixed
known statuses plus OTHER; stage names are eleven fixed literals. There is no
history queue, timer, new wake, scheduling policy or gameplay budget.

The original Native reserve, prefix registration, Native accept, poll, budget
settle, Native settle and Native retire calls stay at their existing sites.
The original branch predicates, arguments and await sequence are preserved.
The retire bool is assigned once to a local so its actual result can be counted;
it still controls exactly the same branch. False remains labeled
`PENDING_OR_REJECTED`, since this bool API does not classify its cause.

`HC_SOURCE_MAP_EXCHANGE` is emitted after an existing observation when at least
five seconds elapsed, or once when the exchange returns. This is not a heartbeat:
if the coroutine never wakes, it emits nothing until the next existing call.
The parent's Main progress trace remains necessary to diagnose a lost wake.

The output includes operation/sequence/map/generation, original epoch and phase,
current stage, per-stage/status counts, first-stage epochs, and stage intervals.
`elapsed_<stage>_usec` is the interval between diagnostic stage observations,
including later calls, awaits and trace overhead. It is **not** an attribution
of exclusive Native function CPU. Current-stage duration is reported separately.

The first original argument and event Graph copies are timed without adding a
second Graph copy. Once the first event Graph copy succeeds, a single diagnostic
`var_to_bytes(request)` measures Godot Variant encoded size; its elapsed time is
separate. This size is **not Native mailbox wire size**. Encoding allocates a
temporary byte array which is not retained. Both trace encoding and output have
overhead, so use this run to locate waiting, not as a comparable performance
benchmark. No build, archive or other load should be overlapped with the next
actual World if performance comparisons are intended.

The first READY poll supplies actual Native queue residence, dispatch wait,
received timestamp, Source poll epoch, deadline classification and actual Main
reply started/finished/CPU values. Main elapsed and reply observation delay are
derived only from these existing actual timestamps. Native `status()` is called
only by the five-second/completion emitter, which copies eight scalar counters;
it is not called on every Source P retry and no full status graph is serialized.

## Current evidence and remaining gate

`STATIC_VALIDATION.json`: **29 checks, 0 failed**, Python native exit 0.
This is a static protocol projection, including six mutation negatives. It
removes exactly the declared diagnostic hunks and checks byte-equivalent original
logic, original external-call order/count and all await expressions. It checks
bounded trace state, one size-encoding site and protected production/index SHAs.
It executes no fake Host, simulated ACK, Godot or game fixture.

Exact executed command:

```powershell
python C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/map_loading_throughput_parallel_20261017/validate_static.py
```

Godot parser/actual trace: **NOT_RUN**. Actual World startup/normal exit:
**NOT_RUN for this candidate**. Root cause: **not yet proven**. The parent can
review/apply the patch after preimage verification, then run its existing
protected actual full-World fixture with the existing diagnostic flag. Do not
expand its exact authorized timeout, reduce the 56 descriptors/47 collision
items, alter clocks, or treat diagnostic summaries as game acceptance.

The earlier real trace showed the Map leaf had advanced through prepare,
resource request/poll and capture_environment into build_item. It also showed
32 unsettled published prefixes and 297 pending epochs. That supports sampling
publication/dispatch backlog separately from Main leaf cost; it does not prove
a specific budget, publication, Main or Graph-copy defect.

Native is unchanged: aggregate
`58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8`, manifest
`SOURCE_MANIFEST.map_reply_observation_20261017.json` SHA
`0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178`.
Parent actual console SHA
`1b69c0d26f54df88301791e5f3dbd43f7e20aad30a727addfff3287ea9d11c91`;
executing main SHA
`7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de`.
These are parent-provided actual build identities, not a new engine validation
by this diagnostic-only block. No Native, five sealed roles or engine files are
modified. SourceSave six-stage positive execution remains gated by a true World
and normal-exit PASS and is not run here.

## Protection

Only this new exclusive output directory was written. Production target remains
the exact captured preimage. The actual R index was read by absolute path and
remains `3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22`.
No Git command, repo initialization, Godot process or original-userdata operation
was performed. This statement is scoped to this block; the earlier chunk10 index
incident and parent's exact index-only recovery remain recorded in
`codex_resume_20261015_182255/index_incident_20261017`.
Frozen SourceSave tools and prior child deliveries are untouched.
