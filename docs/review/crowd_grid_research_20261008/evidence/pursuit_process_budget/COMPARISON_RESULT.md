# Crowd AI frequency offline comparison

Date: 2026-10-09

Scope: retained `immediate_01` and `budgeted_01` artifacts only. No engine rerun or test was performed.

## Outcome

Enemy physics total fell from **2114.601 ms** to **1921.306 ms**, a computed reduction of **9.14%**. The requested >=50% target is **FAIL**. This is not equal-work proof: budgeted admission changes AI service, movement trajectory, attack starts, damage, and potion timing. The budget candidate is not integrated into MAIN.

## Comparison

| run | enemy CPU total | enemy CPU per-process p50/p95/p99/max ms | process interval p50/p95/p99/max ms | motion GU | total/window starts/settlements/completed | damage |
|---|---:|---|---|---:|---|---:|
| immediate_01 | 2114.601 | 6.826/8.923/9.651/12.138 | 16.592/18.727/20.131/21.062 | 2.639531 | 22/19/19/17 | 269 |
| budgeted_01 | 1921.306 | 6.310/7.520/8.324/11.819 | 16.655/17.845/19.032/20.555 | 4.075795 | 16/14/14/12 | 194 |

Nearest-rank p50/p95/p99 uses retained raw `enemy_cpu_by_process` and `process_samples` vectors. Whole-physics/process summary p99 remains `MISSING`; nested counters are not added together.

Both runs retain 34 active/formal actors, 30 engaged requested, 48 loot requested, 300 physics ticks, and 10,200 enemy physics calls. Motion was 2.639531 GU immediate versus 4.075795 GU budgeted. Total attack starts include three pre-window starts in each run; window admission counts are separate.

## Budget service scope

Budgeted observed `epoch_owner_max=1`, `reserved_owner_max=5`, `grants=291`, `budget_denied=2336`, `fifo_denied=14543`, queue peak `28`, maximum wait `2973119 µs / 177 processes`, and retained unserved queue entries up to `6510762 µs / 389 processes`. The service timeline has 256 entries and is truncated; no complete maximum claim is made. This is a product-service **FAIL** even though native exit was successful.

## Evidence scope

- Both native receipts: `PASS`, effective exit `0`, engine errors `0`.
- Both POST_RUN preload/source equality checks: `PASS`, 9,521 files, changed list empty; this is not gameplay/performance acceptance.
- Both raw diagnostic reports: `PASS`; attack runtime regression `NOT_RUN`; Android/GPU `NOT_RUN`.
- Potion schedules and INPUTS hashes differ and are retained in JSON; this prevents equal-work claims.
- Budgeted candidate remains `NOT_INTEGRATED` into MAIN.
