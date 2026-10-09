# Pursuit process budget source review

Review target: `scripts/monster_ai_package/decision_budget.gd` in the isolated
attack-frame worktree. This is a static review only; no engine, native, or
performance run was performed.

Reviewed source SHA256: `695F70EA19EDA984B27426617324F1A2B141ED9E94E6FFFC09EDF050C90F2775`.

## Current source status

The current worker revision addresses the previously observed source issues:

- `reset_pursuit_process_diagnostics()` now clears counters only.
- `reset_pursuit_process_state()` is a separate explicit teardown API and
  asserts that active and borrowed scopes are closed.
- An active owner reuses the existing outer lease rather than opening another
  FrameBudget scope.
- Pending pursuit work calls `FrameBudget.mark_pending()` under the real
  `monster_pursuit_process` category.
- A queued owner stores a set of pending kinds, so observation and new-step
  requests share age and are not overwritten by one another.
- Borrowed legacy tokens are handled by `end_pursuit_turn()` and do not close
  the outer FrameBudget scope.
- Direct `begin_pursuit_turn()` calls while an outer lease is active are
  rejected; explicit `borrow_pursuit_turn()` owns the nested namespace and
  enforces one token per nested kind and matching scope.

## Historical findings retained for traceability

The earlier review found four blockers in intermediate source revisions:

1. Diagnostic reset erased queue, active leases, and borrowed tokens.
2. An active owner could open a second outer process lease.
3. Pursuit admission did not mark the real FrameBudget category pending.
4. A second queued kind overwrote the first kind for the same owner.

Those findings are now historical observations against the earlier hashes, not
current runtime failures. The direct contract fixture exercises each corrected
boundary and also checks FIFO, scope invalidation, lifecycle pruning, optional
budget age, cancellation without refund, and necessary overrun isolation.

Status: `NOT_RUN`. No performance or release claim is made.
