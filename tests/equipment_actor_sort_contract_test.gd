extends Node

const CONTRACT_PATH := "res://assets/data/equipment_actor_sort_contract.json"


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CONTRACT_PATH)
	)
	assert(parsed is Dictionary, "equipment actor sort contract must be valid JSON")
	var contract: Dictionary = parsed
	assert(int(contract.get("schemaVersion", 0)) == 3)
	assert(str(contract.get("contractId", "")) == EquipmentRules.ACTOR_VISUAL_SORT_CONTRACT_ID)
	assert(
		contract.get("worldAppearanceFields", [])
		== ["dressAppearance", "weaponAppearance", "helmetAppearance"]
	)

	var actor_unit: Dictionary = contract.get("actorSortUnit", {})
	assert(str(actor_unit.get("actorNode", "")) == "Player")
	assert(str(actor_unit.get("visualNode", "")) == "PlayerVisual")
	assert(str(actor_unit.get("requiredCompositeBoundary", "")) == "single_non_y_sorted_canvas_subtree")
	assert(int(actor_unit.get("worldZIndex", -1)) == 0)
	assert(bool(actor_unit.get("zAsRelative", false)))
	assert(not bool(actor_unit.get("topLevel", true)))
	assert(not bool(actor_unit.get("showBehindParent", true)))
	assert(str(actor_unit.get("sortOrigin", "")) == "actor_feet")
	assert(str(actor_unit.get("internalOrderMechanism", "")) == "sibling_tree_order")

	var layers: Dictionary = {}
	for layer_value: Variant in contract.get("worldPlaneLayers", []):
		assert(layer_value is Dictionary)
		var layer: Dictionary = layer_value
		layers[str(layer.get("id", ""))] = layer
	assert(layers.size() == 4)
	assert(int(layers.body_and_dress.zIndex) == 0)
	assert(int(layers.hair.zIndex) == 0)
	assert(int(layers.weapon.zIndex) == 0)
	assert(int(layers.helmet.zIndex) == 0)
	assert(str(layers.weapon.node) == "ClientWeaponLayer")
	assert(str(layers.body_and_dress.node) == "BodySprite")
	assert(str(layers.hair.node) == "ClientHairLayer")
	assert(str(layers.helmet.node) == "ClientHelmetLayer")

	var covered_rows := PackedInt32Array()
	for order_value: Variant in contract.get("siblingOrderByDirection", []):
		assert(order_value is Dictionary)
		var order: Dictionary = order_value
		var expected: Array[StringName] = EquipmentRules.actor_visual_layer_order(
			int(order.directionRows[0])
		)
		assert(_string_array(order.backToFront) == _string_array(expected))
		for row_value: Variant in order.directionRows:
			var row := int(row_value)
			covered_rows.append(row)
			assert(
				_string_array(EquipmentRules.actor_visual_layer_order(row))
				== _string_array(expected)
			)
	covered_rows.sort()
	assert(covered_rows == PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7]))

	var invariants: Array = contract.get("invariants", [])
	assert(invariants.size() == 6)
	assert(invariants.any(func(rule: Variant) -> bool:
		return "occludes body, dress, weapon and helmet together" in str(rule)
	))
	print(
		"EQUIPMENT_ACTOR_SORT_CONTRACT_PASS: one world z plane, "
		+ "four appearance layers ordered by sibling tree order"
	)
	get_tree().quit(0)


func _string_array(values: Variant) -> Array[String]:
	var normalized: Array[String] = []
	for value: Variant in values:
		normalized.append(str(value))
	return normalized
