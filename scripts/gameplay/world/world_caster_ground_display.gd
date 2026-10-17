extends "res://scripts/ground_effect.gd"

## Original visual proxy/installer/draw on Main; no duplicate ground ticks.
func _ready() -> void:
	super._ready()
	set_physics_process(false)

func _physics_process(_delta: float) -> void: pass
func _run_legacy_damage_tick() -> void:
	assert(false, "Main caster display cannot execute gameplay")
func claim_runtime_tick(_target: Node) -> bool:
	assert(false, "Main caster display cannot claim gameplay ticks")
	return false
