extends Node

const Rules := preload("res://scripts/world_spatial_rules.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for frame in range(1200):
		await get_tree().process_frame
		if not game._world_bootstrap_in_progress and not game._map_transition_in_progress:
			break
	assert(game.gameplay_input_is_enabled())
	game.set_physics_process(false)
	game.auto_target_enabled = false
	# This fixture probes pickup scheduling and WORLD rays, not body sliding.
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			node.set_physics_process(false)
	var anchor: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	var desired: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
	game._set_player_world_position(anchor)
	assert(game._resolve_loot_ground_position(desired, anchor) == desired)
	var wall := _wall(game, (anchor + desired) * 0.5, Vector2(12, 64))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fixed: Vector2 = game._resolve_loot_ground_position(desired, anchor)
	assert(fixed.is_finite() and fixed != desired)
	assert(game._loot_ground_point_clear(fixed) and game._loot_world_segment_clear(anchor, fixed))
	assert(game._resolve_loot_ground_position(desired, anchor) == fixed, "retry location must not draw random numbers")
	var search: Dictionary = {}
	var resumed: Dictionary = {}
	var slices := 0
	while slices < 51:
		resumed = game._advance_loot_ground_position(
			desired, anchor, search, Time.get_ticks_usec() - 100000, 1, false
		)
		slices += 1
		if bool(resumed.get("complete", false)):
			break
	assert(bool(resumed.get("complete", false)) and resumed.get("position", Vector2.INF) == fixed)
	assert(slices > 1, "blocked placement must yield between collision candidates")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(game._spawn_gold_loot(30, desired, anchor))
	var pickup: LootPickup
	for child in game.get_children():
		if child is LootPickup and child.gold_amount == 30:
			pickup = child
	assert(is_instance_valid(pickup))
	wall = _wall(game, game._canonical_ground_gu_to_screen_px(Vector2(40.2, 13.5)), Vector2(4, 32))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gold_before: int = PlayerState.gold
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(39.9, 13.5)))
	assert(not game._loot_collection_path_is_clear(pickup))
	game._loot_pickup_runtime_manager.player_position_changed(game.player.global_position)
	game._flush_loot_collections()
	assert(PlayerState.gold == gold_before and is_instance_valid(pickup) and not pickup.collection_pending())
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(game._loot_collection_path_is_clear(pickup))
	game._loot_pickup_runtime_manager.player_position_changed(game.player.global_position)
	game._flush_loot_collections()
	assert(PlayerState.gold == gold_before + 30)
	await get_tree().process_frame
	assert(not is_instance_valid(pickup))
	await _test_frozen_equipment_pickup(game, desired)
	game.queue_free()
	await get_tree().process_frame
	print("LOOT_WORLD_PLACEMENT_INTEGRATION_PASS")
	get_tree().quit(0)

func _test_frozen_equipment_pickup(game: Node, position_px: Vector2) -> void:
	var catalog := GameData.get_item_record({"item_id": 80})
	var record := PlayerState.create_drop_item_instance({
		"item_id": 80, "canonical_item_id": 80, "output_item_id": 80,
		"item_name": str(catalog.name), "canonical_name": str(catalog.name),
		"output_record": catalog.duplicate(true), "identity_status": "resolved",
	}, "world-pickup-save-retry")
	assert(record.has("item_instance"))
	var frozen: Dictionary = record.item_instance.duplicate(true)
	assert(game._spawn_loot(str(catalog.name), position_px, record, position_px))
	var pickup: LootPickup
	for child in game.get_children():
		if child is LootPickup and child.item_id == 80:
			pickup = child
	assert(is_instance_valid(pickup))
	var before := PlayerState.inventory.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	game._loot_pickup_runtime_manager.player_position_changed(game.player.global_position)
	game._flush_loot_collections()
	PlayerState._test_force_atomic_write_failure = false
	assert(PlayerState.inventory == before and is_instance_valid(pickup))
	assert(pickup.item_record.item_instance == frozen and not pickup.collection_pending())
	# Invalid nested data must reach the receiver as invalid, never turn into a
	# legacy name-only pickup and silently generate a replacement instance.
	pickup.item_record["item_instance"] = null
	pickup.manager_advance_time(10.0)
	game._loot_pickup_runtime_manager.player_position_changed(game.player.global_position)
	game._flush_loot_collections()
	assert(PlayerState.inventory == before and is_instance_valid(pickup))
	pickup.item_record["item_instance"] = frozen.duplicate(true)
	pickup.manager_advance_time(10.0)
	game._loot_pickup_runtime_manager.player_position_changed(game.player.global_position)
	game._flush_loot_collections()
	var matches := 0
	for entry in PlayerState.inventory:
		if entry is Dictionary and str(entry.get("instance_id", "")) == str(frozen.instance_id):
			assert(entry == frozen)
			matches += 1
	assert(matches == 1, "formal ground pickup must preserve exactly one frozen instance")
	await get_tree().process_frame
	assert(not is_instance_valid(pickup))

func _wall(game: Node, position_px: Vector2, size_px: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = Rules.WORLD_LAYER
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size_px
	collider.shape = shape
	body.add_child(collider)
	game.add_child(body)
	body.global_position = position_px
	return body
