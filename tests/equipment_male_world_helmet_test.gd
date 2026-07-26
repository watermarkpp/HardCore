extends Node


const CONTRACT_PATH := "res://assets/data/equipment_male_world_helmet.json"
const CATALOG_PATH := "res://assets/data/equipment_visual_catalog.json"
const EXPECTED_ITEMS := {
	"146": ["精灵头盔", 105, "elf"],
	"147": ["青铜头盔", 100, "bronze_magic"],
	"148": ["魔法头盔", 100, "bronze_magic"],
	"149": ["道士头盔", 106, "taoist"],
	"150": ["骷髅头盔", 103, "skeleton"],
	"151": ["黑铁头盔", 344, "black_iron"],
	"218": ["神秘头盔", 111, "mystery"],
	"224": ["祈祷头盔", 110, "prayer"],
	"228": ["记忆头盔", 109, "memory"],
	"232": ["圣战头盔", 104, "holy_war"],
	"236": ["法神头盔", 101, "god_magic"],
	"240": ["天尊头盔", 102, "heavenly_taoist"],
}
const EXPECTED_ACTIONS := {
	"idle": 4,
	"walk": 6,
	"attack": 6,
	"cast": 6,
	"hit": 3,
	"death": 4,
}
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


func _ready() -> void:
	_run.call_deferred()


func _json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "%s must contain a Dictionary" % path)
	return parsed


func _assert_int_array(actual: Variant, expected: Array, label: String) -> void:
	assert(actual is Array and actual.size() == expected.size(), "%s size changed" % label)
	for index: int in expected.size():
		assert(int(actual[index]) == int(expected[index]), "%s[%d] changed" % [label, index])


func _run() -> void:
	var contract := _json(CONTRACT_PATH)
	var catalog := _json(CATALOG_PATH)
	assert(
		contract.get("contractId", "")
		== EquipmentRules.MALE_WORLD_HELMET_EXTENSION_CONTRACT_ID
	)
	assert(contract.get("sex", "") == "male")
	assert(bool(contract.get("sourcePolicy", {}).get("femaleExcluded", false)))
	assert(not bool(contract.get("sourcePolicy", {}).get("stateItemPixelsUsed", true)))
	assert(not bool(contract.get("sourcePolicy", {}).get("hairPixelsUsed", true)))
	assert(contract.get("sourcePolicy", {}).get("actionFallbacks", {}) == {})
	_assert_int_array(contract.get("actorContract", {}).get("cell", []), [192, 160], "cell")
	_assert_int_array(contract.get("actorContract", {}).get("footAnchor", []), [64, 80], "footAnchor")
	assert(contract.get("actorContract", {}).get("directions", []) == DIRECTIONS)
	assert(not bool(contract.get("actorContract", {}).get("footPointContractChanged", true)))

	var coverage: Dictionary = contract.get("coverage", {})
	assert(int(coverage.get("formalHelmetItems", 0)) == 12)
	assert(int(coverage.get("visualIdentities", 0)) == 11)
	assert(int(coverage.get("actionsPerIdentity", 0)) == 6)
	assert(int(coverage.get("directionsPerAction", 0)) == 8)
	assert(int(coverage.get("physicalAtlasCells", 0)) == 2552)
	assert(int(coverage.get("logicalItemCells", 0)) == 2784)
	assert(int(coverage.get("missingFrames", -1)) == 0)
	assert(int(coverage.get("maleItems", 0)) == 12)
	assert(int(coverage.get("femaleItems", -1)) == 0)

	var identities: Dictionary = contract.get("visualIdentities", {})
	assert(identities.size() == 11)
	var loaded_paths: Dictionary = {}
	for identity_id: String in identities:
		var identity: Dictionary = identities[identity_id]
		assert(identity.get("identityId", "") == identity_id)
		assert(identity.get("sex", "") == "male")
		assert(not bool(identity.get("stateItemPixelsUsed", true)))
		assert(not bool(identity.get("hairPixelsUsed", true)))
		var source_order: Array = identity.get("sourceSlotDirectionOrder", [])
		var canonical_slots: Array = identity.get("canonicalRowSourceSlots", [])
		assert(source_order.size() == 8 and canonical_slots.size() == 8)
		var seen_directions: Dictionary = {}
		var seen_slots: Dictionary = {}
		for row: int in 8:
			var direction := str(source_order[row])
			assert(direction in DIRECTIONS)
			assert(not seen_directions.has(direction), "%s duplicates direction %s" % [identity_id, direction])
			seen_directions[direction] = true
			var source_slot := int(canonical_slots[row])
			assert(source_slot >= 0 and source_slot < 8)
			assert(not seen_slots.has(source_slot), "%s duplicates source slot %d" % [identity_id, source_slot])
			seen_slots[source_slot] = true
			assert(str(source_order[source_slot]) == str(DIRECTIONS[row]))
		var acceptance: Dictionary = identity.get("directionAcceptance", {})
		assert(acceptance.get("classificationStatus", "") == "accepted_manual_visual_classification")
		assert(not str(acceptance.get("classificationEvidence", "")).is_empty())
		assert(FileAccess.file_exists(str(acceptance.get("path", ""))))

		var actions: Dictionary = identity.get("actions", {})
		assert(actions.keys().size() == 6)
		for action_name: String in EXPECTED_ACTIONS:
			var action: Dictionary = actions.get(action_name, {})
			assert(int(action.get("directions", 0)) == 8)
			assert(int(action.get("framesPerDirection", 0)) == int(EXPECTED_ACTIONS[action_name]))
			assert(int(action.get("physicalCellCount", 0)) == 8 * int(EXPECTED_ACTIONS[action_name]))
			assert(action.get("missingFrames", []).is_empty())
			_assert_int_array(action.get("cell", []), [192, 160], "%s/%s cell" % [identity_id, action_name])
			_assert_int_array(action.get("footAnchor", []), [64, 80], "%s/%s footAnchor" % [identity_id, action_name])
			var path := str(action.get("path", ""))
			assert(ResourceLoader.exists(path), "helmet atlas is not imported: %s" % path)
			assert(not loaded_paths.has(path), "two physical identity actions share an atlas: %s" % path)
			var texture := load(path) as Texture2D
			assert(texture != null)
			assert(texture.get_width() == 192 * int(EXPECTED_ACTIONS[action_name]))
			assert(texture.get_height() == 160 * 8)
			var image := texture.get_image()
			assert(image != null)
			for direction: int in 8:
				for frame: int in int(EXPECTED_ACTIONS[action_name]):
					var x := frame * 192
					var y := direction * 160
					assert(image.get_pixel(x, y).a == 0.0)
					assert(image.get_pixel(x + 191, y).a == 0.0)
					assert(image.get_pixel(x, y + 159).a == 0.0)
					assert(image.get_pixel(x + 191, y + 159).a == 0.0)
			loaded_paths[path] = true
	assert(loaded_paths.size() == 66)

	var items: Dictionary = contract.get("itemsById", {})
	var catalog_items: Dictionary = catalog.get("itemsById", {})
	var catalog_runtime: Dictionary = catalog.get("runtimeMappings", {})
	assert(items.keys().size() == 12)
	for item_key: String in EXPECTED_ITEMS:
		var expected: Array = EXPECTED_ITEMS[item_key]
		var item: Dictionary = items.get(item_key, {})
		assert(int(item.get("itemId", -1)) == int(item_key))
		assert(item.get("itemName", "") == expected[0])
		assert(int(item.get("sourceIndex", -1)) == int(expected[1]))
		assert(item.get("identityId", "") == expected[2])
		assert(item.get("sex", "") == "male")
		var appearance: Dictionary = item.get("maleAppearance", {})
		assert(appearance.get("sex", "") == "male")
		assert(appearance.get("actionFallbacks", {}) == {})
		assert(appearance.get("actions", {}).keys().size() == 6)
		var catalog_item: Dictionary = catalog_items.get(item_key, {})
		assert(int(catalog_item.get("paperDoll", {}).get("sourceIndex", -1)) == int(expected[1]))
		assert(catalog_item.get("worldWear", {}).get("contractId", "") == EquipmentRules.MALE_WORLD_HELMET_EXTENSION_CONTRACT_ID)
		assert(catalog_item.get("worldWear", {}).get("helmetAppearance", {}) == appearance)
		assert(catalog_runtime.get(str(expected[0]), {}).get("helmetAppearance", {}) == appearance)
		var runtime_item := GameData.get_item(str(expected[0]))
		assert(not runtime_item.is_empty(), "runtime catalog missing helmet: %s" % expected[0])
		assert(runtime_item.get("name", "") == expected[0])

	assert(items.get("147", {}).get("maleAppearance", {}) == items.get("148", {}).get("maleAppearance", {}))
	var black_actions: Dictionary = identities.get("black_iron", {}).get("actions", {})
	assert(str(black_actions.get("cast", {}).get("path", "")).ends_with("black_iron_helmet_cast.png"))
	assert(
		black_actions.get("cast", {}).get("atlasRgbaSha256", "")
		!= black_actions.get("idle", {}).get("atlasRgbaSha256", "")
	)
	assert(int(catalog.get("coverage", {}).get("exactMaleWorldWear", 0)) == 55)
	print(
		"EQUIPMENT_MALE_WORLD_HELMET_GODOT_TEST_PASS "
		+ "items=12 identities=11 atlases=66 logical_cells=2784"
	)
	get_tree().quit(0)
