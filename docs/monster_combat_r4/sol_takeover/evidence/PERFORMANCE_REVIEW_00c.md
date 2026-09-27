# Fixed R4 00c performance review (controller)

Source: BASE 1381d2838a3736f4a06699dd24a8cf4a10714950; CAND 00c189b538cc2873f5420f0a3493939f570f5ef2. Raw: t6_pairs_final_v5. 72/72 actual native exits; no dropped/filtered runs. Full critical 525 at 3b21 (production unchanged through 00c), independent clean 103 at 00c; exact-set checker PASS. Protection: 13611 files, 6 approved changes, no unexpected change/missing file; user AGENTS byte-preserved.

## Acceptance

**Performance acceptance: FAIL (not closed).** Successful collection is not evidence of zero regression. Eight of nine conditions have no sustained three-pair mean CPU increase above the fixed A/A noise rule. The AoE/death/loot N10 condition has three increases: 0.015233, 0.069612, 0.022818 ms; A/A noise 0.012797 ms. BASE mean 1.468007 ms, CAND 1.503894 ms. This gate remains open; no performance PASS or device/GPU claim.

## Trace so far

For N10 pairs 1/2/3 inclusive enemy usec deltas are +9140/+41767/+13691 over 600 callbacks. Actual enemy physics calls are BASE 5361/5363/5369, CAND 5390/5404/5390; foreground ticks +28/+40/+20. Attack starts 15 -> 16 in all three pairs; LOS evaluations +64/+55/+62, LOS usec +1585/+3247/+1544. Crowd candidates decrease 260 -> 250; no terrain path calls in either tree. Projection, retarget, safe-zone and movement timing deltas are retained in raw counters. Native death counts and work schedule also differ; native clocks/RNG were not reset to fabricate equal counts. This identifies changed effective work as one contributor; it does not explain or excuse the entire residual CPU delta.

N10 callback P99 improves in pairs 1/2 and increases in pair3; >33 ms counts 10 vs10 in each; >50 ms BASE3/3/5 versusCAND3/2/4. Small N30 tail risk remains: >33 ms BASE0/0/0 vsCAND3/6/0; no >50 ms. Other group raw P95/P99 and workload counts are in summary.json; engine monitor values are not per-frame percentiles.

## Next

Continue actual call-chain/phase attribution at the fixed input boundaries and compare after F03/F05. Do not mutate old raw evidence. F03 narrow RED now demonstrates full-table synchronous journal/checkpoint cost; this is a separate confirmed defect, not a retroactive explanation of the above actor-only inclusive CPU metric. F03/F05, portals, forge and final fixed-source gates remain mandatory before push/cleanup. APK is NOT_RUN by latest user stop-before-package instruction.
