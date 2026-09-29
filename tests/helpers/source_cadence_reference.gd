extends RefCounted
## TEST ORACLE ONLY. NEVER preload this in a production script.
## Models the inspected source-family decision gate, including idle decisions.
var interval_ms: int
var walk_step: int
var wait_ms: int
var walk_tick_ms: int
var walk_count: int = 0
var wait_locked: bool = false
var wait_tick_ms: int = 0
var last_evaluated_ms: int = -1
var valid: bool = false

func configure(interval: int, step: int, wait: int, initial_tick: int = 0) -> bool:
    valid = interval >= 200 and step >= 1 and wait >= 0
    interval_ms = interval
    walk_step = step
    wait_ms = wait
    walk_tick_ms = initial_tick
    walk_count = 0
    wait_locked = false
    wait_tick_ms = initial_tick
    last_evaluated_ms = -1
    return valid

func postpone(delay_ms: int) -> bool:
    if not valid or delay_ms < 0:
        return false
    walk_tick_ms += delay_ms
    return true

func evaluate(now_ms: int, can_act: bool = true) -> bool:
    if not valid or now_ms < 0 or now_ms < last_evaluated_ms:
        valid = false
        return false
    if now_ms == last_evaluated_ms:
        return false
    last_evaluated_ms = now_ms
    if not can_act:
        return false
    if wait_locked:
        if now_ms - wait_tick_ms > wait_ms:
            wait_locked = false
        else:
            return false
    if now_ms - walk_tick_ms <= interval_ms:
        return false
    walk_tick_ms = now_ms
    walk_count += 1
    if walk_count > walk_step:
        walk_count = 0
        wait_locked = true
        wait_tick_ms = now_ms
    return true
