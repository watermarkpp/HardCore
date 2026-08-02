extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const MapPortalTravelGuard := preload(
	"res://scripts/map_editor/map_portal_travel_guard.gd"
)


func _ready() -> void:
	var game := GameRootScript.new()
	var request := {
		"ok": true,
		"target_map_id": 1,
		"target_map_key": "map.1",
		"target_portal_id": "portal.1",
		"arrival_guard_policy_id": MapPortalTravelGuard.POLICY_ID,
		"return_minimum_seconds": 3.0,
		"return_unlock_distance_gu": MapPortalTravelGuard.UNLOCK_DISTANCE_GU,
		"single_flight": true,
	}
	assert(game._valid_portal_request(request))

	var legacy_only := request.duplicate(true)
	legacy_only.erase("return_unlock_distance_gu")
	legacy_only["return_unlock_distance_tiles"] = (
		MapPortalTravelGuard.UNLOCK_DISTANCE_GU
	)
	assert(not game._valid_portal_request(legacy_only))

	var source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	assert(not source.contains("spawn.get(\"radius_tiles\""))
	assert(source.contains("spawn.get(\"radius_gu\""))
	assert(source.contains(
		"GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px"
	))

	game.free()
	print("GAME_ROOT_MAP_UNIT_INTEGRATION_PASS")
	get_tree().quit()
