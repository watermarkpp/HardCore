extends Node


const CONTRACT_PATH := "res://assets/data/equipment_male_weapon_world_wear.json"
const CATALOG_PATH := "res://assets/data/equipment_visual_catalog.json"
const COMPATIBILITY_PATH := "res://assets/data/equipment_primary_weapon_compatibility.json"
const HIDDEN_IDS: Array[int] = []
const UNRESOLVED_IDS := [111]
const REQUIRED_PRIMARY_APPEARANCES := {
	80: [2, "sword"],
	82: [2, "sword"],
	88: [14, "axe"],
	99: [22, "axe"],
	105: [48, "staff"],
	107: [50, "sword"],
	108: [52, "blade"],
	109: [54, "staff"],
	110: [58, "sword"],
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
	var compatibility := _json(COMPATIBILITY_PATH)
	assert(contract.get("contractId", "") == "equipment.world_wear.male_weapon.v1")
	assert(compatibility.get("contractId", "") == "equipment.weapon_compatibility.primary.v1")
	assert(contract.get("sex", "") == "male")
	assert(bool(contract.get("mappingPolicy", {}).get("femaleExcluded", false)))
	assert(not bool(contract.get("mappingPolicy", {}).get("crystalShapeDirectMapping", true)))
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
	assert(int(compatibility.get("coverage", {}).get("anonymousPrimaryWeaponFeatures", -1)) == 0)
	var dragon_slayer: Dictionary = compatibility.get("itemsById", {}).get("108", {})
	assert(dragon_slayer.get("mappingType", "") == "user_confirmed_semantic_primary_weapon_feature")
	assert(int(dragon_slayer.get("classicWeaponShape", -1)) == 26)
	assert(int(dragon_slayer.get("maleFeature", -1)) == 52)
	assert(dragon_slayer.get("userConfirmation", {}).get("authority", "") == "explicit_user_confirmation")
	var dragon_coverage: Dictionary = dragon_slayer.get("weaponEvidence", {}).get("actionCoverage", {})
	assert(int(dragon_coverage.get("decodedFrames", 0)) == 232)
	assert(int(dragon_coverage.get("missingFrames", -1)) == 0)
	var destiny: Dictionary = compatibility.get("itemsById", {}).get("110", {})
	assert(destiny.get("status", "") == "resolved_primary_pixels")
	assert(destiny.get("mappingType", "") == "user_confirmed_semantic_primary_weapon_feature")
	assert(destiny.get("primaryServerQuery", {}).get("targetNameResult", {}).get("status", "") == "missing")
	assert(destiny.get("crystalShape") == null)
	assert(int(destiny.get("stateItemEvidence", {}).get("sourceIndex", -1)) == 65)
	assert(int(destiny.get("maleFeature", -1)) == 58)
	assert(destiny.get("visualWeaponClass", "") == "sword")
	assert(int(destiny.get("weaponEvidence", {}).get("actionCoverage", {}).get("decodedFrames", 0)) == 232)
	var full_review: Dictionary = compatibility.get("acceptance", {}).get("fullAtlasUserReview", {})
	assert(full_review.get("authority", "") == "explicit_user_confirmation")
	assert(int(full_review.get("mappingCount", 0)) == 36)
	_assert_int_array(full_review.get("unresolvedItemIds", []), [111], "weapon review unresolvedItemIds")
	assert(str(full_review.get("reviewManifestSha256", "")).length() == 64)

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
			assert(not item.has("maleAppearance"))
			assert(not runtime.has(str(item.get("itemName", ""))))
			var unresolved_compatibility: Dictionary = compatibility.get("itemsById", {}).get(item_key, {})
			assert(unresolved_compatibility.get("status", "") == "unresolved")
			assert(unresolved_compatibility.get("visualWeaponClass", "") == "unresolved")
			continue
		var appearance: Dictionary = item.get("maleAppearance", {})
		var runtime_appearance: Dictionary = runtime.get(str(item.get("itemName", "")), {}).get("weaponAppearance", {})
		assert(int(appearance.get("feature", -1)) == int(appearance.get("classicShape", -1)) * 2)
		assert(int(appearance.get("shape", -1)) == int(appearance.get("classicShape", -2)))
		var compatibility_record: Dictionary = compatibility.get("itemsById", {}).get(item_key, {})
		assert(compatibility_record.get("status", "") == "resolved_primary_pixels")
		if compatibility_record.get("crystalShape") == null:
			assert(not appearance.has("crystalShape"))
			assert(str(appearance.get("crystalShapeStatus", "")).contains("missing"))
			assert(compatibility_record.get("crystalShape") == null)
		else:
			assert(int(appearance.get("crystalShape", -1)) == int(compatibility_record.get("crystalShape", -2)))
		assert(int(appearance.get("classicShape", -1)) == int(compatibility_record.get("classicWeaponShape", -2)))
		assert(appearance.get("visualWeaponClass", "") == compatibility_record.get("visualWeaponClass", ""))
		assert(not bool(compatibility_record.get("crystalShapeUsedAsClassicShape", true)))
		assert(int(runtime_appearance.get("feature", -1)) == int(appearance.get("feature", -2)))
		var confidence := str(item.get("mappingAssessment", {}).get("confidence", ""))
		var expected_confidence := "primary_pixel_compatibility"
		if item_id == 88:
			expected_confidence = "integration_user_required_shared_primary_appearance"
		elif item_id in [108, 110]:
			expected_confidence = "user_confirmed_semantic_primary_weapon_feature"
		elif item_id in [99, 105, 107]:
			expected_confidence = "user_confirmed_primary_pixel_compatibility"
		assert(confidence == expected_confidence)
		assert(not bool(item.get("mappingAssessment", {}).get("crystalShapeUsedAsClassicShape", true)))
		visible_count += 1
		assert(status == "visible")
		assert(bool(appearance.get("visible", false)))
		assert(runtime_by_item_id.has(item_key))
		assert(runtime_by_item_id[item_key].get("weaponAppearance", {}) == appearance)
		for action: String in EXPECTED_ACTIONS:
			var path := str(appearance.get("actions", {}).get(action, {}).get("path", ""))
			assert(path == str(runtime_appearance.get("actions", {}).get(action, {}).get("path", "")))

	for required_item_id: int in REQUIRED_PRIMARY_APPEARANCES:
		var required_item: Dictionary = items.get(str(required_item_id), {})
		var required_appearance: Dictionary = required_item.get("maleAppearance", {})
		var expected: Array = REQUIRED_PRIMARY_APPEARANCES[required_item_id]
		assert(int(required_appearance.get("feature", -1)) == int(expected[0]))
		assert(required_appearance.get("visualWeaponClass", "") == str(expected[1]))
		var required_evidence: Dictionary = catalog.get("itemsById", {}).get(str(required_item_id), {}).get("worldWear", {}).get("shapeEvidence", {})
		var expected_evidence_confidence := "user_confirmed_semantic_primary_weapon_feature" if required_item_id in [108, 110] else "primary_pixel_compatibility"
		assert(required_evidence.get("confidence", "") == expected_evidence_confidence)

	assert(visible_count == 36)
	assert(hidden_count == 0)
	assert(unresolved_count == 1)
	print("EQUIPMENT_MALE_WEAPON_WORLD_WEAR_GODOT_TEST_PASS items=37 atlases=%d" % loaded_paths.size())
	get_tree().quit(0)
