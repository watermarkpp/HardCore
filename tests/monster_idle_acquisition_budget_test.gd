extends Node2D

const GU := preload("res://scripts/ground_unit_space.gd")

class ProbeEnemy extends EnemyActor:
	var safe_queries := 0
	var threat_queries := 0
	var los_queries := 0
	func _point_inside_safe_zone(point: Vector2, known_hc_cache := false) -> bool:
		safe_queries += 1
		return super._point_inside_safe_zone(point, known_hc_cache)
	func _threat_for(source: Node2D) -> float:
		threat_queries += 1
		return super._threat_for(source)
	func _initial_acquisition_static_los_clear(candidate: Node2D) -> bool:
		los_queries += 1
		return super._initial_acquisition_static_los_clear(candidate)
	func clear_counts() -> void:
		safe_queries = 0
		threat_queries = 0
		los_queries = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	# Keep the real spawn-overlap guard from moving the actor away from the
	# origin used by the exact boundary checks below.
	player.position = Vector2(50000, 50000)
	var enemy := ProbeEnemy.new()
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zone_context", {"valid": true, "zones": [], "revision": 1})
	add_child(enemy)
	assert(enemy.position == Vector2.ZERO)
	assert(enemy._target_acquisition_policy.view_range_cells == 5)
	enemy.target = null
	enemy._threat_table.clear()
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(30, 0))
	enemy.clear_counts()
	for index in range(100):
		enemy._retarget_timer = 0.0
		enemy._retarget(0.25)
		assert(enemy.target == null)
	print("IDLE_ACQUISITION_COUNTS safe=%d threat=%d los=%d" % [
		enemy.safe_queries, enemy.threat_queries, enemy.los_queries])
	assert(enemy.safe_queries == 0, "idle out-of-view targets must not trigger safe-zone queries")
	assert(enemy.threat_queries == 0, "an empty threat table must not be queried per idle candidate")
	assert(enemy.los_queries == 0)

	# Entering the exact square corner still acquires; there is no circular
	# approximation and no additional wakeup delay.
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(5, 5))
	enemy.clear_counts()
	enemy._retarget_timer = 0.0
	enemy._retarget(0.25)
	assert(enemy.target == player)
	assert(enemy.safe_queries > 0 and enemy.los_queries == 1)
	assert(enemy.threat_queries == 0)

	# Once engaged, the existing pursuit envelope remains authoritative.
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(10, 0))
	enemy._retarget_timer = 0.0
	enemy._retarget(0.25)
	assert(enemy.target == player, "existing pursuit must not be narrowed to idle ViewRange")

	# Receiving damage/threat while idle is an explicit wake event even when
	# the attacker is outside first-acquisition range, inside the real leash.
	enemy.target = null
	enemy._threat_table.clear()
	enemy._add_threat(player, 10.0)
	enemy.clear_counts()
	enemy._retarget_timer = 0.0
	enemy._retarget(0.25)
	assert(enemy.target == player and enemy.threat_queries > 0)

	# An in-range target still passes through the real safety authority.
	enemy.target = null
	enemy._threat_table.clear()
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(3, 0))
	var zones: Dictionary = enemy.get_meta("safe_zone_context")
	zones.zones.append({"shape": "circle", "center_ground_gu": Vector2(3, 0), "radius_gu": 1.0})
	zones.revision += 1
	enemy._retarget_timer = 0.0
	enemy._retarget(0.25)
	assert(enemy.target == null)
	zones.zones.clear()
	zones.revision += 1
	player._dead = true
	enemy._retarget_timer = 0.0
	enemy._retarget(0.25)
	assert(enemy.target == null, "range alone is not permission to target a dead player")
	player._dead = false

	# Drive the production timer wakeup too: it stays asleep when empty, then
	# acquires on the same scheduled wakeup when the player enters its range.
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(30, 0))
	enemy._enter_background_deep_sleep(false)
	enemy.clear_counts()
	enemy._retarget_timer = 0.0
	enemy._on_background_wakeup_timeout()
	assert(enemy._background_deep_sleeping and enemy.target == null)
	assert(enemy.safe_queries == 0 and enemy.threat_queries == 0 and enemy.los_queries == 0)
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(5, 0))
	enemy._retarget_timer = 0.0
	enemy._on_background_wakeup_timeout()
	assert(enemy.target == player and not enemy._background_deep_sleeping)
	enemy.free()
	player.free()
	print("MONSTER_IDLE_ACQUISITION_BUDGET_PASS")
	get_tree().quit(0)
