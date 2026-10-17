# Actual Pro decision: 300ms planning and one-thread congestion

User request: only monster collisions/paths on one background thread; can it finish within300ms while Main runs normally? This round official Pro was actually sent15:17:34, model Pro visible, formal reply completed and read. Request/response/screenshot/meta stored at outputs/v115_multicore/root_integration_20261014/PRO_CROWD_300MS_*.

This is a design response based on supplied exact source excerpts and reported component/phone evidence, not an independent complete-source performance audit. No new gameplay cadence, collision rate or delayed-result policy was adopted from the response.

## Current factual distinction

Owner decision interval defaults300ms in enemy_shared_state.gd. It suppresses rich observation/retarget/planning, and expressly excludes committed attacks/damage/motion/collision. Source movement cadence is another grant clock. Actual movement reads current collision inputs on physics steps. Thus existing frequency reduction is real; a complete long-window background preparation channel is not yet implemented.

## Single-thread arithmetic

If planning alone has an entire300ms CPU window, 30 monsters permit an absolute mean ceiling10ms per monster/decision; 40 permit7.5ms. These are arithmetic ceilings, not measured Honor costs. Required conditions also include worker queue/dispatch, instantaneous dynamic geometry, invalidation and repair, preparation, commit and CPU service competition. A100ms non-preemptible planning block can miss immediate geometry deadlines even if total work per300ms is small. Average stability cannot prove due deadlines or simultaneous activation peak.

Current114 phone mixed calm/crowd86s frameP95=150.198ms is frame spacing, not planning CPU. Native141/70/74us 24query geometry microbatch from10/30/40 fixture is not complete monster work. Do not substitute either into full300ms capacity.

## Construction decision

Preserve independent M presentation + unique S world/HP/physics + a bounded W pool. Give existing300ms owner gate a real preparation lane: immutable stable map values, already-known candidate/static numeric work ready before original consumers; current input-dependent selection still occurs at its original observation boundary. Dynamic geometry uses short rolling batches and live exact readset repair at original S consumption. Do not dispatch each predicate just before it consumes and call that full advance preparation.

Long tasks split at legitimate source progress points, short-deadline tasks receive scheduling priority. With p>=2 gameplay slots, long work should not occupy all p slots; actual instantaneous Godot pool contention still counts. Do not create one forever-running thread per10 monsters or shrink the entire global Godot pool to gameplay capacity. Pro recommends retaining a small pool and a provisional gameplay upper limit3; this is a recommendation, not current measured best hardware configuration. Component fixture requested4 tasks but happened to use3 worker threads. Production1/2/3/4 capability and configuration must be explicit and selected using full workload, not reported thread count alone.

Source inputs and candidate ordinal are authoritative; unchanged peer rows can be reused, changed rows repaired, membership changes restore original query/order. Do not reread a first sampled position at a different time just because a later radius read changed. Do not cache300ms old positions/collision truth. Invalid preparation does not authorize an extra rich retarget. Necessary already-dispatched work stays alive to true retirement; missing due outputs preserve real deadline failure, not fake-ready or silently next-period service.

## Forbidden shortcuts / acceptance

A single final position per300ms interpolated on M changes current collisions/reaction/attack observation; no authorization to implement it. Preparing18 future H candidates may be finite speculation, never18 future committed moves, and frequent dense changes may waste substantial work. No random phase shift or slowed first activation. M never joins path/geometry; rendering60fps cannot disguise accumulating S state age. Full S critical path, W completion/deadline, S prepare/repair/commit, memory/queue, M/GPU presentation and input service must be distinguished. Existing comparable PC recordings should be reused; missing exact cost columns remain MISSING. No repeated old microbenchmark requested.

Full115 world integration remains underway; no APK115 or device acceptance exists. Root active profile-state and source world numerical stages are not production evidence.
