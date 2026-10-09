extends Node

const FormalReady := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var _path_checks := 0
var _rejections: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _checked_formal_path(pickup: LootPickup, game: Node) -> bool:
	_path_checks += 1
	return game._loot_collection_path_is_clear(pickup)

func _rejected(_item_name: String, message: String) -> void:
	_rejections.append(message)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await FormalReady.wait_for_formal_world(self, game, "continuous_cohorts")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	PlayerState.set_process(false)
	var directory := "user://loot_continuous_cohorts_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.active_profile_id = "cohorts"
	PlayerState.test_mode = false
	PlayerState.inventory = []
	PlayerState.gold = 0
	assert(PlayerState.save_game(false))
	var layer: Control = game.hud.loot_feedback_layer
	layer.set_process(false)
	layer.clear_feedback()
	var anchor: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	game._set_player_world_position(anchor)
	game._loot_pickup_runtime_manager.collection_path_is_clear = _checked_formal_path.bind(game)
	assert(game._spawn_gold_loot(1, anchor, anchor, true))
	var first: LootPickup = game._pending_loot_collections[0].pickup
	first.collection_rejected.connect(_rejected)
	assert(game._flush_loot_collections(true).get("pending", false))
	# Accepted sources must not keep raycasting while a real write owns them.
	var path_checks_before := _path_checks
	for iteration in 20:
		game._loot_pickup_runtime_manager.player_position_changed(anchor)
	assert(_path_checks == path_checks_before,
		"an accepted source must not repeat terrain admission checks during IO")
	# A real save barrier cancels unapproved preparation. New sources can enter
	# before GameRoot consumes that receipt; old accepted order must survive.
	assert(PlayerState.save_game(false))
	assert(bool(game._prepared_loot_collection.plan.completed))
	assert(bool(game._prepared_loot_collection.plan.completion.get("retry", false)))
	var item: Dictionary = GameData.get_item_record("金创药(小量)")
	assert(not item.is_empty())
	for index in 10:
		assert(game._spawn_loot(str(item.name), anchor, {}, anchor, true))
		var pickup: LootPickup = game._pending_loot_collections.back().pickup
		pickup.collection_rejected.connect(_rejected)
		assert(game._spawn_gold_loot(index + 2, anchor, anchor, true))
		pickup = game._pending_loot_collections.back().pickup
		pickup.collection_rejected.connect(_rejected)
	assert(game._pending_loot_collections.size() == 20)
	var retried: Dictionary = game._poll_prepared_loot_collection()
	assert(retried.get("retry", false))
	assert(game._pending_loot_collections.size() == 21)
	assert(game._pending_loot_collections[0].pickup == first,
		"a receipt retry must precede newer sources instead of reversing accepted order")
	var commits_before := int(PlayerState.loot_batch_debug_snapshot().get("save_commits", 0))
	var deadline := Time.get_ticks_msec() + 5000
	while not game._pending_loot_collections.is_empty() or not game._prepared_loot_collection.is_empty():
		assert(Time.get_ticks_msec() < deadline)
		if game._prepared_loot_collection.is_empty():
			game._flush_loot_collections(true)
		else:
			game._poll_prepared_loot_collection()
		await get_tree().process_frame
	assert(_rejections.is_empty(), "continuous accepted pickup must not emit an artificial busy/retry error")
	assert(PlayerState.gold == 66 and PlayerState.item_count_by_entity_id(GameData.item_entity_id(item)) == 10)
	assert(int(PlayerState.loot_batch_debug_snapshot().get("save_commits", 0)) == commits_before + 1,
		"uncommitted continuous sources must coalesce into one durable collection")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState._profile_path("cohorts")))
	# Wire records deliberately omit runtime identity aliases. Verify the
	# persisted canonical owner/count rather than equating the two formats.
	assert(int(document.gold) == 66 and document.inventory.size() == 1)
	assert(int(document.inventory[0].item_id) == 920045
		and int(document.inventory[0].count) == 10
		and str(document.inventory[0].name) == str(item.name),
		"durable item ownership and count must exactly match the accepted sources")
	assert(layer.toast_entries[0].item_name == "金币 +1")
	layer._process(layer.DEFAULT_DURATION + 0.01)
	for index in 10:
		assert(layer.toast_entries[0].item_name == str(item.name))
		layer._process(layer.DEFAULT_DURATION + 0.01)
		assert(layer.toast_entries[0].item_name == "金币 +%d" % (index + 2))
		layer._process(layer.DEFAULT_DURATION + 0.01)
	assert(layer.toast_entries.is_empty())
	game.free()
	PlayerState._json_persistence.drain()
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	print("LOOT_CONTINUOUS_COHORTS_PASS 21_sources/item_gold/save_barrier_retry/one_commit/no_false_error/FIFO/no_pending_raycast")
	get_tree().quit(0)
