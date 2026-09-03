class_name MapTeleportRuntimePolicy
extends RefCounted

const MapEditorRuntimeBridgeScript := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const CONTRACT_ID := "gameplay.map.teleport.policy.v1"
const UI_REQUEST_CONTRACT_ID := "ui.map.teleport.v1"
const DIRECT_CITY_RULE_ID := "map.teleport.direct_city.v1"
const SCROLL_RULE_ID := "map.teleport.scroll_requirement.v1"
const DEFAULT_CITY_ARRIVAL_ANCHOR_ID := "map.respawn.default"

const DIRECT_CITY_LABELS := {
	910001: "比奇",
	910003: "盟重",
	910005: "封魔谷",
	910006: "白日门",
	910007: "苍月岛",
}

# Future content adds exact item IDs here. An absent entry is deliberately
# fail-closed: no name matching and no generic-scroll fallback can unlock it.
const SCROLL_REQUIREMENTS_BY_MAP_ID := {}


static func rules_for_maps(
	map_ids: Array,
	item_count_by_id := Callable(),
) -> Dictionary:
	var rules: Dictionary = {}
	for raw_map_id: Variant in map_ids:
		var map_id := int(raw_map_id)
		if map_id <= 0:
			continue
		rules[map_id] = rule_for_map(map_id, item_count_by_id)
	return rules


static func rule_for_map(
	map_id: int,
	item_count_by_id := Callable(),
) -> Dictionary:
	if DIRECT_CITY_LABELS.has(map_id):
		var city_label := str(DIRECT_CITY_LABELS[map_id])
		return {
			"contract_id": CONTRACT_ID,
			"enabled": true,
			"destination_map_id": map_id,
			"arrival_anchor_id": DEFAULT_CITY_ARRIVAL_ANCHOR_ID,
			"destination_label": "%s复活点" % city_label,
			"reason": "",
			"rule_id": DIRECT_CITY_RULE_ID,
			"unlock_contract_id": DIRECT_CITY_RULE_ID,
			"requires_map_scroll": false,
			"required_item_id": -1,
			"required_item_count": 0,
			"consume_on_success": false,
		}

	var requirement := scroll_requirement_for_map(map_id)
	if requirement.is_empty():
		return _locked_scroll_rule(
			map_id,
			"需要该地图对应的传送卷轴（卷轴功能尚未开放）",
		)
	var item_id := int(requirement.get("required_item_id", -1))
	var required_count := maxi(1, int(requirement.get("required_item_count", 1)))
	var owned_count := 0
	if item_count_by_id.is_valid():
		owned_count = maxi(0, int(item_count_by_id.call(item_id)))
	var enabled := item_id > 0 and owned_count >= required_count
	return {
		"contract_id": CONTRACT_ID,
		"enabled": enabled,
		"destination_map_id": int(requirement.get("destination_map_id", map_id)),
		"arrival_anchor_id": str(requirement.get("arrival_anchor_id", "")),
		"destination_label": str(requirement.get("destination_label", "地图传送点")),
		"reason": "" if enabled else "需要对应传送卷轴",
		"rule_id": str(requirement.get("rule_id", SCROLL_RULE_ID)),
		"unlock_contract_id": SCROLL_RULE_ID,
		"requires_map_scroll": true,
		"required_item_id": item_id,
		"required_item_count": required_count,
		"owned_item_count": owned_count,
		"consume_on_success": bool(requirement.get("consume_on_success", true)),
	}


static func scroll_requirement_for_map(map_id: int) -> Dictionary:
	var raw: Variant = SCROLL_REQUIREMENTS_BY_MAP_ID.get(map_id, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func request_matches_rule(request: Dictionary, rule: Dictionary) -> bool:
	return (
		str(request.get("contract_id", "")) == UI_REQUEST_CONTRACT_ID
		and bool(rule.get("enabled", false))
		and int(request.get("selected_map_id", -1)) > 0
		and int(request.get("destination_map_id", -1))
			== int(rule.get("destination_map_id", -2))
		and str(request.get("arrival_anchor_id", ""))
			== str(rule.get("arrival_anchor_id", "__missing__"))
		and str(request.get("rule_id", ""))
			== str(rule.get("rule_id", "__missing__"))
	)


static func resolve_arrival(map_id: int, anchor_id: String) -> Dictionary:
	if anchor_id != DEFAULT_CITY_ARRIVAL_ANCHOR_ID:
		return _invalid_arrival(map_id, "unsupported_arrival_anchor")
	var runtime := MapEditorRuntimeBridgeScript.load_map(map_id)
	if runtime.is_empty():
		return _invalid_arrival(map_id, "runtime_map_unavailable")
	var semantics: Dictionary = runtime.get("semantics", {})
	var respawn := _preferred_respawn_point(
		semantics.get("respawn_points", [])
	)
	if not respawn.is_empty():
		return _arrival_from_tile(
			map_id,
			runtime,
			respawn.get("tile", []),
			str(respawn.get("semantic_id", respawn.get("respawn_id", ""))),
			"respawn_point",
		)
	# Direct-city teleport is only allowed to a formally authored respawn point.
	# Safe areas and map centers are not interchangeable arrival authorities.
	return _invalid_arrival(map_id, "formal_respawn_point_missing")


static func _locked_scroll_rule(map_id: int, reason: String) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"enabled": false,
		"destination_map_id": map_id,
		"arrival_anchor_id": "",
		"destination_label": "",
		"reason": reason,
		"rule_id": SCROLL_RULE_ID,
		"unlock_contract_id": SCROLL_RULE_ID,
		"requires_map_scroll": true,
		"required_item_id": -1,
		"required_item_count": 1,
		"owned_item_count": 0,
		"consume_on_success": true,
	}


static func _preferred_respawn_point(raw_points: Variant) -> Dictionary:
	if not raw_points is Array:
		return {}
	for raw: Variant in raw_points:
		if (
			raw is Dictionary
			and bool((raw as Dictionary).get("is_respawn_point", true))
			and bool((raw as Dictionary).get("is_default", false))
		):
			return raw as Dictionary
	for raw: Variant in raw_points:
		if raw is Dictionary and bool((raw as Dictionary).get("is_respawn_point", true)):
			return raw as Dictionary
	return {}


static func _arrival_from_tile(
	map_id: int,
	runtime: Dictionary,
	raw_tile: Variant,
	resolved_anchor_id: String,
	source: String,
) -> Dictionary:
	if not raw_tile is Array or (raw_tile as Array).size() != 2:
		return _invalid_arrival(map_id, "invalid_arrival_tile")
	return {
		"valid": true,
		"map_id": map_id,
		"position_px": MapEditorRuntimeBridgeScript.grid_cell_to_screen_position_px(
			runtime,
			raw_tile as Array,
		),
		"resolved_anchor_id": resolved_anchor_id,
		"source": source,
		"reason": "",
	}


static func _invalid_arrival(map_id: int, reason: String) -> Dictionary:
	return {
		"valid": false,
		"map_id": map_id,
		"position_px": Vector2.ZERO,
		"resolved_anchor_id": "",
		"source": "",
		"reason": reason,
	}
