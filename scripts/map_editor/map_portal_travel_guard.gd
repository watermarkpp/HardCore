class_name MapPortalTravelGuard
extends RefCounted

const POLICY_ID := "portal_arrival_guard_v2"
const MINIMUM_RETURN_MSEC := 3000
const UNLOCK_DISTANCE_TILES := 1.5


static func new_state() -> Dictionary:
	return {
		"policy_id": POLICY_ID,
		"travel_in_flight": false,
		"locked_portal_id": "",
		"arrival_msec": -1,
		"arrival_tile": [0.0, 0.0],
	}


static func begin_travel(state: Dictionary) -> bool:
	if bool(state.get("travel_in_flight", false)):
		return false
	state["travel_in_flight"] = true
	return true


static func finish_arrival(
	state: Dictionary,
	portal_id: String,
	arrival_msec: int,
	arrival_tile: Vector2
) -> void:
	state["travel_in_flight"] = false
	state["locked_portal_id"] = portal_id
	state["arrival_msec"] = arrival_msec
	state["arrival_tile"] = [arrival_tile.x, arrival_tile.y]


static func can_activate(
	state: Dictionary,
	portal_id: String,
	now_msec: int,
	current_tile: Vector2,
	fresh_activation: bool
) -> bool:
	if bool(state.get("travel_in_flight", false)):
		return false
	if not fresh_activation:
		return false
	if str(state.get("locked_portal_id", "")) != portal_id:
		return true
	var arrival_msec := int(state.get("arrival_msec", now_msec))
	var elapsed_ready := now_msec - arrival_msec >= MINIMUM_RETURN_MSEC
	var raw_arrival: Array = state.get("arrival_tile", [0.0, 0.0])
	var arrival_tile := Vector2(float(raw_arrival[0]), float(raw_arrival[1]))
	var distance_ready := (
		current_tile.distance_to(arrival_tile) >= UNLOCK_DISTANCE_TILES
	)
	return elapsed_ready or distance_ready


static func clear_lock_after_departure(
	state: Dictionary,
	portal_id: String,
	current_tile: Vector2
) -> bool:
	if str(state.get("locked_portal_id", "")) != portal_id:
		return false
	var raw_arrival: Array = state.get("arrival_tile", [0.0, 0.0])
	var arrival_tile := Vector2(float(raw_arrival[0]), float(raw_arrival[1]))
	if current_tile.distance_to(arrival_tile) < UNLOCK_DISTANCE_TILES:
		return false
	state["locked_portal_id"] = ""
	return true
