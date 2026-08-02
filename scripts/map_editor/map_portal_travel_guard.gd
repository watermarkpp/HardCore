class_name MapPortalTravelGuard
extends RefCounted

const POLICY_ID := "portal_arrival_guard_v2"
const MINIMUM_RETURN_MSEC := 3000
const UNLOCK_DISTANCE_GU := 1.5
# Deprecated compatibility alias for old tests and positional callers.
const UNLOCK_DISTANCE_TILES := UNLOCK_DISTANCE_GU


static func new_state() -> Dictionary:
	return {
		"policy_id": POLICY_ID,
		"travel_in_flight": false,
		"locked_portal_id": "",
		"arrival_msec": -1,
		"arrival_ground_gu": [0.0, 0.0],
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
	arrival_ground_gu: Vector2
) -> void:
	state["travel_in_flight"] = false
	state["locked_portal_id"] = portal_id
	state["arrival_msec"] = arrival_msec
	state["arrival_ground_gu"] = [arrival_ground_gu.x, arrival_ground_gu.y]
	state["arrival_tile"] = [arrival_ground_gu.x, arrival_ground_gu.y]


static func can_activate(
	state: Dictionary,
	portal_id: String,
	now_msec: int,
	current_ground_gu: Vector2,
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
	var raw_arrival: Array = state.get(
		"arrival_ground_gu", state.get("arrival_tile", [0.0, 0.0])
	)
	var arrival_ground_gu := Vector2(float(raw_arrival[0]), float(raw_arrival[1]))
	var distance_ready := (
		current_ground_gu.distance_to(arrival_ground_gu) >= UNLOCK_DISTANCE_GU
	)
	return elapsed_ready or distance_ready


static func clear_lock_after_departure(
	state: Dictionary,
	portal_id: String,
	current_ground_gu: Vector2
) -> bool:
	if str(state.get("locked_portal_id", "")) != portal_id:
		return false
	var raw_arrival: Array = state.get(
		"arrival_ground_gu", state.get("arrival_tile", [0.0, 0.0])
	)
	var arrival_ground_gu := Vector2(float(raw_arrival[0]), float(raw_arrival[1]))
	if current_ground_gu.distance_to(arrival_ground_gu) < UNLOCK_DISTANCE_GU:
		return false
	state["locked_portal_id"] = ""
	return true
