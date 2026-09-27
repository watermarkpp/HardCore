# Fixed F03/F05 matrix at 9e7c2cb (controller review)

BASE 1381d2838a3736f4a06699dd24a8cf4a10714950; CAND 9e7c2cb22d6d562a1f95221ef4f6bf5e35f18eb4. `t6_f03_full` contains all 72 native samples, each 600 paired callbacks, normal runner exits and real initialized profile/journal transactions. Source remained unchanged throughout. Actual collector exited 0 and printed matrix completion; summary PASS means collection, not performance acceptance.

## Current performance acceptance: FAIL / unresolved

Two three-pair mean warnings remain: small30 (+0.386/+0.032/+0.649 ms, A/A noise .0171 ms) and large_pets20 (+.365/+.078/+.208 ms, A/A noise .0294 ms). Small30 also has one candidate sample with 18,510 enemy calls vs 18,000 BASE, P99 38.67 vs31.60 ms, and 17 vs1 callbacks over33.33 ms. Other two small30 tails improve. All raw samples are retained, including these unfavorable samples. AoE30 mean CPU is also higher despite no sustained noise flag, so that condition is not silently accepted by the warning heuristic.

AoE10 P99 improves in all pairs: BASE35.81/33.80/41.46 -> CAND29.93/26.73/27.19 ms; >50ms BASE3/3/4 -> CAND0/0/0. AoE20 P99 BASE63.58/58.42/71.45 -> CAND56.77/52.23/54.79. AoE30 P99 BASE84.91/87.30/82.17 -> CAND72.72/68.21/65.28. The real death-settlement aggregate for AoE30 changes BASE508/513/503 -> CAND97/93/96 ms; native drop planning remains main-thread work. These are improvements, not a claim that all long frames disappeared.

Inclusive enemy segments use elapsed wall time, which includes preemption; they are not OS thread CPU clocks. Phase counters overlap and must not be added into a fictitious total. Native allocation-dependent staggering, attacks, movement and pending settlement differ across versions. Neither clocks/cooldowns nor runtime IDs were reset to manufacture identical work. `controller_phase_trace.json` retains these inputs, actual counts and queues. Native lifecycle tests independently cover receipt consumption on map changes and exit; a sample-end queue is not dropped work.

Next: finish current-source direct R4 regression, verify the body-admission hot-query candidate with a real failure, then narrow paired follow-up before integration. Original 00c FAIL remains preserved. Forge merge, final full critical/clean check, remote push and cleanup remain NOT_RUN. GPU and device NOT_RUN; APK is intentionally NOT_RUN by the user's stop-before-packaging boundary.
