extends RefCounted

## Test-owned observation only. No time, damage, admission or scheduler writes.
const CAPACITY := 8192
var samples := PackedInt64Array()
var last_usec := 0
var overflowed := false

func begin() -> void:
    last_usec = Time.get_ticks_usec()

func record_frame() -> void:
    var now := Time.get_ticks_usec()
    if samples.size() / 2 >= CAPACITY:
        overflowed = true
    else:
        samples.append(now)
        samples.append(now - last_usec)
    last_usec = now

func snapshot() -> Dictionary:
    return {"schema":"test.physics_frame_intervals.v1", "capacity":CAPACITY,
        "overflowed":overflowed, "pairs_engine_usec_interval_usec":samples,
        "scope":"combat sampling only; wall interval, not CPU/GPU duration"}
