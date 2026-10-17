extends RefCounted

## Original EnemyActor combat-clock/attack-admission state. Actor identity is
## supplied by its owner; this object's instance ID is never an actor ID.
const Timeline := preload("res://scripts/gameplay/actors/monster_action_timeline.gd")
var timeline := Timeline.new()
var time_s := 0.0
var logic_serial := 0
var logic_started_at_ms := 0
var action_start_time_s := -1.0
var action_duration_s := 0.0
var action_source_life := -1
var action_generation := -1
var action_active := false
var struck_paused_time_s := 0.0


## Returns the original completed-action notification at the exact write.
## The owner adapter performs its existing source176 diagnostic after this.
func advance_clock(delta: float) -> bool:
	time_s += delta
	if action_active and (time_s - action_start_time_s) >= action_duration_s:
		action_active = false
		return true
	return false


func allocate_attack(duration: float, source_life: int, generation: int, diagnostic_wall_ms: int) -> int:
	logic_serial += 1
	action_start_time_s = time_s
	action_duration_s = duration
	action_source_life = source_life
	action_generation = generation
	action_active = true
	logic_started_at_ms = diagnostic_wall_ms
	return logic_serial


func movement_time_ms() -> int:
	return int(maxf(0.0, time_s - struck_paused_time_s) * 1000.0)
