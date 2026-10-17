extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var errors: Array[String] = []
var releases: Array[Dictionary] = []
var skills: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _on_attack(origin: Vector2, direction: Vector2, damage: int, player: PlayerCharacter) -> void:
	releases.append({"origin": origin, "direction": direction, "damage": damage, "context": player.consume_attack_context()})

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var model: Object = player.domain_model
	check(model.has_method("step_physics") and model.has_method("request_attack_toward") and model.has_method("request_skill"), "all movement and accepted release gameplay lives in the non-Node model")
	if not model.has_method("step_physics") or not model.has_method("request_skill"):
		player.queue_free()
		await get_tree().process_frame
		_finish()
		return
	player.collision_mask = 0
	player.environment_blocker = null
	model.set_touch_vector(Vector2.RIGHT)
	model.step_physics(0.30)
	check(model.locomotion_state == "walk" and model.locomotion_distance_gu > 0.0 and model.locomotion_distance_gu < 1.0, "real body displacement begins with sub-GU walking")
	model.step_physics(0.35)
	check(model.locomotion_state == "run" and player.locomotion_state == "run", "one accepted GU advances the unique locomotion owner")
	check(player.actual_ground_motion_gu == model.actual_ground_motion_gu and player.facing == model.facing, "adapter pose-derived gameplay state forwards the model")
	model.set_touch_vector(Vector2.ZERO)
	model.step_physics(0.01)
	check(model.locomotion_state == "walk" and is_zero_approx(model.locomotion_distance_gu), "neutral input resets original locomotion progression")
	player.attack_requested.connect(_on_attack.bind(player))
	var target := Node2D.new()
	add_child(target)
	target.global_position = player.global_position + Vector2(100.0, 0.0)
	model.attack_hit_windup = 0.04
	model.attack_animation_duration = 0.06
	check(model.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "model accepts an ordinary attack through the real legacy ports")
	var expected_origin := player.global_position + Vector2(32.0, 0.0)
	player.global_position = expected_origin
	target.global_position += Vector2(0.0, 100.0)
	await get_tree().create_timer(0.10).timeout
	check(releases.size() == 1, "one accepted attack owns exactly one original P-tail release")
	if releases.size() == 1:
		check(releases[0].origin == expected_origin and releases[0].direction.is_equal_approx(Vector2.RIGHT), "release reads the current source pose while retaining the locked input axis")
		var release_id: String = releases[0].context.release_geometry.release_id
		check(release_id.begins_with("player:%d:action:" % player.get_instance_id()), "release identity uses the positive adapter actor ID, never the RefCounted ID")
	check(not model.has_pending_combat_release() and model.combat_action_snapshot().committed, "release closes its original producer and commits the shared body slot")
	model.step_physics(1.0)
	model.attack_hit_windup = 0.06
	check(model.request_attack(), "first overlapping release is accepted")
	model.combat_actions.attack_timer = 0.0
	model.combat_actions.action_timer = 0.0
	model.attack_hit_windup = 0.02
	check(model.request_attack(), "second body action is accepted while the first producer survives")
	await get_tree().create_timer(0.12).timeout
	check(releases.size() == 3 and not model.has_pending_combat_release(), "superseding the body slot preserves both accepted producers exactly once")
	PlayerState.set_profession_identity("hc.profession.wizard")
	PlayerState.learned_skills = {"hc.skill.wizard.fireball": 0}
	PlayerState.recalculate_stats(false)
	model.step_physics(1.0)
	model.current_mp = 100
	model.max_hp = 500
	model.current_hp = 500
	player.skill_requested.connect(func(skill: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void: skills.append(skill))
	check(model.request_skill("hc.skill.wizard.fireball"), "model accepts a real learned active skill through the original resource and timing rules")
	model.take_damage(15, true, {}, true)
	model.step_physics(1.0)
	check(model.struck_reaction_snapshot().queued and not model.combat_action_snapshot().committed, "physics catch-up cannot consume struck before the accepted process release")
	await get_tree().create_timer(1.0).timeout
	model.step_physics(0.001)
	check(skills.size() == 1 and not model.struck_reaction_snapshot().queued and model.struck_reaction_snapshot().reaction_lock_remaining > 0.0, "process release then first following owner step starts the queued reaction once")
	player.queue_free()
	target.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_player_full_model_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_PLAYER_FULL_MODEL_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
