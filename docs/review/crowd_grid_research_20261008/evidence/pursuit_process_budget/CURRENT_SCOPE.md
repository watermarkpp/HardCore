# Current bounded experiment scope

PURSUIT_PROCESS_BUDGET_AB supersedes the whole-foreground 10Hz draft for the first experiment. User authorizes lowering AI reaction/precision and checking less, while preserving architecture progress and avoiding long-frame regression. Pro13 was actually read and the controller selected a smaller separable planning cut.

The initial prototype defers only due observation and generation of new pursuit steps under one existing process FrameBudget. Existing earliest observation cadence stays unchanged for the first paired comparison. All existing active movement, collision integration, range/eligibility, attack submission, committed animation/damage, struck and cooldown timing remain on their existing owner path. No entire Enemy tick or melee tick is budget-gated. Planning scopes close before real movement advances.

CONTROL and PROCESS_BUDGET share the same accepted overlay code, real engine, original full diagnostics, formal34/30/48/300/10200 workload and moving-player/potion policy. The new policy changes service timing and may alter trajectories and attack output; those consequences are recorded, never labeled equivalent-work speedup. Process admission cap is at most five distinct owners across catchup physics callbacks, optional work cannot bypass exhausted budget with necessary retry, and queued identity work cannot rerun geometry in prune.

A running synchronous planning query is not preemptible. Record quantum/overrun and oldest unserved requests; do not claim a strict total-frame ceiling without further continuation work if one quantum remains too heavy. No missed AI decision debt or large-delta movement catchup may be introduced.

Earlier SOURCE_DESIGN.md and draft_pre_scope_reset contain an untested whole-foreground10Hz concept and partial code. They are NOT_RUN, not the current candidate. Production main remains untouched. No new test or performance result exists for this current scope yet. Full Pro text permanent export is MISSING; actual read metadata and controller interpretation are in docs/review/crowd_grid_research_20261008/PRO_RESPONSE_ROUND13_READ_RECEIPT_20261009.md.
