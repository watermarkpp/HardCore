class_name HCM30WalkPhase
extends RefCounted

## Pure phase math: EnemyActor owns movement, pending impact and cooldown.
## This helper never writes positions, velocities or damage.
## The visual adapter calibrates reference cycle length from the existing
## nominal GU speed and authored loop FPS/frame count. 1 GU is only the pure
## helper fallback, NOT a claim that every monster has the same physical stride.
## With a 1-GU reference, a half-GU step advances half a cycle; never catch up by time.
var cycle_gu: float = 1.0
var phase: float = 0.0
var total_ground_distance_gu: float = 0.0
var last_motion_tick: int = -1

func configure_cycle(distance_per_cycle_gu: float) -> void:
	if not is_finite(distance_per_cycle_gu) or distance_per_cycle_gu <= 0.000001:
		return
	cycle_gu = distance_per_cycle_gu
	phase = fposmod(total_ground_distance_gu / cycle_gu, 1.0)

func accept_distance(distance_gu: float, physics_tick: int) -> void:
	if not is_finite(distance_gu) or distance_gu <= 0.000001:
		return
	if not is_finite(cycle_gu) or cycle_gu <= 0.000001:
		return
	total_ground_distance_gu += distance_gu
	phase = fposmod(phase + distance_gu / cycle_gu, 1.0)
	last_motion_tick = physics_tick

func moving_on(physics_tick: int) -> bool:
	return last_motion_tick == physics_tick

func frame_index(frame_count: int) -> int:
	if frame_count <= 1:
		return 0
	return mini(frame_count - 1, int(floor(phase * float(frame_count))))

func interrupt_pose() -> void:
	# An attack/hit overrides the current pose, not the accumulated foot phase.
	last_motion_tick = -1

static func attack_clip_seconds(authored_seconds: float, interval_seconds: float, hit_delay_seconds: float) -> float:
	# Reserve a readable attack pose, including zero-delay impacts, and leave
	# a movement window inside the EXISTING attack cooldown. This only selects
	# presentation duration and movement phase; it does not change attack rate.
	var full_clip: float = maxf(authored_seconds, 0.62)
	var window: float = maxf(0.001, interval_seconds) * 0.60
	return maxf(maxf(0.0, hit_delay_seconds), minf(full_clip, window))

static func attack_movement_locked(attack_timer: float, cutoff: float) -> bool:
	return attack_timer > maxf(0.0, cutoff) + 0.000001
