extends Node

## Diagnose the reported post-lightning pause using canonical actors and real
## physics time. No movement/attack clock is reset or advanced by the test.
## Far targets need a walk grant; nearby targets can attack while that grant
## remains postponed. The open terrain only removes unrelated map obstacles.
const CombatRuntime := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const GroundSpace := preload("res://scripts/ground_unit_space.gd")
const OpenTerrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")

var combat: Node
var observations: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _project(value: Vector2) -> Vector2:
	return GroundSpace.ground_delta_gu_to_screen_delta_px(value)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	combat = CombatRuntime.new()
	add_child(combat)
	for monster_id: int in [81, 89, 79]:
		await _observe(monster_id, 8.0)
	for monster_id: int in [81, 89]:
		await _observe(monster_id, 1.25)
	print("ZOMBIE_LIGHTNING_PURSUIT_TIMING_EVIDENCE=" + JSON.stringify(observations))
	print("ZOMBIE_LIGHTNING_PURSUIT_TIMING_PASS cases=%d" % observations.size())
	get_tree().quit(0)


func _observe(monster_id: int, distance_gu: float) -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000
	player.current_hp = 1000
	player.global_position = _project(OpenTerrain.CENTER_GROUND_GU + Vector2(distance_gu, 0.0))
	var enemy := EnemyActor.new()
	enemy.global_position = _project(OpenTerrain.CENTER_GROUND_GU)
	enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("safe_zones", [])
	enemy.configure_runtime_map_projection(1, _project, GroundSpace.screen_delta_px_to_ground_delta_gu)
	enemy.configure_terrain_navigation_context(OpenTerrain.build(1))
	add_child(enemy)
	var index := SpatialIndex.new()
	enemy.configure_spatial_index(index, 1)
	index.register(1, 1, OpenTerrain.CENTER_GROUND_GU, enemy.combat_radius_gu, 1, enemy)
	assert(enemy.combat_enabled and not enemy._movement_authority_failed_closed)
	var cadence: MonsterMovementCadence = enemy._movement_cadence
	var tick_before := cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	var hit_ms := Time.get_ticks_msec()
	var resolution: Dictionary = combat.apply_enemy_direct_spell_damage(
		enemy, "wizard.lightning", 20, player, null, Callable(), 9, {},
	)
	assert(bool(resolution.get("success", false)) and enemy.current_hp < hp_before)
	assert(enemy.control_time <= 0.0, "lightning must not create a control stun")
	var added_delay := cadence.walk_tick_ms - tick_before
	assert(added_delay >= 800 and added_delay <= 1799, "exactly one magic delay per delivery")
	var floor_ms := cadence.direct_magic_walk_floor_ms
	assert(floor_ms == tick_before + added_delay + cadence.walk_interval_ms)
	var origin := enemy.global_position
	var acquired_ms := -1
	var moved_ms := -1
	var attacked_ms := -1
	var deadline := floor_ms + 1000
	while Time.get_ticks_msec() <= deadline:
		await get_tree().process_frame
		var now_ms := Time.get_ticks_msec()
		if enemy.target == player and acquired_ms < 0:
			acquired_ms = now_ms
		if enemy.global_position.distance_to(origin) > 0.01 and moved_ms < 0:
			moved_ms = now_ms
		if enemy._hc_starts > 0 or enemy._pending_attack_time >= 0.0:
			if attacked_ms < 0:
				attacked_ms = now_ms
		if (distance_gu > 6.0 and moved_ms >= 0) or (distance_gu < 1.5 and attacked_ms >= 0):
			break
	var row := {
		"monster_id": monster_id, "distance_gu": distance_gu,
		"level": enemy.level, "walk_interval_ms": cadence.walk_interval_ms,
		"added_magic_delay_ms": added_delay, "walk_floor_after_hit_ms": floor_ms - hit_ms,
		"acquired_after_hit_ms": acquired_ms - hit_ms if acquired_ms >= 0 else -1,
		"moved_after_hit_ms": moved_ms - hit_ms if moved_ms >= 0 else -1,
		"attacked_after_hit_ms": attacked_ms - hit_ms if attacked_ms >= 0 else -1,
		"reason": enemy._hc_last_reason,
	}
	print("ZOMBIE_LIGHTNING_CASE=" + JSON.stringify(row))
	observations.append(row)
	assert(acquired_ms >= hit_ms and acquired_ms < floor_ms, "damage must acquire before walk delay expires")
	if distance_gu > 6.0:
		assert(moved_ms >= floor_ms, "far pursuit must respect the magic movement deadline")
		assert(moved_ms <= floor_ms + 250, "no extra long wait after the movement deadline")
	else:
		assert(attacked_ms >= hit_ms and attacked_ms < floor_ms, "nearby attack must not wait for movement")
	enemy.queue_free()
	player.queue_free()
	await get_tree().process_frame
