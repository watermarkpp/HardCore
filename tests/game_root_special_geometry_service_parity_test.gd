extends Node

## R1-B + PERF-1 parity evidence: the CombatTargetQueryService must produce
## the same candidate set as the direct index node queries the game_root
## special-geometry skills replaced (melee release plans, wizard cell-union
## plans, lightning sky strike, wild rush blocker segments). Three ways must
## agree on every randomized envelope:
##   1. the allocation-conscious fast path (query_envelope_into, the
##      production hot path since PERF-1) == the direct index node query;
##   2. the fast path == the record-based query() path intersected with the
##      legacy game_root live filter (dying / death-pending / queued / dead);
##   3. the default-epsilon envelope stays a superset of the epsilon-0 one.
## Randomized envelopes plus fixed boundary cases, seed-locked.

const CombatTargetQueryServiceScript := preload(
	"res://scripts/layers/runtime/combat_target_query_service.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const RUNTIME_MAP_ID := 9103
const LIVE_ACTOR_COUNT := 40
const RECT_QUERIES := 96
const SEGMENT_QUERIES := 48


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	var index: RuntimeCombatSpatialIndex = (
		RuntimeCombatSpatialIndexScript.new()
	)
	var actors: Array[EnemyActor] = []
	var actor_records: Array[Dictionary] = []
	for actor_index: int in range(LIVE_ACTOR_COUNT):
		var enemy := _make_enemy(
			Vector2(
				rng.randf_range(-10.0, 110.0),
				rng.randf_range(-10.0, 110.0)
			),
			rng.randf_range(0.05, 0.6)
		)
		actors.append(enemy)
		var runtime_id := actor_index + 1
		index.register(
			runtime_id,
			RUNTIME_MAP_ID,
			enemy.global_position,
			enemy.combat_radius_gu,
			runtime_id,
			enemy,
		)
		actor_records.append({
			"id": runtime_id,
			"enemy": enemy,
		})
	# Registered actors the live filter must drop exactly like the index
	# node query does.
	var dying := _make_enemy(Vector2(50.0, 50.0), 0.25)
	dying._dying = true
	dying.current_hp = 0
	index.register(901, RUNTIME_MAP_ID, dying.global_position, 0.25, 901, dying)
	var death_pending := _make_enemy(Vector2(51.0, 50.0), 0.25)
	death_pending._death_pending = true
	index.register(902, RUNTIME_MAP_ID, death_pending.global_position, 0.25, 902, death_pending)
	var dead := _make_enemy(Vector2(49.0, 50.0), 0.25)
	dead.current_hp = 0
	index.register(903, RUNTIME_MAP_ID, dead.global_position, 0.25, 903, dead)

	var service: CombatTargetQueryService = (
		CombatTargetQueryServiceScript.new(index, RUNTIME_MAP_ID)
	)

	for query_index: int in range(RECT_QUERIES):
		var bounds := _random_rect(rng)
		var service_ids := _service_ids_with_live_filter(
			service, {
				"shape": "aabb",
				"bounds_ground_gu": bounds,
				"broadphase_epsilon_gu": 0.0,
			}
		)
		var index_ids := _index_ids(index, RUNTIME_MAP_ID, bounds)
		assert(
			_ids_equal(service_ids, index_ids),
			"rect query #%d diverged: service=%s index=%s" % [
				query_index, str(service_ids), str(index_ids)
			]
		)
		# PERF-1: the production fast path must equal the direct node query
		# and the live-filtered record path on every envelope.
		var fast_ids := _fast_path_ids(service, bounds)
		assert(
			_ids_equal(fast_ids, index_ids)
			and _ids_equal(fast_ids, service_ids),
			"rect fast path #%d diverged: fast=%s record=%s index=%s" % [
				query_index, str(fast_ids), str(service_ids), str(index_ids)
			]
		)
		# The default-epsilon envelope stays a superset of the legacy one
		# on both the record path and the fast path.
		var epsilon_ids := _service_ids_with_live_filter(
			service,
			{
				"shape": "aabb",
				"bounds_ground_gu": bounds,
			}
		)
		var fast_epsilon_ids := _fast_path_ids(service, bounds, 0.05)
		for id: int in index_ids:
			assert(
				epsilon_ids.has(id) and fast_epsilon_ids.has(id),
				"default-epsilon envelope lost legacy candidate %d" % id
			)

	for query_index: int in range(SEGMENT_QUERIES):
		var start := Vector2(
			rng.randf_range(-5.0, 105.0), rng.randf_range(-5.0, 105.0)
		)
		var end := Vector2(
			rng.randf_range(-5.0, 105.0), rng.randf_range(-5.0, 105.0)
		)
		var expansion := rng.randf_range(0.0, 1.5)
		# Same envelope construction as the migrated game_root callers.
		var min_gu := Vector2(
			minf(start.x, end.x), minf(start.y, end.y)
		) - Vector2.ONE * expansion
		var max_gu := Vector2(
			maxf(start.x, end.x), maxf(start.y, end.y)
		) + Vector2.ONE * expansion
		var bounds := Rect2(min_gu, max_gu - min_gu)
		var service_ids := _service_ids_with_live_filter(
			service, {
				"shape": "aabb",
				"bounds_ground_gu": bounds,
				"broadphase_epsilon_gu": 0.0,
			}
		)
		var index_ids := _index_ids(index, RUNTIME_MAP_ID, bounds)
		assert(
			_ids_equal(service_ids, index_ids),
			"segment query #%d diverged: service=%s index=%s" % [
				query_index, str(service_ids), str(index_ids)
			]
		)
		var fast_ids := _fast_path_ids(service, bounds)
		assert(
			_ids_equal(fast_ids, index_ids)
			and _ids_equal(fast_ids, service_ids),
			"segment fast path #%d diverged: fast=%s record=%s index=%s" % [
				query_index, str(fast_ids), str(service_ids), str(index_ids)
			]
		)

	# Position transaction parity: a moved actor leaves the old envelope on
	# both paths and appears on neither until the move.
	index.update_actor(1, Vector2(200.0, 200.0))
	var moved_bounds := Rect2(
		actor_records[0]["enemy"].global_position - Vector2.ONE * 2.0,
		Vector2(4.0, 4.0)
	)
	var moved_instance_id: int = (
		(actor_records[0]["enemy"] as EnemyActor).get_instance_id()
	)
	var moved_service_ids := _fast_path_ids(service, moved_bounds)
	var moved_index_ids := _index_ids(index, RUNTIME_MAP_ID, moved_bounds)
	assert(
		not moved_service_ids.has(moved_instance_id)
		and not moved_index_ids.has(moved_instance_id),
		"moved actor stayed inside its old envelope on one path"
	)

	# Map clear parity: both paths must drain with the map.
	index.clear_map(RUNTIME_MAP_ID)
	var cleared_bounds := Rect2(Vector2(-50.0, -50.0), Vector2(200.0, 200.0))
	var cleared_service_ids := _fast_path_ids(service, cleared_bounds)
	var cleared_index_ids := _index_ids(index, RUNTIME_MAP_ID, cleared_bounds)
	assert(
		cleared_service_ids.is_empty() and cleared_index_ids.is_empty(),
		"map clear left stale candidates on one path"
	)

	# Fail-closed parity: an unusable map answers empty with a reason on
	# both the record path and the fast path.
	var broken_service: CombatTargetQueryService = (
		CombatTargetQueryServiceScript.new(index, -1)
	)
	assert(
		broken_service.query({
			"shape": "aabb",
			"bounds_ground_gu": Rect2(Vector2.ZERO, Vector2.ONE),
		}).is_empty()
		and broken_service.last_rejection_reason() != "",
		"unavailable map must fail closed with a reason"
	)
	var broken_nodes: Array = []
	assert(
		not broken_service.query_envelope_into(
			Rect2(Vector2.ZERO, Vector2.ONE), broken_nodes
		)
		and broken_nodes.is_empty()
		and broken_service.last_rejection_reason()
			== "runtime_map_unavailable",
		"unavailable map must fail closed on the fast path"
	)
	# Invalid envelopes fail closed on the fast path with the same reason
	# the record path's bounds gate uses.
	var invalid_nodes: Array = []
	assert(
		not service.query_envelope_into(
			Rect2(Vector2.ZERO, Vector2(-1.0, -1.0)), invalid_nodes
		)
		and invalid_nodes.is_empty()
		and service.last_rejection_reason() == "bounds_invalid",
		"invalid envelope must fail closed on the fast path"
	)

	for enemy: EnemyActor in actors:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for enemy: EnemyActor in [dying, death_pending, dead]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	print(
		"GAME_ROOT_SPECIAL_GEOMETRY_SERVICE_PARITY_PASS ",
		"rect=%d segment=%d fast_path=delegated" % [RECT_QUERIES, SEGMENT_QUERIES]
	)
	get_tree().quit(0)


func _make_enemy(position: Vector2, radius: float) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.current_hp = 100
	enemy.max_hp = 100
	enemy.combat_radius_gu = radius
	enemy.global_position = position
	enemy._dying = false
	enemy._death_pending = false
	return enemy


func _random_rect(rng: RandomNumberGenerator) -> Rect2:
	var center := Vector2(
		rng.randf_range(-5.0, 105.0), rng.randf_range(-5.0, 105.0)
	)
	var size := Vector2(
		rng.randf_range(0.0, 16.0), rng.randf_range(0.0, 16.0)
	)
	return Rect2(center - size * 0.5, size)


func _service_ids_with_live_filter(
	service: CombatTargetQueryService,
	request: Dictionary
) -> Dictionary:
	var ids: Dictionary = {}
	for record: Dictionary in service.query(request):
		var enemy: EnemyActor = record.get("node")
		# Live filter mirroring the legacy game_root record-path wrapper
		# (the index node query applies the same filter inline).
		if (
			is_instance_valid(enemy)
			and not enemy.is_queued_for_deletion()
			and not enemy._dying
			and not enemy._death_pending
			and enemy.current_hp > 0
		):
			ids[enemy.get_instance_id()] = true
	return ids


func _fast_path_ids(
	service: CombatTargetQueryService,
	bounds: Rect2,
	epsilon := 0.0
) -> Dictionary:
	var nodes: Array = []
	assert(
		service.query_envelope_into(bounds, nodes, true, epsilon),
		"fast path unexpectedly rejected a valid query"
	)
	var ids: Dictionary = {}
	for candidate: Variant in nodes:
		if candidate is EnemyActor:
			ids[(candidate as EnemyActor).get_instance_id()] = true
	return ids


func _index_ids(
	index: RuntimeCombatSpatialIndex,
	runtime_map_id: int,
	bounds: Rect2
) -> Dictionary:
	var candidates: Array = []
	index.query_enemy_nodes_aabb_into(runtime_map_id, bounds, candidates)
	var ids: Dictionary = {}
	for candidate: Variant in candidates:
		if candidate is EnemyActor:
			ids[(candidate as EnemyActor).get_instance_id()] = true
	return ids


func _ids_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a:
		if not b.has(key):
			return false
	return true
