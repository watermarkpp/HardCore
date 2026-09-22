extends Node

## WALL-P1R Consumer R1.1 minimal positive proof (advisor contract):
## two production bootstrap smokes through the REAL GameRoot staged order
## (prepare -> REQUEST_RESOURCES -> WAIT_RESOURCES -> required gate ->
## submit_staged_build -> BUILD_MAP). No cache injection; the optimized
## mode must be selected by the production pipeline itself.
##
## dark  (mengzhong_dark_area 913203): 650 atlas source commands -> 325
##       wall_atlas_sprite, 31 static chunks, zero legacy residue.
## valley (chiyue_valley 916001): 511 single-layer atlas commands -> 511
##       wall_atlas_sprite, zero chunks, zero legacy residue.

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"
const DARK_MAP_ID := 913203
const CHIYUE_MAP_ID := 916001
const DARK_EXPECTED_GROUPS := 325
const DARK_EXPECTED_CHUNKS := 35
const CHIYUE_EXPECTED_GROUPS := 511


func _ready() -> void:
	_run.call_deferred()


func _wait_for_transition(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not bool(game._map_transition_in_progress)


func _wait_for_initial_world(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not bool(game.gameplay_input_is_enabled()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(game.gameplay_input_is_enabled())


func _wait_bootstrap_idle(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while bool(game._world_bootstrap_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _travel(game: Node, map_id: int) -> void:
	assert(bool(game._request_map_travel(map_id)), "travel request failed: %d" % map_id)
	assert(bool(game._map_transition_in_progress), "transition did not start")
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})
	assert(await _wait_for_transition(game), "transition did not finish")
	assert(game.current_map_id == map_id)
	await _wait_bootstrap_idle(game)


func _collect_composites(root_node: Node) -> Array:
	var found: Array = []
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and bool(node.get_meta("editor_runtime_wall_composite", false)):
			found.append(node)
	return found


func _collect_chunk_sprites(root_node: Node) -> Array:
	var found: Array = []
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and bool(node.get_meta("wall_static_chunk", false)):
			found.append(node)
	return found


func _assert_optimized(game: Node, expected_groups: int, expected_chunks: int) -> void:
	var stats: Dictionary = game.background.wall_render_stats()
	assert(bool(stats["wall_render_plan_found"]), "plan not found")
	assert(bool(stats["wall_render_plan_valid"]), "plan invalid")
	assert(
		str(stats["wall_render_mode"]) == "OPTIMIZED",
		"mode=%s reason=%s" % [
			str(stats["wall_render_mode"]),
			str(stats["wall_render_fallback_reason"]),
		]
	)
	assert(str(stats["wall_render_fallback_reason"]) == "")
	assert(int(stats["dynamic_group_count"]) == expected_groups, "group count")
	assert(int(stats["static_chunk_count"]) == expected_chunks, "chunk count")
	# Wall y-sort wrappers live under background's parent layer, not inside
	# background itself - walk the whole game scene.
	var atlas_nodes := _collect_composites(game)
	assert(
		atlas_nodes.size() == expected_groups,
		"atlas nodes %d != expected %d" % [atlas_nodes.size(), expected_groups]
	)
	# P0-2 residue proof: a wall y-sort wrapper must hold the composite and
	# NO legacy instance sprite. The static authored wall bridge overlay
	# (meta static_authored_wall_bridge, in-code texture) is a legitimate
	# extra layer with identical semantics in the legacy path - it rides on
	# top of the wall's wrapper and is not residue.
	for sprite: Sprite2D in atlas_nodes:
		var wrapper := sprite.get_parent()
		var composite_children := 0
		var legacy_children := 0
		for child in wrapper.get_children():
			if child is Sprite2D:
				if bool(child.get_meta("editor_runtime_wall_composite", false)):
					composite_children += 1
				elif bool(child.get_meta("editor_runtime_instance", false)):
					legacy_children += 1
					print("SMOKE_DUMP residue wrapper=%s child=%s" % [
						str(wrapper.name), str(child.name),
					])
		assert(
			composite_children == 1,
			"wall wrapper %s holds %d composites" % [
				str(wrapper.name), composite_children,
			]
		)
		assert(
			legacy_children == 0,
			"wall wrapper %s holds %d legacy instance sprites (residue)" % [
				str(wrapper.name), legacy_children,
			]
		)
	var chunk_nodes := _collect_chunk_sprites(game)
	assert(
		chunk_nodes.size() == expected_chunks,
		"chunk sprites %d != expected %d" % [chunk_nodes.size(), expected_chunks]
	)
	var coord = game._world_bootstrap_coordinator
	assert(not coord.has_failed_required_resource(), "required prefetch failed")
	assert(int(coord.unexpected_sync_load_count) == 0, "unexpected sync load")


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	assert(await _wait_for_initial_world(game), "initial world did not finish")
	await _wait_bootstrap_idle(game)
	game._monster_prefetch_enabled = false
	# Production staged travel: real bootstrap order decides OPTIMIZED.
	PlayerState.test_mode = false

	await _travel(game, DARK_MAP_ID)
	_assert_optimized(game, DARK_EXPECTED_GROUPS, DARK_EXPECTED_CHUNKS)

	await _travel(game, CHIYUE_MAP_ID)
	_assert_optimized(game, CHIYUE_EXPECTED_GROUPS, 0)

	game.queue_free()
	print(
		"WALL_RENDER_OPTIMIZED_SMOKE_PASS dark_groups=%d dark_chunks=%d chiyue_groups=%d" % [
			DARK_EXPECTED_GROUPS, DARK_EXPECTED_CHUNKS, CHIYUE_EXPECTED_GROUPS,
		]
	)
	get_tree().quit(0)
