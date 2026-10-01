extends Node

const StageFixture := preload("res://tests/helpers/ordered_json_stage_fixture.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 10000
	while game._world_bootstrap_in_progress or game._map_transition_in_progress:
		assert(Time.get_ticks_msec() < deadline)
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled())
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	PlayerState.set_process(false)
	var directory := "user://f03_native_root_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.active_profile_id = "native"
	PlayerState.test_mode = false
	PlayerState.gold = 0
	assert(PlayerState.save_game(false))
	var anchor: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	game._set_player_world_position(anchor)
	var first := _prepare(game, anchor, 7)
	await _start_committing(game, first)
	assert(PlayerState.gold == 0)
	# Fault at actual generation boundary; preserve an already-approved durable
	# transaction instead of falsely cancelling it after the worker committed.
	game._zone_generation += 1
	var outcome: Dictionary = game._poll_prepared_loot_collection()
	assert(outcome.success and PlayerState.gold == 7)
	assert(game._prepared_loot_collection.is_empty())
	game._zone_generation -= 1 # Restore this identity-only fault fixture.
	var second := _prepare(game, anchor, 11)
	await _start_committing(game, second)
	assert(PlayerState.gold == 7)
	game.free() # Native GameRoot._exit_tree must consume its committing receipt.
	assert(PlayerState.gold == 18 and second.completed and second.completion.success)
	var path: String = PlayerState._profile_path("native")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(int(stored.gold) == 18)
	assert(PlayerState.finish_prepared_loot_save(second).success and PlayerState.gold == 18)
	PlayerState._json_persistence.drain()
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	await get_tree().process_frame
	print("F03_NATIVE_PICKUP_LIFECYCLE_PASS")
	get_tree().quit(0)

func _prepare(game: Node, anchor: Vector2, amount: int) -> Dictionary:
	assert(game._spawn_gold_loot(amount, anchor, anchor))
	var pickup: LootPickup
	for child: Node in game.get_children():
		if child is LootPickup and child.gold_amount == amount:
			pickup = child
	assert(is_instance_valid(pickup))
	assert(game._loot_collection_path_is_clear(pickup))
	# Registration under the player's feet already requests native collection.
	# A second request is correctly rejected while that request is pending.
	assert(pickup.collection_pending())
	assert(game._flush_loot_collections(true).get("pending", false))
	var plan: Dictionary = game._prepared_loot_collection.plan
	assert(plan.writer.result(true).success)
	return plan

func _start_committing(game: Node, plan: Dictionary) -> void:
	await StageFixture.await_durable_promotion(PlayerState._json_persistence, plan.writer.job,
		game._poll_prepared_loot_collection, get_tree())
	assert(not plan.completed)
