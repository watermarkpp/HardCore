extends RefCounted
## Pure outcome selection, NOT a second runtime timer. Feed the result of the
## owner's complete geometry/WORLD/frontline/target check, not just distance.
static func choose(target_valid: bool, gameplay_locked: bool, source_decision_granted: bool, access_clear: bool, hit_due: bool) -> StringName:
    if not target_valid:
        return &"NO_TARGET"
    if gameplay_locked:
        return &"ACTION_LOCKED"
    if not source_decision_granted:
        return &"CADENCE_WAIT"
    if access_clear:
        return &"ATTACK" if hit_due else &"COOLDOWN_HOLD"
    return &"PURSUE"

static func can_reserve_body_action(physics_tick: int, last_body_commit_tick: int, has_incompatible_pending_release: bool, gameplay_locked: bool) -> bool:
    ## Call BEFORE allocating release IDs, dealing damage or starting cooldowns.
    ## No read of rendering state. This prevents same-tick independent attacks;
    ## longer mutual exclusion comes from the source-class logical state only.
    return physics_tick >= 0 and physics_tick != last_body_commit_tick and not has_incompatible_pending_release and not gameplay_locked
