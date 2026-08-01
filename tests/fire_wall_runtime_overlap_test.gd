extends Node

var _recorded_tick_powers: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var caster := Node2D.new()
	add_child(caster)
	var target := EnemyActor.new()
	target.max_hp = 999
	target.current_hp = 999
	target.monster_data = {"name": "fire-wall-overlap-target"}
	add_child(target)
	target.global_position = Vector2.ZERO
	target.add_to_group("enemies")
	target.set_physics_process(false)

	var first_field := _make_field(caster, 37)
	var overlapping_field := _make_field(caster, 91)
	add_child(first_field)
	add_child(overlapping_field)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert(
		_recorded_tick_powers.size() == 1,
		"one monster received multiple fire wall ticks from one caster in one interval"
	)
	assert(
		_recorded_tick_powers[0] in [37, 91],
		"overlap protection changed the canonical raw tick power"
	)
	assert(
		first_field.damage == 37 and overlapping_field.damage == 91,
		"overlap protection mutated either independent fire wall's damage"
	)

	await get_tree().create_timer(0.25).timeout
	assert(
		_recorded_tick_powers.size() == 1,
		"overlapping fire walls produced a sub-second extra tick"
	)
	await get_tree().create_timer(1.10).timeout
	assert(
		_recorded_tick_powers.size() == 2,
		"fire wall overlap protection did not preserve exactly one next tick: %s"
		% str(_recorded_tick_powers)
	)
	assert(
		_recorded_tick_powers[1] == _recorded_tick_powers[0],
		"the next legal fire wall tick changed the selected field's raw power"
	)
	print(
		"FIRE_WALL_RUNTIME_OVERLAP_PASS: independent overlapping fields preserve raw power while one caster deals at most one tick per target per second"
	)
	get_tree().quit(0)


func _make_field(caster: Node2D, raw_power: int) -> GroundSkillEffect:
	var field := GroundSkillEffect.new()
	field.setup(
		Vector2.ZERO,
		raw_power,
		74.0,
		3.0,
		Color.WHITE,
		"wizard.fire_wall",
		1.0
	)
	field.configure_runtime_resolution(
		caster,
		Callable(self, "_record_tick")
	)
	return field


func _record_tick(_target: EnemyActor, raw_power: int) -> void:
	_recorded_tick_powers.append(raw_power)
