extends Node

## R4 T3-A wide-phase bucket-boundary counterexample: a REAL 0.5GU large
## body whose center sits near a bucket boundary must be found by a formal
## narrow query whose AABB/segment lies in the NEIGHBORING bucket and only
## touches the actor through its true radius (0.4GU from center: inside the
## true 0.5GU body, outside the stale 0.353GU default-derived radius). A
## shrunken registration radius MUST miss this query - verified through an
## isolated index instance fed the stale value, so the criterion itself is
## proven discriminating without touching production code.

const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")

const STALE_SMALL_RADIUS := 0.353553390593274


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline_boot: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline_boot:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	var map_id: int = int(game.get("current_map_id"))
	var index: RuntimeCombatSpatialIndex = game._combat_spatial_index
	var bucket: float = index.bucket_size_gu()
	assert(bucket > 0.0, "fixture needs a real bucket size")

	# Place the large actor right next to a bucket boundary in ground GU.
	var boundary := floorf(40.5 / bucket) * bucket
	var actor_ground := Vector2(boundary - 0.1, 13.5)
	var actor_screen: Vector2 = game._canonical_ground_gu_to_screen_px(actor_ground)
	var boss: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(76),
		actor_screen,
		true,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:r4-radius-boundary"},
	)
	assert(boss != null and boss.combat_radius_gu > STALE_SMALL_RADIUS + 0.05, "fixture needs a large body with its true radius")
	var true_radius: float = boss.combat_radius_gu
	var runtime_id: int = boss.spatial_actor_runtime_id

	# Probe AABB fully inside the NEIGHBORING bucket, its near edge at the
	# bucket boundary. The index visits exactly the buckets covered by the
	# query box expanded by _max_actor_bounds_gu, then collects the actors
	# whose CENTER lies in that expanded box:
	# - stale 0.353 registration expands to 0.403GU short of the probe edge
	#   (probe near edge = 0.40GU from center: 0.10 to boundary + 0.05 half
	#   + 0.353 expansion > 0.5 needed) -> the actor's bucket is never
	#   visited -> MISS;
	# - true 0.5 registration expands past it -> actor center inside the
	#   expanded box -> HIT.
	# The probe is 0.50GU from the actor center: separation margin ~0.10GU
	# on the stale side and 0.05GU on the true side.
	# The probe AABB (0.1GU wide) sits fully inside the NEIGHBORING bucket.
	# The index visits the buckets covered by the box expanded by
	# _max_actor_bounds_gu (quantized at the 4GU bucket granularity):
	# - stale 0.353 registration: box near edge 40.38 - 0.353 = 40.027 still
	#   quantizes INTO the neighbor bucket (bucket key 10), so the actor's
	#   bucket (key 9, containing 39.9) is never visited -> MISS;
	# - true 0.5 registration: 40.38 - 0.5 = 39.88 quantizes back into the
	#   actor's bucket (key 9) -> actor center collected -> HIT.
	# probe = boundary + 0.43, half extent 0.05: separation margin ~0.03GU
	# from the stale bucket quantization edge on one side and ~0.02GU inside
	# the true reach on the other.
	var probe_ground := Vector2(boundary + 0.43, 13.5)
	var probe_distance: float = probe_ground.distance_to(actor_ground)
	# True radius must reach far enough to re-quantize into the actor's
	# bucket; the stale radius must not.
	assert(
		probe_ground.x - 0.05 - STALE_SMALL_RADIUS >= boundary
			and probe_ground.x - 0.05 - true_radius < boundary,
		"fixture probe must discriminate stale vs true registration radius",
	)
	var probe_aabb := Rect2(probe_ground - Vector2(0.05, 0.05), Vector2(0.1, 0.1))

	# --- Formal index must contain the large actor ---
	var found: Array = []
	index.query_enemy_nodes_aabb_into(map_id, probe_aabb, found)
	var found_ids: Array = []
	for entry: Variant in found:
		if entry is Dictionary:
			found_ids.append(int(entry.get("actor_runtime_id", entry.get("runtime_id", -1))))
		elif entry is Node:
			found_ids.append(int((entry as Node).get("spatial_actor_runtime_id")))
	var aabb_ok: bool = found_ids.has(runtime_id)

	# Segment (thin line) counterexample through the same probe point.
	var seg_found: Array = []
	index.query_enemy_nodes_segment_into(map_id, probe_ground, probe_ground + Vector2(0.0, 0.02), 0.0, seg_found)
	var seg_ok: bool = false
	for entry: Variant in seg_found:
		if entry is Node and int((entry as Node).get("spatial_actor_runtime_id")) == runtime_id:
			seg_ok = true

	# --- Fault variant: the stale shrunken radius must MISS the same query.
	var stale_index: RuntimeCombatSpatialIndex = SpatialIndexScript.new()
	stale_index.register(
		990001,
		map_id,
		actor_ground,
		STALE_SMALL_RADIUS,
		990001,
		boss,
		Callable(boss, "spatial_index_position"),
	)
	var stale_found: Array = []
	stale_index.query_enemy_nodes_aabb_into(map_id, probe_aabb, stale_found)
	var stale_hit: bool = not stale_found.is_empty()
	stale_index.unregister(990001)

	var valid: bool = aabb_ok and seg_ok and not stale_hit
	if boss != null:
		boss.queue_free()
	game.queue_free()
	if not valid:
		printerr(
			"R4_RADIUS_BUCKET_FAIL: aabb_ok=%s seg_ok=%s stale_variant_hit=%s true_radius=%.6f probe_distance=%.3f" % [
				aabb_ok, seg_ok, stale_hit, true_radius, probe_distance,
			]
		)
		get_tree().quit(1)
		return
	print("R4_RADIUS_BUCKET_BOUNDARY_PASS: true_radius=%.6f probe_distance=%.3f stale variant missed as required" % [true_radius, probe_distance])
	get_tree().quit(0)
