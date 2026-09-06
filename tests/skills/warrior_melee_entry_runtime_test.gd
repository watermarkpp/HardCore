extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")

## Production-entry coverage for the user-authorized warrior melee overrides:
## - no-target input never selects Fire Sword, while the existing normal
##   fallback still releases without consuming Fire charge/cooldown;
## - normal attacks from every profession reach a target at the 2 GU boundary
##   through GameRoot._on_player_attack, rather than only reading constants.


func _ready() -> void:
	_run_and_wait.call_deferred()


func _run_and_wait() -> void:
	await _run()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.learned_skills = {"烈火剑法": 3}
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				game.player.global_position + Vector2(3000.0, 3000.0),
				&"warrior_melee_entry_fixture_clear"
			)

	await _verify_fire_no_target_preserves_normal_fallback(game)
	var player_ground_for_target: Vector2 = game._canonical_screen_px_to_ground_gu(
		Vector2(game.player.global_position)
	)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(
		player_ground_for_target + Vector2(2.0, 0.0)
	)
	var target: EnemyActor = _make_enemy(
		game,
		target_position
	)
	await get_tree().process_frame
	# Spawn-time Bich safe-zone/overlap enforcement may relocate a fixture before
	# the first frame. Reinstall the canonical projected 2 GU endpoint after the
	# actor is ready, then freeze only this fixture's AI so the release snapshot
	# remains the measured 2 GU boundary.
	target.set_combat_position(target_position, &"warrior_melee_entry_fixture_2gu")
	target.set_physics_process(false)
	_verify_normal_two_gu_entry_for_all_professions(game, target)

	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"WARRIOR_MELEE_ENTRY_RUNTIME_PASS: Fire empty input rejected; "
		+ "normal GameRoot entry reaches 2 GU for warrior/wizard/taoist"
	)
	get_tree().quit(0)


func _verify_fire_no_target_preserves_normal_fallback(game: Node) -> void:
	PlayerState.profession = "战士"
	PlayerState.learned_skills = {"烈火剑法": 3}
	PlayerState.recalculate_stats()
	game.player.current_mp = 999
	game.player.fire_sword_enabled = false
	assert(game.player.request_skill("烈火剑法"), "Fire Sword toggle must use the production skill entry")
	assert(game.player.fire_sword_enabled, "Fire Sword toggle was not armed")
	# Seed a real active charge so the no-target path proves it does not consume
	# the charge while selecting the existing normal fallback.
	game._set_canonical_fire_charge_expires_at(Time.get_ticks_msec() + 10000)
	var charge_before: int = game._canonical_fire_charge_expires_ms
	var cooldown_before: int = game.player.skill_cooldown_remaining_ms(
		"warrior.fire_sword"
	)
	var preflight: Dictionary = game.player._build_warrior_attack_context(false)
	assert(
		str(preflight.get("mode", "")) == "normal"
			and str(preflight.get("selected_body_mode", "")) == "normal"
			and str(preflight.get("skill_id", "")) == "",
		"no-target Fire input must select normal fallback, never fire mode"
	)
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	var attack_signal_count: Array[int] = [0]
	game.player.attack_requested.connect(
		func(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
			attack_signal_count[0] += 1
	)
	var started: bool = game.player.request_attack(false)
	assert(started, "no-target Fire input must retain the existing normal fallback")
	assert(
		game.player.fire_sword_enabled,
		"normal fallback must not silently consume the Fire Sword toggle"
	)
	await get_tree().create_timer(game.player.attack_hit_windup + 0.05).timeout
	assert(attack_signal_count[0] == 1, "normal fallback did not reach production attack release")
	assert(
		game._canonical_fire_charge_expires_ms == charge_before,
		"no-target fallback consumed the active Fire charge"
	)
	assert(
		game.player.skill_cooldown_remaining_ms("warrior.fire_sword") == cooldown_before,
		"no-target fallback committed the Fire Sword cooldown"
	)
	game._set_canonical_fire_charge_expires_at(0)
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0


func _verify_normal_two_gu_entry_for_all_professions(
	game: Node,
	target: EnemyActor
) -> void:
	for profession: String in ["战士", "法师", "道士"]:
		PlayerState.profession = profession
		PlayerState.learned_skills = {}
		PlayerState.recalculate_stats()
		game.player.fire_sword_enabled = false
		game.player.thrusting_enabled = false
		game.player.half_moon_enabled = false
		target.current_hp = target.max_hp
		var origin: Vector2 = game.player.global_position
		var release_geometry: Dictionary = ReleaseGeometry.resolve(
			origin,
			Vector2.RIGHT,
			target.get_instance_id(),
			target.global_position,
			true,
			true,
			ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		)
		assert(
			bool(release_geometry.get("locked_target_valid_at_release", false)),
			"%s fixture did not create a valid release lock" % profession
		)
		game.locked_target = target
		game.magic_locked_target = target
		game._skill_cast_target = target
		game.player._pending_attack_context = {
			"mode": "normal",
			"selected_body_mode": "normal",
			"skill_name": "attack",
			"skill_level": 0,
			"direct_toggle_release": false,
			"release_geometry": release_geometry,
		}
		var hp_before := target.current_hp
		game._on_player_attack(origin, Vector2.RIGHT, 20)
		assert(
			target.current_hp < hp_before,
			"%s normal attack did not use the 2 GU GameRoot release entry" % profession
		)


func _make_enemy(game: Node, position: Vector2) -> EnemyActor:
	var enemy: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(38),
		position,
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_group_id": "warrior_melee_entry_target"}
	)
	assert(enemy != null, "2 GU normal-entry fixture enemy failed to spawn")
	enemy.max_hp = 1000
	enemy.current_hp = enemy.max_hp
	enemy.agility = 1
	enemy.control_time = 60.0
	return enemy
