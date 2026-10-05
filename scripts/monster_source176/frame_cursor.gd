extends RefCounted
## Presentation observer only. Returns -1 outside [start, start+duration).
## No invented duration; missing metadata must be addressed by the caller.
static func frame_at(owner_time: float, started_at: float, duration: float, frame_count: int) -> int:
    if not is_finite(owner_time) or not is_finite(started_at) or not is_finite(duration):
        return -1
    if duration <= 0.0 or frame_count <= 0:
        return -1
    var age: float = owner_time - started_at
    if age < 0.0 or age >= duration:
        return -1
    return clampi(int(floor(age / duration * float(frame_count) + 0.000000001)), 0, frame_count - 1)
