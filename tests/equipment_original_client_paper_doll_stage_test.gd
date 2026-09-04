extends Node


const MANIFEST_PATH := "res://assets/data/equipment_original_client_paper_doll_stage.json"
const EXPECTED_DRAW_ORDER := ["base", "hair", "dress", "weapon", "helmet"]


func _ready() -> void:
	_run.call_deferred()


func _load_manifest() -> Dictionary:
	assert(FileAccess.file_exists(MANIFEST_PATH), "missing paper-doll manifest")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(parsed is Dictionary, "paper-doll manifest must be a Dictionary")
	return parsed


func _load_image(path: String, label: String) -> Image:
	assert(FileAccess.file_exists(path), "%s resource is missing: %s" % [label, path])
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		assert(texture != null, "%s texture failed to load" % label)
		var imported_image := texture.get_image()
		assert(imported_image != null and not imported_image.is_empty(), "%s image is empty" % label)
		return imported_image
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(image != null and not image.is_empty(), "%s source PNG failed to decode" % label)
	return image


func _assert_image_record(record: Dictionary, label: String) -> void:
	var path := str(record.get("path", ""))
	assert(not path.is_empty(), "%s missing resource path" % label)
	var image := _load_image(path, label)
	var size: Array = record.get("size", [])
	assert(size.size() == 2, "%s size must contain two values" % label)
	assert(image.get_width() == int(size[0]), "%s width changed" % label)
	assert(image.get_height() == int(size[1]), "%s height changed" % label)


func _assert_int_array(actual: Variant, expected: Array, label: String) -> void:
	assert(actual is Array, "%s must be an Array" % label)
	assert(actual.size() == expected.size(), "%s length changed" % label)
	for index: int in expected.size():
		assert(int(actual[index]) == int(expected[index]), "%s value %d changed" % [label, index])


func _run() -> void:
	var manifest := _load_manifest()
	assert(manifest.get("contractId", "") == "equipment.paper_doll.original_client_stage.v1")
	assert(manifest.get("sex", "") == "male")
	assert(manifest.get("presentationRole", "") == "legacy_audit_full_panel")
	assert(bool(manifest.get("forbiddenForPlayerUI", false)))
	assert(str(manifest.get("presentationModesRef", "")).ends_with("equipment_paper_doll_presentation_modes.json"))
	_assert_int_array(manifest.get("canvasSize", []), [232, 325], "canvasSize")
	_assert_int_array(manifest.get("viewportOrigin", []), [0, 0], "viewportOrigin")
	_assert_int_array(manifest.get("viewportBounds", []), [0, 0, 232, 325], "viewportBounds")

	var composition: Dictionary = manifest.get("composition", {})
	_assert_int_array(composition.get("baseScreenOrigin", []), [38, 52], "baseScreenOrigin")
	_assert_int_array(composition.get("equipmentScreenAnchor", []), [31, 96], "equipmentScreenAnchor")
	_assert_int_array(composition.get("viewportOrigin", []), [0, 0], "composition.viewportOrigin")
	assert(composition.get("drawOrder", []) == EXPECTED_DRAW_ORDER)

	var stage: Dictionary = manifest.get("stage", {})
	assert(int(stage.get("sourceIndex", -1)) == 376)
	_assert_int_array([stage.get("hotX", 0), stage.get("hotY", 0)], [7, -44], "stage Hot")
	_assert_int_array(stage.get("stagePosition", []), [38, 52], "stagePosition")
	var source_policy: Dictionary = manifest.get("sourcePolicy", {})
	var runtime_composition: Dictionary = source_policy.get("runtimeComposition", {})
	assert(runtime_composition.get("output", "") == "single_composited_paper_doll_layer")
	assert(runtime_composition.get("stageLayerMode", "") == "opaque")
	assert(runtime_composition.get("overlayLayerMode", "") == "transparent_color_key")
	_assert_image_record(stage, "Prguse376 stage")

	var hair: Dictionary = manifest.get("hair", {})
	assert(int(hair.get("sourceIndex", -1)) == 442)
	_assert_int_array([hair.get("hotX", 0), hair.get("hotY", 0)], [87, 0], "hair Hot")
	_assert_int_array(hair.get("stagePosition", []), [118, 96], "hair stagePosition")
	_assert_image_record(hair, "Prguse442 hair")

	var coverage: Dictionary = manifest.get("coverage", {})
	assert(int(coverage.get("mappedItems", 0)) == 61)
	assert(int(coverage.get("uniqueStateItemRecords", 0)) == 55)
	assert(int(coverage.get("completeRectangles", 0)) == 61)
	assert(int(coverage.get("croppedOrMattedRecords", -1)) == 0)

	var items: Dictionary = manifest.get("itemsById", {})
	assert(items.size() == 61)
	for item_id: String in items:
		var entry: Dictionary = items[item_id]
		assert(int(entry.get("itemId", -1)) == int(item_id))
		var record: Dictionary = entry.get("originalClientPaperDoll", {})
		var expected_position := [
			31 + int(record.get("hotX", 0)),
			96 + int(record.get("hotY", 0)),
		]
		_assert_int_array(record.get("stagePosition", []), expected_position, "item %s stagePosition" % item_id)
		assert(str(record.get("recordPolicy", "")).contains("no crop"))
		_assert_image_record(record, "item %s" % item_id)

	print("EQUIPMENT_ORIGINAL_CLIENT_PAPER_DOLL_STAGE_GODOT_TEST_PASS items=61")
	get_tree().quit(0)
