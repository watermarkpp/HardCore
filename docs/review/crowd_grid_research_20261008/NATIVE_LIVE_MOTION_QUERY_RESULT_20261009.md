# NATIVE_LIVE_MOTION_QUERY result (2026-10-09)

Performance: FAIL. Candidate retired. No integration, APK or device acceptance.

Fixed107 edae6fdef6a6551a951fab1ea8c6ade43359d603: 2057.2785ms median; goal <=1028.63925ms. Complete same workload retained: 34 alive /30 engaged /48 loot /300 real physics /10200 Enemy callbacks.

| Window | Enemy CPU ms | Moving ticks | Player travel GU | Native entries since setup | Cache hits since setup |
|---|---:|---:|---:|---:|---:|
| native_live_full01 | 2061.624 | 126 | 3.458751068 | 10745 | 31253 |
| native_live_full02 | 2070.613 | 123 | 3.343442160 | 10775 | 30870 |

Median 2066.1185ms is 0.429694% slower. Both complete native/runner results PASS with queue0/open0/maxwait1. This does not prove a gain; trajectories differ and do not identify a pure Object.get cost. Native statistics include setup: exact in-window native-query count MISSING, not fabricated. Unsupported owner/candidate legacy/projection miss/provider fallback/revalidation failure counts are all zero across the full superset, so the real workload did enter the native implementation. Original formal counters are in raw reports.

The actual execution replacement moved the live motion candidate loop and known exact-script cache/eligibility predicates into C++, with original counters called at original points. The host supplied real owner/endpoints/existing Array, not boolean answers or packed snapshots. Unknown owners return NIL before original effects; inherited candidates retain their real callees. No cadence, clock, Move, writer, target selection or budget change.

Direct green03 passed 118 checks with native exit0 and zero engine errors on source06/DLL c296ea4244c78ccfe8d0c75e104e98fca81b3655f33f5dd1f266b38e60f7c3be, the same final production/native source used by both full windows. This scope covers valid typed production fields and focused identity/cache/counter/fallback cases; it is not blanket proof of arbitrary destructive callbacks or candidate Array mutation. Those boundaries remain MISSING. The source/receipt binding is explicit in INPUTS and direct_result/raw reports; generic historic native_handoffs still has null source_content_sha256 and empty producers, retained as MISSING.

Failures retained: fixture parse errors in red01; hash-letter-case mismatch in red02; clean old-DLL API absence red03; namespace StringName initialization crash/DLL error1114 in green01; green02 printed a local PASS but runner FAIL for stock bool(String/Vector2) constructor errors. Generic Variant truthiness was incorrectly treated as explicit bool() conversion. Final source06 accepts BOOL/INT/FLOAT as stock does; valid floating tests replace those malformed fixture assumptions. This corrects fixture expectations to observed stock behavior without changing gameplay. Green02 is not promoted to PASS. New library load and bool-domain corrections justified their necessary reruns; no unchanged tests were repeated.

After archive, Enemy and all five production paths were restored exactstock107. Native .cpp/.h and dormant DLL restored to sealed task2 foundation. New fixtures remain dormant; no unknown dirty content removed. 50% goal remains active; this negative result does not support expanding the same direct-read mechanism or adding contexts as a rescue.

Archive: evidence/native_live_motion_query; final inventory SHA256 f9f855774f36dc30bac7f62632449534dd6dbae8e00969c5e4ee3b9d679309e1. Local outputs/crowd_native_live_motion_query_20261009/final_evidence. DEVICE TEST: NOT_RUN. CPU is not mobile FPS.
