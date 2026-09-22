extends Node2D

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

class MagicTarget:
	extends Node2D

	var current_hp := 1000
	var _dying := false
	var _dead := false
	var poison_count := 0
	var control_count := 0

	func take_direct_spell_damage(_spell_id: String, raw_damage: int) -> Dictionary:
		var applied := maxi(0, raw_damage)
		current_hp = maxi(0, current_hp - applied)
		return {
			"applied_damage": applied,
			"magic_defense_checked": true,
			"physical_defense_bypassed": true,
		}

	func apply_poison(_damage: int, _seconds: float) -> void:
		poison_count += 1

	func apply_control(_seconds: float) -> void:
		control_count += 1


var _blocked_ground_gu := Vector2.INF


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	await _assert_flame_wooma_magic_melee()
	await _assert_touch_dragon_frozen_area_magic()
	print(
		"MONSTER_SPECIAL_DELIVERY_RUNTIME_PASS "
		+ "id70=adjacent_magic_wall_gate "
		+ "id124=strict_square_frozen_targets_no_los delay=0.6"
	)
	get_tree().quit(0)


func _assert_flame_wooma_magic_melee() -> void:
	var player := _make_player(Vector2(1.0, 0.0))
	var attacker := _make_attacker(70, player)
	await get_tree().process_frame
	attacker.global_position = Vector2.ZERO
	attacker.attack_min = 20
	attacker.attack_max = 20
	assert(attacker._uses_special_magic_melee_delivery())
	assert(is_equal_approx(attacker.attack_range_gu, 1.0))

	var hp_before := player.current_hp
	_blocked_ground_gu = Vector2(0.5, 0.0)
	attacker._deal_special_magic_melee_hit(player, 20)
	assert(player.current_hp == hp_before, "70 magic melee crossed a world blocker")

	_blocked_ground_gu = Vector2.INF
	attacker._deal_special_magic_melee_hit(player, 20)
	assert(player.current_hp < hp_before, "70 adjacent magic melee did not resolve immediately")
	assert(str(attacker.last_magic_attack_resolution.get("damage_channel", "")) == "magic_defense")
	assert(str(attacker.last_magic_attack_resolution.get("delivery_kind", "")) == "special_melee")
	assert(is_equal_approx(float(attacker.last_magic_attack_resolution.get("presentation_delay_seconds", 0.0)), 0.3))

	player.current_hp = hp_before
	player.global_position = _ground_to_screen(Vector2(1.01, 0.0))
	attacker._deal_special_magic_melee_hit(player, 20)
	assert(player.current_hp == hp_before, "70 special melee exceeded its one-GU boundary")

	attacker.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _assert_touch_dragon_frozen_area_magic() -> void:
	var primary := _make_player(Vector2(5.0, 5.0))
	var attacker := _make_attacker(124, primary)
	await get_tree().process_frame
	attacker.global_position = Vector2.ZERO
	attacker.attack_min = 30
	attacker.attack_max = 30
	attacker._attack_timer = 0.0
	assert(attacker._uses_area_magic_delivery())

	var second := _make_magic_target(Vector2(-5.0, -5.0))
	var boundary := _make_magic_target(Vector2(6.0, 0.0))
	var entrant := _make_magic_target(Vector2(7.0, 0.0))
	var primary_hp_before := primary.current_hp
	var second_hp_before := second.current_hp
	var boundary_hp_before := boundary.current_hp
	var entrant_hp_before := entrant.current_hp

	# Original Race107 has no CanFly/LOS check. A configured blocker therefore
	# must not alter the strict abs(x)<6 && abs(y)<6 frozen target set.
	_blocked_ground_gu = Vector2(2.5, 2.5)
	attacker._update_area_magic_delivery(0.0)
	assert(attacker._area_magic_release_records.size() == 2)
	assert(is_equal_approx(attacker._area_magic_warning, 0.6))
	assert(primary.current_hp == primary_hp_before)
	assert(second.current_hp == second_hp_before)

	primary.global_position = _ground_to_screen(Vector2(8.0, 8.0))
	second.global_position = _ground_to_screen(Vector2(-8.0, -8.0))
	entrant.global_position = _ground_to_screen(Vector2(1.0, 1.0))
	attacker._update_area_magic_delivery(0.61)
	assert(primary.current_hp < primary_hp_before, "124 lost its frozen primary target")
	assert(second.current_hp < second_hp_before, "124 lost its frozen secondary target")
	assert(boundary.current_hp == boundary_hp_before, "124 included the exclusive six-GU edge")
	assert(entrant.current_hp == entrant_hp_before, "124 hit a target entering after release")
	assert(attacker._area_magic_release_records.is_empty())
	assert(str(attacker.last_magic_attack_resolution.get("delivery_kind", "")) == "area_magic")

	_blocked_ground_gu = Vector2.INF
	attacker.queue_free()
	primary.queue_free()
	second.queue_free()
	boundary.queue_free()
	entrant.queue_free()
	await get_tree().process_frame


func _make_player(ground_gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(ground_gu)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	player.set_meta("runtime_map_id", 1)
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 999
	player.defense_max = 999
	return player


func _make_magic_target(ground_gu: Vector2) -> MagicTarget:
	var victim := MagicTarget.new()
	victim.global_position = _ground_to_screen(ground_gu)
	victim.set_meta("runtime_map_id", 1)
	victim.add_to_group("combat_targets")
	add_child(victim)
	return victim


func _make_attacker(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var attacker := EnemyActor.new()
	attacker.global_position = Vector2.ZERO
	attacker.setup(GameData.get_monster_by_id(monster_id), player, false)
	attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	attacker.environment_blocker = self
	attacker.process_mode = Node.PROCESS_MODE_DISABLED
	attacker.set_physics_process(false)
	add_child(attacker)
	return attacker


func is_environment_point_blocked(world_px: Vector2) -> bool:
	return (
		_blocked_ground_gu != Vector2.INF
		and world_px.distance_to(_ground_to_screen(_blocked_ground_gu)) <= 2.0
	)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)
