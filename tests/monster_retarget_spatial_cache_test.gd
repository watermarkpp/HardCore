extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const ENEMY_COUNT := 40
const SAMPLE_TICKS := 15

var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(50000.0, 50000.0)

	var enemies: Array[EnemyActor] = []
	for index in range(ENEMY_COUNT):
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(18), player, false)
		enemy.global_position = Vector2(float(index) * 80.0, 0.0)
		enemy.set_meta("spawn_position", enemy.global_position)
		enemy.set_meta("safe_zones", [])
		enemy.set_physics_process(false)
		add_child(enemy)
		enemies.append(enemy)
	await get_tree().process_frame

	# Model the observed idle background cadence. Every actor reaches a decision
	# tick, but one shared spatial broadphase walk serves the 250 ms window.
	EnemyActor.reset_performance_diagnostics()
	for _tick in range(SAMPLE_TICKS):
		for enemy: EnemyActor in enemies:
			enemy.target = null
			enemy._threat_table.clear()
			enemy._retarget_timer = 0.0
			enemy._retarget(0.25)
		await get_tree().process_frame
	var idle_metrics := EnemyActor.performance_diagnostics()
	assert(
		int(idle_metrics.retarget_full_scans) <= SAMPLE_TICKS,
		"idle actors rebuilt the full target group per actor: %s" % idle_metrics,
	)
	assert(
		int(idle_metrics.retarget_target_group_scans)
			== int(idle_metrics.retarget_full_scans),
		"retarget scan diagnostics diverged: %s" % idle_metrics,
	)
	assert(
		int(idle_metrics.retarget_target_candidates)
			== int(idle_metrics.retarget_target_group_scans),
		"idle target cache did not retain the single primary target: %s" % idle_metrics,
	)
	print("MONSTER_RETARGET_CACHE_STAGE idle %s" % idle_metrics)

	var probe: EnemyActor = enemies[0]
	probe.global_position = Vector2.ZERO
	probe.set_meta("spawn_position", Vector2.ZERO)
	# The primary target is checked live and must retain the exact 5-cell boundary.
	player.global_position = _ground_position_from_enemy(probe, Vector2(5.0, 0.0))
	probe.target = null
	probe._threat_table.clear()
	probe._retarget_timer = 0.0
	probe._retarget(1.0 / 60.0)
	assert(probe.target == player, "primary target entering 5 GU was not acquired")
	_checks += 1

	player.global_position = _ground_position_from_enemy(probe, Vector2(6.0, 0.0))
	probe.target = null
	probe._threat_table.clear()
	probe._retarget_timer = 0.0
	probe._retarget(0.0)
	assert(probe.target == null, "primary target at 6 GU bypassed the view boundary")
	_checks += 1

	# Existing target pursuit remains outside first-acquisition ViewRange when the
	# target is still inside the authored aggro radius.
	player.global_position = _ground_position_from_enemy(probe, Vector2(10.0, 0.0))
	probe.target = player
	probe._retarget_timer = 0.0
	probe._retarget(0.0)
	assert(probe.target == player, "existing target path was cleared by the broadphase")
	_checks += 1

	# Non-primary candidates at the Chebyshev diagonal boundary must survive the
	# conservative screen-space broadphase and the canonical exact filter.
	var diagonal_source := Node2D.new()
	add_child(diagonal_source)
	diagonal_source.add_to_group("combat_targets")
	player.global_position = Vector2(50000.0, 50000.0)
	diagonal_source.global_position = _ground_position_from_enemy(
		probe,
		Vector2(5.0, -5.0),
	)
	probe.target = null
	probe._threat_table.clear()
	probe._retarget_timer = 0.0
	probe._retarget(0.0)
	assert(
		probe.target == diagonal_source,
		"non-primary diagonal 5,-5 candidate was lost in the broadphase",
	)
	_checks += 1
	diagonal_source.queue_free()
	await get_tree().process_frame

	# A secondary target added after the shared walk is visible within the
	# bounded 250 ms refresh window; the known primary path is not delayed.
	EnemyActor.reset_performance_diagnostics()
	player.global_position = Vector2(50000.0, 50000.0)
	probe.target = null
	probe._threat_table.clear()
	probe._retarget_timer = 0.0
	probe._retarget(0.25)
	var late_source := Node2D.new()
	add_child(late_source)
	late_source.add_to_group("combat_targets")
	late_source.global_position = _ground_position_from_enemy(probe, Vector2(5.0, 0.0))
	probe.target = null
	probe._retarget_timer = 0.0
	probe._retarget(0.25)
	assert(probe.target == null, "secondary target bypassed the bounded refresh window")
	await get_tree().create_timer(0.27).timeout
	probe._retarget_timer = 0.0
	probe._retarget(0.25)
	assert(probe.target == late_source, "secondary target exceeded the 250 ms refresh bound")
	_checks += 2
	late_source.queue_free()
	await get_tree().process_frame

	# Threat handoff is immediate even when the attacker joins just after the
	# shared cache refresh.  The live target/threat entries are exact candidates,
	# so a near-distance retarget cannot clear the handoff before the next window.
	EnemyActor.reset_performance_diagnostics()
	player.global_position = Vector2(50000.0, 50000.0)
	probe.target = null
	probe._threat_table.clear()
	probe._retarget_timer = 0.0
	probe._retarget(0.25)
	var stale_threat_source := Node2D.new()
	add_child(stale_threat_source)
	stale_threat_source.add_to_group("combat_targets")
	stale_threat_source.global_position = _ground_position_from_enemy(
		probe,
		Vector2(11.0, 0.0),
	)
	probe._add_threat(stale_threat_source, 10.0)
	probe._retarget_timer = 0.0
	probe._retarget(0.18)
	assert(
		probe.target == stale_threat_source,
		"stale-cache threat handoff was cleared before refresh",
	)
	_checks += 1
	stale_threat_source.queue_free()
	await get_tree().process_frame

	# A non-primary combat target must still participate in threat retargeting.
	var threat_source := Node2D.new()
	add_child(threat_source)
	threat_source.add_to_group("combat_targets")
	threat_source.global_position = _ground_position_from_enemy(probe, Vector2(11.0, 0.0))
	probe.target = null
	probe._threat_table.clear()
	probe._add_threat(threat_source, 10.0)
	probe._retarget(0.0)
	assert(probe.target == threat_source, "threat target was lost in the spatial candidate query")
	_checks += 1

	# DATA_HOLD must remain fail-closed even when the primary target is on the
	# actor's current cell.
	var hold_enemy := EnemyActor.new()
	hold_enemy.setup(GameData.get_monster_by_id(228), player, false)
	hold_enemy.global_position = Vector2.ZERO
	hold_enemy.set_meta("spawn_position", Vector2.ZERO)
	hold_enemy.set_meta("safe_zones", [])
	hold_enemy.set_physics_process(false)
	add_child(hold_enemy)
	await get_tree().process_frame
	player.global_position = hold_enemy.global_position
	hold_enemy.target = null
	hold_enemy._threat_table.clear()
	hold_enemy._retarget_timer = 0.0
	hold_enemy._retarget(0.0)
	assert(hold_enemy.target == null, "DATA_HOLD target acquisition was not fail-closed")
	_checks += 1

	print("MONSTER_RETARGET_SPATIAL_CACHE_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _ground_position_from_enemy(enemy: EnemyActor, delta_ground_gu: Vector2) -> Vector2:
	return enemy.global_position + (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(delta_ground_gu)
	)
