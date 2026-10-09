extends Node

const FormalReady := preload("res://tests/helpers/formal_world_skill_fixture.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await FormalReady.wait_for_formal_world(self, game, "accepted_loot")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	PlayerState.set_process(false)
	var directory := "user://loot_accepted_movement_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.active_profile_id = "accepted"
	PlayerState.test_mode = false
	PlayerState.gold = 0
	assert(PlayerState.save_game(false))
	game.hud.loot_feedback_layer.set_process(false)
	game.hud.loot_feedback_layer.clear_feedback()
	var anchor: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	game._set_player_world_position(anchor)
	var pickups: Array[LootPickup] = []
	for amount in range(1, 11):
		assert(game._spawn_gold_loot(amount, anchor, anchor, true))
	for child: Node in game.get_children():
		if child is LootPickup and child.collection_pending():
			pickups.append(child)
	assert(pickups.size() == 10 and game._pending_loot_collections.size() == 10,
		"real manager must accept all ten requests once while player is in range")
	# Move after acceptance, before the deferred flush, then continue moving
	# during the real background write. Neither may undo an accepted pickup.
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5)))
	var flush: Dictionary = game._flush_loot_collections(true)
	assert(flush.get("pending", false) and not game._prepared_loot_collection.is_empty(),
		"movement must not reject already accepted collection with a retry cooldown")
	var deadline := Time.get_ticks_msec() + 5000
	var completed: Dictionary
	while not game._prepared_loot_collection.is_empty():
		assert(Time.get_ticks_msec() < deadline)
		completed = game._poll_prepared_loot_collection()
		assert(not completed.get("retry", false), "movement cannot cancel and requeue accepted loot")
		await get_tree().process_frame
	assert(completed.success and completed.success_count == 10 and PlayerState.gold == 55)
	assert(game._pending_loot_collections.is_empty())
	for pickup: LootPickup in pickups:
		assert(not is_instance_valid(pickup), "each accepted source must retire exactly once after durable receipt")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState._profile_path("accepted")))
	assert(int(document.gold) == 55, "one real durable receipt must contain the complete collection")
	var layer: Control = game.hud.loot_feedback_layer
	for amount in range(1, 11):
		assert(layer.toast_entries.size() == 1 and layer.toast_entries[0].item_name == "金币 +%d" % amount,
			"actual committed HUD notices must preserve every source in order")
		layer._process(layer.DEFAULT_DURATION + 0.01)
	assert(layer.toast_entries.is_empty())
	game.free()
	PlayerState._json_persistence.drain()
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	print("LOOT_ACCEPTED_MOVEMENT_PASS count=10 durable_gold=55 single_receipt/continuous_movement/FIFO")
	get_tree().quit(0)
