extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const ORIGIN_GU := Vector2(38.5, 13.5)
const RAW_DAMAGE := 20

var _game: Node
var _targets: Dictionary = {}
var _secondary: EnemyActor
var _owned_targets: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.equipment.clear()
	# Exclude Basic/Slaying modifiers so 20 is the exact pre-defense DC.
	PlayerState.learned_skills = {"刺杀剑术": 3, "半月弯刀": 3, "烈火剑法": 3}
	PlayerState.recalculate_stats(false)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var deadline := Time.get_ticks_msec() + 10000
	while (
		(_game._world_bootstrap_in_progress or _game._map_transition_in_progress)
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	assert(_game.gameplay_input_is_enabled(), "physical defense fixture world never reached READY")
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.player.set_physics_process(false)
	_game.auto_target_enabled = false
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			var actor := node as EnemyActor
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.set_combat_position(
				_game.player.global_position + Vector2(4000.0, 4000.0),
				&"player_physical_defense_fixture_clear",
			)
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(ORIGIN_GU))
	for monster_id: int in [38, 39, 57]:
		_targets[monster_id] = _new_target(monster_id)
	_secondary = _new_target(39)
	await get_tree().physics_frame
	assert((_targets[38] as EnemyActor).defense == 0)
	assert((_targets[38] as EnemyActor).magic_defense == 0)
	assert((_targets[39] as EnemyActor).defense == 100)
	assert((_targets[39] as EnemyActor).magic_defense == 0)
	assert((_targets[57] as EnemyActor).defense == 0)
	assert((_targets[57] as EnemyActor).magic_defense == 100)

	_verify_normal_release_ac_and_mac()
	_verify_canonical_melee_modes()
	_verify_red_poison_and_expiry()
	_verify_direct_bypass_and_hit_boundaries()
	_verify_spell_consumer_unchanged()
	assert(PlayerState.test_mode, "non-test hit-boundary probe leaked its mode")
	_game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"PLAYER_PHYSICAL_DEFENSE_PRODUCTION_PASS: real normal/half-moon/fire/thrust "
		+ "AC once, second-segment bypass, red poison/expiry, hit boundaries, MAC parity"
	)
	get_tree().quit(0)


func _new_target(monster_id: int) -> EnemyActor:
	var target: EnemyActor = _game._spawn_enemy(
		GameData.get_monster_by_id(monster_id),
		_game._canonical_ground_gu_to_screen_px(ORIGIN_GU + Vector2(10.0, 10.0)),
		false, -1.0,
		{"respawn_enabled": false, "spawn_group_id": "player_physical_defense_contract"},
	)
	assert(target != null and target.monster_id == monster_id)
	assert(not target.get_meta("canonical_rejected", false))
	assert(target.max_hp > 120, "canonical fixture HP must survive raw120 probes")
	target.set_process(false)
	target.set_physics_process(false)
	_owned_targets.append(target)
	return target


func _verify_normal_release_ac_and_mac() -> void:
	var expected := {38: 20, 39: 1, 57: 20}
	for monster_id: int in [38, 39, 57]:
		var observed := _release(_targets[monster_id], "normal", RAW_DAMAGE)
		assert(
			int(observed.primary) == int(expected[monster_id]),
			"normal _on_player_attack ID%d raw20 expected%d got%d; AC must reach HP"
			% [monster_id, expected[monster_id], observed.primary],
		)
	var high_raw := _release(_targets[39], "normal", 120)
	assert(int(high_raw.primary) == 20, "normal raw120 minus AC100 must be applied exactly once")


func _verify_canonical_melee_modes() -> void:
	# These releases use the actual canonical mode resolver and target geometry.
	# Compare against zero-AC output to isolate AC from the existing body formula.
	for mode: String in ["half_moon", "fire"]:
		var zero_ac := _release(_targets[38], mode, RAW_DAMAGE)
		var high_ac := _release(_targets[39], mode, RAW_DAMAGE)
		var high_mac := _release(_targets[57], mode, RAW_DAMAGE)
		assert(int(zero_ac.primary) > 1, mode + ": canonical mode did not reach real HP")
		assert(int(high_ac.primary) == 1, mode + ": canonical AC100 must absorb this body hit to floor1")
		assert(int(high_mac.primary) == int(zero_ac.primary), mode + ": physical mode consumed MAC100")
	var arc := _release(_targets[38], "half_moon", RAW_DAMAGE, _secondary)
	assert(int(arc.secondary) == 1, "half-moon side target bypassed AC100")
	var thrust := _release(_targets[39], "thrust", RAW_DAMAGE, _secondary)
	assert(int(thrust.primary) == 1, "thrust first segment must consume canonical AC")
	assert(int(thrust.secondary) == 20, "rank3 thrust second segment must ignore AC100")
	var high_raw := _release(_targets[39], "thrust", 120, _secondary)
	assert(int(high_raw.primary) == 20, "thrust primary AC was subtracted twice")
	assert(int(high_raw.secondary) == 120, "thrust secondary lost its AC bypass")


func _verify_red_poison_and_expiry() -> void:
	var target := _targets[39] as EnemyActor
	_game._apply_canonical_poison(target, {
		"poison_type": "red_poison", "duration_seconds": 60.0,
		"flat_ac_reduction": 95, "flat_mac_reduction": 0,
	})
	assert(target.canonical_red_poison_active())
	assert(target.defense == 100, "red poison must not overwrite the canonical base AC cache")
	assert(int(_release(target, "normal", RAW_DAMAGE).primary) == 15, "normal hit ignored active red-poison AC95 reduction")
	assert(int(_release(target, "thrust", RAW_DAMAGE).primary) == 15, "thrust primary bypassed runtime red-poison AC reduction")
	var expired: Dictionary = target.get_meta("canonical_red_poison", {}).duplicate(true)
	expired["expires_at_ms"] = Time.get_ticks_msec() - 1
	target.set_meta("canonical_red_poison", expired)
	assert(int(_release(target, "normal", RAW_DAMAGE).primary) == 1, "expired red poison left stale AC reduction")
	assert(not target.has_meta("canonical_red_poison"), "physical consumer did not reclaim expired red-poison metadata")
	assert(target.defense == 100)
	_game._apply_canonical_poison(target, {
		"poison_type": "red_poison", "duration_seconds": 60.0,
		"flat_ac_reduction": 0, "flat_mac_reduction": 95,
	})
	assert(int(_release(target, "normal", RAW_DAMAGE).primary) == 1, "physical consumer confused MAC reduction with AC reduction")
	target.remove_meta("canonical_red_poison")


func _verify_direct_bypass_and_hit_boundaries() -> void:
	var armored := _targets[39] as EnemyActor
	armored.current_hp = armored.max_hp
	# Dynamic call keeps the RED fixture parseable before the new optional
	# argument exists. The earlier normal-AC assertion fails on the old code.
	var bypassed := bool(_game.call("_apply_physical_hit", armored, RAW_DAMAGE, 0, true))
	assert(bypassed and armored.max_hp - armored.current_hp == RAW_DAMAGE, "explicit ignore_ac=true did not bypass AC100")
	var target := _targets[38] as EnemyActor
	var checked_accuracy := 5
	assert(target.agility > checked_accuracy, "hit-boundary fixture requires agility > accuracy")
	var accuracy_bonus := checked_accuracy - int(PlayerState.computed_stats.get("accuracy", 0))
	for exact_roll: int in [checked_accuracy - 1, checked_accuracy]:
		target.current_hp = target.max_hp
		_game._rng.seed = _seed_for_exact_roll(target.agility, exact_roll)
		var isolated_mode := PlayerState.test_mode
		PlayerState.test_mode = false
		var hit := bool(_game._apply_physical_hit(target, RAW_DAMAGE, accuracy_bonus))
		PlayerState.test_mode = isolated_mode
		var expected_hit := exact_roll < checked_accuracy
		assert(hit == expected_hit, "physical hit must retain strict roll < accuracy boundary")
		assert(target.max_hp - target.current_hp == (RAW_DAMAGE if expected_hit else 0), "miss reached HP or hit did not commit exactly once")


func _verify_spell_consumer_unchanged() -> void:
	# Call the real shared spell commit used by GameRoot, with its MAC adapter;
	# do not substitute a mathematical helper or EnemyActor.take_damage stub.
	var expected := {38: 20, 39: 20, 57: 0}
	for monster_id: int in [38, 39, 57]:
		var target := _targets[monster_id] as EnemyActor
		target.current_hp = target.max_hp
		var stats: Dictionary = {}
		assert(target.direct_spell_runtime_stats_into(stats))
		assert(int(stats.get("anti_magic_points", -1)) == 0)
		var result: Dictionary = _game._combat_runtime.apply_enemy_direct_spell_damage(
			target, "wizard.fireball", RAW_DAMAGE, _game.player, _game._rng,
			Callable(_game, "_resolve_magic_defense"), 0,
		)
		assert(int(result.get("final_damage", -1)) == int(expected[monster_id]))
		assert(target.max_hp - target.current_hp == int(expected[monster_id]), "spell HP commit consumed AC or physical floor1")


func _release(
	primary: EnemyActor, mode: String, raw_damage: int,
	secondary: EnemyActor = null,
) -> Dictionary:
	for index: int in range(_owned_targets.size()):
		var target := _owned_targets[index]
		target.current_hp = target.max_hp
		target.set_combat_position(
			_game._canonical_ground_gu_to_screen_px(ORIGIN_GU + Vector2(20.0 + index * 2.0, 20.0)),
			&"player_physical_defense_park",
		)
	var origin: Vector2 = _game._canonical_ground_gu_to_screen_px(ORIGIN_GU)
	primary.set_combat_position(
		_game._canonical_ground_gu_to_screen_px(ORIGIN_GU + Vector2(1.1, 0.0)),
		&"player_physical_defense_primary",
	)
	if secondary != null:
		var offset := Vector2(2.1, 0.0) if mode == "thrust" else Vector2(0.8, 0.8)
		secondary.set_combat_position(
			_game._canonical_ground_gu_to_screen_px(ORIGIN_GU + offset),
			&"player_physical_defense_secondary",
		)
	_game.player.current_mp = 1000
	_game.player.fire_sword_enabled = mode == "fire"
	_game.player.thrusting_enabled = mode == "thrust"
	_game.player.half_moon_enabled = mode == "half_moon"
	_game._set_canonical_fire_charge_expires_at(0)
	_game.locked_target = primary
	_game.magic_locked_target = primary
	_game._skill_cast_target = primary
	var direction := origin.direction_to(primary.global_position)
	var geometry := ReleaseGeometry.resolve(
		origin, direction, primary.get_instance_id(), primary.global_position,
		true, true, ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION,
	)
	assert(bool(geometry.get("locked_target_valid_at_release", false)))
	_game.player._pending_attack_context = {
		"mode": mode, "selected_body_mode": mode,
		"direct_toggle_release": mode == "fire", "release_geometry": geometry,
	}
	_game._on_player_attack(origin, direction, raw_damage)
	return {
		"primary": primary.max_hp - primary.current_hp,
		"secondary": secondary.max_hp - secondary.current_hp if secondary != null else 0,
	}


func _seed_for_exact_roll(agility: int, exact_roll: int) -> int:
	var probe := RandomNumberGenerator.new()
	for candidate: int in range(1, 4097):
		probe.seed = candidate
		if probe.randi_range(0, agility - 1) == exact_roll:
			return candidate
	assert(false, "could not find deterministic physical-hit boundary seed")
	return 0
