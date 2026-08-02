class_name MapPortalRuntimeService
extends RefCounted

const PORTAL_CONTRACT_ID := "unified_map_portal_endpoint_v1"
const ARRIVAL_GUARD_POLICY_ID := "portal_arrival_guard_v2"


static func endpoints(runtime: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for endpoint: Dictionary in runtime.get("semantics", {}).get(
		"map_exit_points", []
	):
		if str(endpoint.get("portal_contract_id", "")) == PORTAL_CONTRACT_ID:
			result.append(endpoint)
	return result


static func endpoint_by_id(
	runtime: Dictionary,
	portal_id: String
) -> Dictionary:
	for endpoint: Dictionary in endpoints(runtime):
		if str(endpoint.get("semantic_id", "")) == portal_id:
			return endpoint
	return {}


static func travel_request(endpoint: Dictionary) -> Dictionary:
	if str(endpoint.get("portal_contract_id", "")) != PORTAL_CONTRACT_ID:
		return {"ok": false, "errors": ["unsupported_portal_contract"]}
	if not bool(endpoint.get("target_configured", false)):
		return {"ok": false, "errors": ["portal_target_not_configured"]}
	return {
		"ok": true,
		"target_map_id": int(endpoint.get("target_map_id", -1)),
		"target_map_key": str(endpoint.get("target_map_key", "")),
		"target_portal_id": str(endpoint.get("target_portal_id", "")),
		"target_tile": endpoint.get("target_tile", []).duplicate(),
		"arrival_guard_policy_id": str(
			endpoint.get("arrival_reentry_policy_id", "")
		),
		"return_minimum_seconds": float(
			endpoint.get("return_minimum_seconds", 0.0)
		),
		"return_unlock_distance_gu": float(
			endpoint.get("return_unlock_distance_gu", 0.0)
		),
		"single_flight": bool(
			endpoint.get("travel_request_single_flight", false)
		),
	}


static func validate_network(
	runtimes_by_map_key: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	for source_map_key: String in runtimes_by_map_key:
		var source: Dictionary = runtimes_by_map_key[source_map_key]
		for endpoint: Dictionary in endpoints(source):
			var portal_id := str(endpoint.get("semantic_id", ""))
			if bool(endpoint.get("arrival_only", false)):
				continue
			if not bool(endpoint.get("target_configured", false)):
				continue
			var target_map_key := str(endpoint.get("target_map_key", ""))
			if not runtimes_by_map_key.has(target_map_key):
				errors.append("target_runtime_missing:%s" % portal_id)
				continue
			var target: Dictionary = runtimes_by_map_key[target_map_key]
			var target_endpoint := endpoint_by_id(
				target,
				str(endpoint.get("target_portal_id", ""))
			)
			if target_endpoint.is_empty():
				errors.append("target_portal_missing:%s" % portal_id)
				continue
			if bool(endpoint.get("one_way", false)):
				if not bool(target_endpoint.get("arrival_only", false)):
					errors.append("one_way_target_not_arrival_only:%s" % portal_id)
				if bool(target_endpoint.get("trigger_on_enter", true)):
					errors.append("one_way_target_trigger_enabled:%s" % portal_id)
				_validate_guard(endpoint, portal_id, errors)
				continue
			if str(target_endpoint.get("target_map_key", "")) != source_map_key:
				errors.append("target_map_not_reciprocal:%s" % portal_id)
			if str(target_endpoint.get("target_portal_id", "")) != portal_id:
				errors.append("target_portal_not_reciprocal:%s" % portal_id)
			_validate_guard(endpoint, portal_id, errors)
	return errors


static func _validate_guard(
	endpoint: Dictionary,
	portal_id: String,
	errors: Array[String]
) -> void:
	if str(endpoint.get("arrival_reentry_policy_id", "")) != ARRIVAL_GUARD_POLICY_ID:
		errors.append("arrival_guard_missing:%s" % portal_id)
	if not bool(endpoint.get("travel_request_single_flight", false)):
		errors.append("single_flight_missing:%s" % portal_id)
