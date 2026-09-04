extends Node

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"
const SHARED_WHITELIST := [
	"res://assets/presentation/skins/gothic_bich_camp/gothic_bich_ground_tiles.png",
	"res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png",
]


func _ready() -> void:
	_run.call_deferred()


func _wait_for_transition(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not bool(game._map_transition_in_progress)


func _production_travel(game: Node, map_id: int) -> void:
	PlayerState.test_mode = false
	game.travel_to_map(map_id)
	assert(game._map_transition_in_progress, "production travel must start a coordinator transition")
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})
	assert(await _wait_for_transition(game), "transition did not finish")
	assert(game.current_map_id == map_id, "arrival map mismatch")


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game._monster_prefetch_enabled = false

	# Production path through the coordinator into the orc-tomb region.
	await _production_travel(game, 217)
	var coord = game._world_bootstrap_coordinator
	var scope: Dictionary = coord.resource_scope_summary()
	assert(str(scope.get("target_region", "")) == "orc_tomb", "target region must be orc_tomb")
	assert(int(scope.get("target_map_resource_count", 0)) > 0, "target-map resources must be requested")
	assert(int(scope.get("cross_region_resource_count", 0)) == 0, "cross-region resources must be 0")
	for path: Variant in coord.resource_manifest:
		var entry: Dictionary = coord.resource_manifest[path]
		if str(entry.get("scope", "target")) == "shared":
			assert(path in SHARED_WHITELIST, "shared resource not whitelisted: %s" % path)
		else:
			var path_text := str(path)
			assert(
				not (
					"/wooma_region/" in path_text
					or "/snake_valley/" in path_text
					or "/mine/" in path_text
					or "/natural_cave/" in path_text
					or "/bich/" in path_text
					or "/gothic_bich_camp/" in path_text
				),
				"other-region exclusive resource requested for map 217: %s" % path_text
			)

	# Switching to the wooma-forest region must not request orc-tomb exclusive
	# resources either (shared orc_tomb_ground base is whitelisted).
	await _production_travel(game, 268)
	coord = game._world_bootstrap_coordinator
	scope = coord.resource_scope_summary()
	assert(str(scope.get("target_region", "")) == "wooma_forest", "target region must be wooma_forest")
	assert(int(scope.get("cross_region_resource_count", 0)) == 0, "cross-region resources must be 0 on region switch")
	for path: Variant in coord.resource_manifest:
		var entry: Dictionary = coord.resource_manifest[path]
		if str(entry.get("scope", "target")) == "shared":
			assert(path in SHARED_WHITELIST, "shared resource not whitelisted: %s" % path)
		else:
			var path_text := str(path)
			assert(
				not (
					"/orc_tomb/" in path_text
					or "/bich/" in path_text
					or "/snake_valley/" in path_text
				),
				"other-region exclusive resource requested for map 268: %s" % path_text
			)

	game.queue_free()
	print(
		"WORLD_BACKGROUND_TARGET_RESOURCE_SCOPE_PASS "
		+ "target_region=%s cross_region=%d" % [
			str(scope.get("target_region", "")),
			int(scope.get("cross_region_resource_count", 0)),
		]
	)
	get_tree().quit(0)
