extends Node


const CONTRACT_PATH := "res://assets/data/equipment_male_weapon_world_wear.json"
const CATALOG_PATH := "res://assets/data/equipment_visual_catalog.json"
const HIDDEN_IDS: Array[int] = []
const UNRESOLVED_IDS := [111]
const USER_EVIDENCE_IDS := [80, 82, 88, 108, 109]
const REQUIRED_IDENTITIES := {
	80: [1, 2, "sword", "通用"],
	82: [1, 2, "sword", "通用"],
	88: [7, 14, "axe", "战士"],
	99: [11, 22, "axe", "战士"],
	105: [24, 48, "staff", "战士"],
	107: [25, 50, "sword", "道士"],
	108: [26, 52, "blade", "战士"],
	109: [27, 54, "staff", "法师"],
}
const EXPECTED_ACTIONS := {
	"idle": 4,
	"walk": 6,
	"attack": 6,
	"cast": 6,
	"hit": 3,
	"death": 4,
}


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
	assert(contract.get("contractId", "") == "equipment.world_wear.male_weapon.v1")
	assert(contract.get("sex", "") == "male")
	assert(bool(contract.get("mappingPolicy", {}).get("femaleExcluded", false)))
	var taxonomy: Dictionary = contract.get("visualWeaponClassTaxonomy", {})
	var classes: Dictionary = taxonomy.get("classes", {})
	assert(classes.size() == 7)
	assert(str(taxonomy.get("axis", "")).contains("independent from profession"))
	assert(str(classes.get("staff", {}).get("semantic", "")).contains("long-handled"))
	_assert_int_array(contract.get("actorContract", {}).get("cell", []), [224, 224], "cell")
	_assert_int_array(contract.get("actorContract", {}).get("actorOrigin", []), [80, 116], "actorOrigin")
	_assert_int_array(contract.get("actorContract", {}).get("footPoint", []), [80, 116], "footPoint")
	assert(not bool(contract.get("actorContract", {}).get("footPointContractChanged", true)))
	var coverage: Dictionary = contract.get("coverage", {})
	assert(int(coverage.get("formalWeapons", 0)) == 37)
	assert(int(coverage.get("visible", 0)) == 36)
	assert(int(coverage.get("hiddenByClassicRule", -1)) == 0)
	assert(int(coverage.get("unresolved", 0)) == 1)
	assert(int(coverage.get("maleWeaponFeatureFamilies", 0)) == 34)
	assert(int(coverage.get("transparentEmptyFrames", 0)) == 232)

	var features: Dictionary = contract.get("featureFamilies", {})
	assert(features.size() == 34)
	var runtime_by_item_id: Dictionary = contract.get("runtimeMappingsByItemId", {})
	assert(runtime_by_item_id.size() == 36)
	var loaded_paths: Dictionary = {}
	for feature_key: String in features:
		assert(int(feature_key) % 2 == 0)
		var feature: Dictionary = features[feature_key]
		assert(feature.get("sex", "") == "male")
		_assert_int_array(feature.get("footPoint", []), [80, 116], "feature footPoint")
		for action: String in EXPECTED_ACTIONS:
			var action_record: Dictionary = feature.get("actions", {}).get(action, {})
			assert(int(action_record.get("directions", 0)) == 8)
			assert(int(action_record.get("framesPerDirection", 0)) == int(EXPECTED_ACTIONS[action]))
			assert(int(action_record.get("decodedFrameCount", 0)) == 8 * int(EXPECTED_ACTIONS[action]))
			assert(action_record.get("missingFrames", []).is_empty())
			assert(action_record.get("pixelActionConfidence", "") == "A")
			_assert_int_array(action_record.get("footPoint", []), [80, 116], "action footPoint")
			var expected_empty_count := 8 * int(EXPECTED_ACTIONS[action]) if int(feature_key) == 0 else 0
			assert(action_record.get("transparentEmptyFrames", []).size() == expected_empty_count)
			var path := str(action_record.get("path", ""))
			assert(path.contains("/weapon/male/"))
			assert(not path.contains("/female/"))
			assert(ResourceLoader.exists(path), "male weapon atlas missing: %s" % path)
			if not loaded_paths.has(path):
				var texture := load(path) as Texture2D
				assert(texture != null)
				assert(texture.get_width() == 224 * int(EXPECTED_ACTIONS[action]))
				assert(texture.get_height() == 224 * 8)
				loaded_paths[path] = true

	var items: Dictionary = contract.get("itemsById", {})
	assert(items.size() == 37)
	var runtime: Dictionary = catalog.get("runtimeMappings", {})
	var visible_count := 0
	var hidden_count := 0
	var unresolved_count := 0
	for item_key: String in items:
		var item_id := int(item_key)
		var item: Dictionary = items[item_key]
		assert(int(item.get("itemId", -1)) == item_id)
		assert(item.get("sex", "") == "male")
		var status := str(item.get("status", ""))
		if item_id in UNRESOLVED_IDS:
			unresolved_count += 1
			assert(status == "unresolved")
			assert(item.get("visualWeaponClass", "") == "unresolved")
			assert(not item.has("maleAppearance"))
			assert(not runtime.has(str(item.get("itemName", ""))))
			continue
		var appearance: Dictionary = item.get("maleAppearance", {})
		var runtime_appearance: Dictionary = runtime.get(str(item.get("itemName", "")), {}).get("weaponAppearance", {})
		assert(int(appearance.get("feature", -1)) == int(appearance.get("shape", -1)) * 2)
		assert(int(runtime_appearance.get("feature", -1)) == int(appearance.get("feature", -2)))
		var assessment: Dictionary = item.get("mappingAssessment", {})
		assert(assessment.get("confidence", "") == "A")
		assert(str(assessment.get("source", "")).contains("mylgd_mir2server_176"))
		assert(item.get("visualWeaponClass", "") == appearance.get("visualWeaponClass", ""))
		assert(item.get("visualWeaponClassEvidence", {}).get("confidence", "") == "manually_verified")
		var expected_profile := "weapon.hold.%s.source_hot.v1" % str(item.get("visualWeaponClass", ""))
		assert(item.get("weaponHoldAnchorProfile", "") == expected_profile)
		assert(appearance.get("holdAnchorProfile", "") == expected_profile)
		visible_count += 1
		assert(status == "visible")
		assert(bool(appearance.get("visible", false)))
		assert(runtime_by_item_id.has(item_key))
		assert(runtime_by_item_id[item_key].get("weaponAppearance", {}) == appearance)
		for action: String in EXPECTED_ACTIONS:
			var path := str(appearance.get("actions", {}).get(action, {}).get("path", ""))
			assert(path == str(runtime_appearance.get("actions", {}).get(action, {}).get("path", "")))
		if item_id in USER_EVIDENCE_IDS:
			var evidence: Dictionary = catalog.get("itemsById", {}).get(item_key, {}).get("worldWear", {}).get("shapeEvidence", {})
			assert(evidence.get("confidence", "") == "A")
			assert(evidence.has("userEvidence"))
		if REQUIRED_IDENTITIES.has(item_id):
			var expected: Array = REQUIRED_IDENTITIES[item_id]
			assert(int(appearance.get("shape", -1)) == int(expected[0]))
			assert(int(appearance.get("feature", -1)) == int(expected[1]))
			assert(appearance.get("visualWeaponClass", "") == expected[2])
			assert(item.get("profession", "") == expected[3])

	assert(visible_count == 36)
	assert(hidden_count == 0)
	assert(unresolved_count == 1)
	print("EQUIPMENT_MALE_WEAPON_WORLD_WEAR_GODOT_TEST_PASS items=37 atlases=%d" % loaded_paths.size())
	get_tree().quit(0)
