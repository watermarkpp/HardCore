# Fixed admission-owner follow-up

BASE042e8a1b3fa44b4856fb87bc5f02aa6552a04edd; CANDec6466108a336081503c4d2148ebb61b3d9556d9. Actual24/24 native exits, three conditions each AA and AB/BA/AB, 600 callbacks. Independent exact verifier8/8 per condition PASS. Typed body owner correctness9/9 is separate from performance.

Small30 mean8.4592->8.5589ms, paired deltas -.0258/+.1190/+.2057ms, AA .1114. P99 28.25/35.44/29.05 ->34.40/30.07/31.80; >33 0/8/1->12/1/0; >50 zero all. Pets20 mean6.3052->6.3201ms, +.0322/+.0430/-.0307ms; AA .1574. P99 27.42/26.82/27.62->27.52/28.02/26.29; >33 0/1/0->0/0/0. AoE30 mean7.9107->8.2793ms, -.2066/+.2445/+1.0678; AA1.8406. P99 64.66/72.67/67.17->71.64/68.26/67.74; >50 10/10/10->10/10/13.

No sustained noise flag, but no consistent improvement. Do not use this larger AA noise to relabel the original72 warnings as PASS. AoE pair3 native physics calls16821->17181 and movement214602->707544us show real workload/scheduler variation; intervals include OS preemption. All unfavorable rows retained. Performance acceptance remains FAIL/open.

Next distinguish hot-path full diagnostic observer cost from actual default-OFF pacing, through the same native workload and a declared frame_only observation mode. Keep original R3 BASE1381, never replace it to hide regression. Frame-only cannot provide per-actor script CPU attribution; report those values NOT_RUN. Native HP/starts/pet damage/count remain required. GPU/device NOT_RUN.
