extends Node

const CONTRACT_PATH := "res://assets/data/equipment_actor_sort_contract.json"


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CONTRACT_PATH)
	)
	assert(parsed is Dictionary, "equipment actor sort contract must be valid JSON")
	var contract: Dictionary = parsed
	assert(int(contract.get("schemaVersion", 0)) == 1)
	assert(str(contract.get("contractId", "")) == "equipment_actor_visual_sort_unit_v1")
	assert(
		contract.get("worldAppearanceFields", [])
		== ["dressAppearance", "weaponAppearance", "helmetAppearance"]
	)

	var actor_unit: Dictionary = contract.get("actorSortUnit", {})
	assert(str(actor_unit.get("actorNode", "")) == "Player")
	assert(str(actor_unit.get("visualNode", "")) == "PlayerVisual")
	assert(str(actor_unit.get("requiredCompositeBoundary", "")) == "CanvasGroup")
	assert(int(actor_unit.get("worldZIndex", -1)) == 0)
	assert(bool(actor_unit.get("zAsRelative", false)))
	assert(not bool(actor_unit.get("topLevel", true)))
	assert(not bool(actor_unit.get("showBehindParent", true)))
	assert(str(actor_unit.get("sortOrigin", "")) == "actor_feet")

	var layers: Dictionary = {}
	for layer_value: Variant in contract.get("internalLayers", []):
		assert(layer_value is Dictionary)
		var layer: Dictionary = layer_value
		layers[str(layer.get("id", ""))] = layer
	assert(layers.size() == 4)
	assert(int(layers.weapon_back.zIndex) == -1)
	assert(
		PackedInt32Array(layers.weapon_back.directionRows)
		== PackedInt32Array([7, 0, 1])
	)
	assert(int(layers.body_and_dress.zIndex) == 0)
	assert(int(layers.weapon_front.zIndex) == 1)
	assert(
		PackedInt32Array(layers.weapon_front.directionRows)
		== PackedInt32Array([2, 3, 4, 5, 6])
	)
	assert(int(layers.helmet.zIndex) == 2)
	assert(str(layers.weapon_back.node) == "ClientWeaponLayer")
	assert(str(layers.weapon_front.node) == "ClientWeaponLayer")
	assert(str(layers.body_and_dress.node) == "BodySprite")
	assert(str(layers.helmet.node) == "ClientHelmetLayer")

	var invariants: Array = contract.get("invariants", [])
	assert(invariants.size() == 5)
	assert(invariants.any(func(rule: Variant) -> bool:
		return "occludes body, dress, weapon and helmet together" in str(rule)
	))
	print(
		"EQUIPMENT_ACTOR_SORT_CONTRACT_PASS: one world sort unit, "
		+ "four internal appearance layers"
	)
	get_tree().quit(0)
