extends Node

## PERF-2: the broadphase expansion bound must shrink after the actor that
## held the maximum unregisters. The shrink is lazy (dirty flag, refreshed
## on the next query) and never over-shrinks: the recomputed maximum walks
## the live registered set, so every envelope stays conservative. Also
## covers the clear_map path and immediate re-growth on a new maximum.

const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 9201


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var index: RuntimeCombatSpatialIndex = (
		RuntimeCombatSpatialIndexScript.new()
	)
	# 0.3-radius crowd plus one 5.0-radius actor holding the maximum.
	var crowd: Array[EnemyActor] = []
	for actor_index: int in range(4):
		var enemy := _make_enemy(Vector2(10.0 + actor_index, 10.0))
		crowd.append(enemy)
		index.register(
			actor_index + 1,
			MAP_ID,
			enemy.global_position,
			0.3,
			actor_index + 1,
			enemy,
		)
	var big := _make_enemy(Vector2(60.0, 60.0))
	index.register(99, MAP_ID, big.global_position, 5.0, 99, big)
	assert(
		is_equal_approx(
			float(index.diagnostics()["max_actor_bounds_gu"]), 5.0
		),
		"registered maximum must be 5.0"
	)
	# Removing the max holder only marks the shrink dirty (lazy).
	index.unregister(99)
	assert(
		is_equal_approx(
			float(index.diagnostics()["max_actor_bounds_gu"]), 5.0
		),
		"shrink must stay lazy until the next query"
	)
	# The next query refreshes the bound to the live maximum.
	var found: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_ID, Rect2(Vector2(8.0, 8.0), Vector2(6.0, 6.0)), found
	)
	assert(
		is_equal_approx(
			float(index.diagnostics()["max_actor_bounds_gu"]), 0.3
		),
		"the next query must shrink the expansion to the live maximum"
	)
	assert(
		found.size() == 4,
		"small actors must still be found after the shrink"
	)
	# Registering a new maximum grows it immediately again.
	index.register(99, MAP_ID, big.global_position, 5.0, 99, big)
	assert(
		is_equal_approx(
			float(index.diagnostics()["max_actor_bounds_gu"]), 5.0
		),
		"a new maximum must apply immediately"
	)
	# Shrinking is safe: the envelope keeps covering every live actor.
	var wide: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_ID, Rect2(Vector2(0.0, 0.0), Vector2(20.0, 20.0)), wide
	)
	assert(
		wide.size() == 4,
		"the shrunk envelope must still cover the crowd"
	)
	# clear_map also shrinks lazily to zero.
	index.clear_map(MAP_ID)
	var drained: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_ID, Rect2(Vector2(-50.0, -50.0), Vector2(200.0, 200.0)), drained
	)
	assert(
		drained.is_empty()
		and is_equal_approx(
			float(index.diagnostics()["max_actor_bounds_gu"]), 0.0
		),
		"clear_map must shrink the expansion to zero on the next query"
	)
	for enemy: EnemyActor in crowd:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if is_instance_valid(big):
		big.queue_free()
	print("RUNTIME_COMBAT_SPATIAL_INDEX_MAX_BOUNDS_PASS")
	get_tree().quit(0)


func _make_enemy(position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.current_hp = 100
	enemy.max_hp = 100
	enemy.combat_radius_gu = 0.3
	enemy.global_position = position
	enemy._dying = false
	enemy._death_pending = false
	return enemy
