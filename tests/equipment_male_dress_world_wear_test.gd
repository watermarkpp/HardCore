extends Node


const CONTRACT_PATH := "res://assets/data/equipment_male_dress_world_wear.json"
const CATALOG_PATH := "res://assets/data/equipment_visual_catalog.json"
const EXPECTED_ACTIONS := {
	"idle": 4,
	"walk": 6,
	"attack": 6,
	"cast": 6,
	"hit": 3,
	"death": 4,
}
const EXPECTED_ITEM_FEATURES := {
	116: 2,
	118: 4,
	120: 4,
	122: 6,
	128: 6,
	140: 12,
	124: 8,
	130: 8,
	142: 14,
	126: 10,
	132: 10,
	144: 16,
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
	assert(contract.get("contractId", "") == "equipment.world_wear.male_dress.v1")
	assert(contract.get("sex", "") == "male")
	assert(bool(contract.get("mappingPolicy", {}).get("femaleExcluded", false)))
	_assert_int_array(contract.get("actorContract", {}).get("cell", []), [192, 160], "cell")
	_assert_int_array(contract.get("actorContract", {}).get("actorOrigin", []), [64, 80], "actorOrigin")
	assert(not bool(contract.get("actorContract", {}).get("footPointContractChanged", true)))
	assert(str(contract.get("source", {}).get("sha256", {}).get("wil", "")).length() == 64)
	assert(str(contract.get("source", {}).get("sha256", {}).get("wix", "")).length() == 64)
	var acceptance: Dictionary = contract.get("acceptance", {})
	assert(bool(acceptance.get("automaticRemappingProhibited", false)))
	var full_review: Dictionary = acceptance.get("fullAtlasUserReview", {})
	assert(full_review.get("authority", "") == "explicit_user_confirmation")
	assert(int(full_review.get("mappingCount", 0)) == 12)
	assert(int(full_review.get("femaleAssetsConfirmed", -1)) == 0)
	assert(str(full_review.get("reviewManifestSha256", "")).length() == 64)
	_assert_int_array(full_review.get("sharedFeatureGroups", {}).get("4", []), [118, 120], "dress review feature4")
	_assert_int_array(full_review.get("sharedFeatureGroups", {}).get("6", []), [122, 128], "dress review feature6")
	_assert_int_array(full_review.get("sharedFeatureGroups", {}).get("8", []), [124, 130], "dress review feature8")
	_assert_int_array(full_review.get("sharedFeatureGroups", {}).get("10", []), [126, 132], "dress review feature10")

	var features: Dictionary = contract.get("featureFamilies", {})
	assert(features.size() == 9)
	var loaded_paths: Dictionary = {}
	for feature_key: String in features:
		assert(int(feature_key) % 2 == 0)
		var feature: Dictionary = features[feature_key]
		assert(feature.get("sex", "") == "male")
		for action: String in EXPECTED_ACTIONS:
			var action_record: Dictionary = feature.get("actions", {}).get(action, {})
			assert(int(action_record.get("directions", 0)) == 8)
			assert(int(action_record.get("framesPerDirection", 0)) == int(EXPECTED_ACTIONS[action]))
			assert(int(action_record.get("decodedFrameCount", 0)) == 8 * int(EXPECTED_ACTIONS[action]))
			assert(action_record.get("missingFrames", []).is_empty())
			assert(action_record.get("pixelActionConfidence", "") == "A")
			var path := str(action_record.get("path", ""))
			assert(path.contains("/dress/male/"))
			assert(not path.contains("/female/"))
			assert(ResourceLoader.exists(path), "male dress atlas missing: %s" % path)
			if not loaded_paths.has(path):
				var texture := load(path) as Texture2D
				assert(texture != null)
				assert(texture.get_width() == 192 * int(EXPECTED_ACTIONS[action]))
				assert(texture.get_height() == 160 * 8)
				loaded_paths[path] = true

	var items: Dictionary = contract.get("itemsById", {})
	assert(items.size() == 12)
	var runtime: Dictionary = catalog.get("runtimeMappings", {})
	for item_key: String in items:
		var item: Dictionary = items[item_key]
		assert(int(item.get("itemId", -1)) == int(item_key))
		assert(item.get("sex", "") == "male")
		var confidence := str(item.get("mappingAssessment", {}).get("confidence", ""))
		assert(confidence == "user_confirmed_full_atlas_review")
		assert(confidence != "A")
		var item_review: Dictionary = item.get("userAtlasReviewEvidence", {})
		assert(item_review.get("authority", "") == "explicit_user_confirmation")
		assert(bool(item_review.get("confirmed", false)))
		assert(str(item_review.get("reviewManifestSha256", "")) == str(full_review.get("reviewManifestSha256", "")))
		var appearance: Dictionary = item.get("maleAppearance", {})
		assert(appearance.get("sex", "") == "male")
		assert(int(appearance.get("feature", -1)) == int(appearance.get("shape", -1)) * 2)
		assert(int(appearance.get("feature", -1)) == int(EXPECTED_ITEM_FEATURES.get(int(item_key), -2)))
		var runtime_appearance: Dictionary = runtime.get(str(item.get("itemName", "")), {}).get("dressAppearance", {})
		assert(int(runtime_appearance.get("feature", -1)) == int(appearance.get("feature", -2)))
		for action: String in EXPECTED_ACTIONS:
			var path := str(appearance.get("actions", {}).get(action, {}).get("path", ""))
			assert(path == str(runtime_appearance.get("actions", {}).get(action, {}).get("path", "")))

	print("EQUIPMENT_MALE_DRESS_WORLD_WEAR_GODOT_TEST_PASS items=12 atlases=%d" % loaded_paths.size())
	get_tree().quit(0)
