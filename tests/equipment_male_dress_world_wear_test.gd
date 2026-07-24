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
		assert(confidence == ("manually_confirmed" if int(item_key) == 128 else "B"))
		assert(confidence != "A")
		var appearance: Dictionary = item.get("maleAppearance", {})
		assert(appearance.get("sex", "") == "male")
		assert(int(appearance.get("feature", -1)) == int(appearance.get("shape", -1)) * 2)
		var runtime_appearance: Dictionary = runtime.get(str(item.get("itemName", "")), {}).get("dressAppearance", {})
		assert(int(runtime_appearance.get("feature", -1)) == int(appearance.get("feature", -2)))
		for action: String in EXPECTED_ACTIONS:
			var path := str(appearance.get("actions", {}).get(action, {}).get("path", ""))
			assert(path == str(runtime_appearance.get("actions", {}).get(action, {}).get("path", "")))

	print("EQUIPMENT_MALE_DRESS_WORLD_WEAR_GODOT_TEST_PASS items=12 atlases=%d" % loaded_paths.size())
	get_tree().quit(0)
