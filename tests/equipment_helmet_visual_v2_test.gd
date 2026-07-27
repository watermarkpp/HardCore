extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const ACTIONS := {
	"idle": 4, "walk": 6, "attack": 6, "cast": 6, "hit": 3, "death": 4,
}
const EXPECTED_ELF_ROWS := [4, 5, 6, 1, 0, 7, 2, 3]
const EXPECTED_BLACK_ROWS := [0, 1, 7, 2, 4, 3, 6, 5]
const EXPECTED_CALIBRATION_ITEMS := [
	146, 147, 149, 150, 151, 218, 224, 228, 232, 236, 240,
]
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_calibration"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract := HelmetVisualV2.contract()
	var sockets := HelmetVisualV2.head_socket_database()
	assert(contract.get("contractId", "") == EquipmentRules.PLAYER_VISUAL_HELMET_V2_CONTRACT_ID)
	assert(sockets.get("contractId", "") == HelmetVisualV2.HEAD_SOCKET_CONTRACT_ID)
	assert(contract.get("canonicalDirections", []) == DIRECTIONS)
	assert(sockets.get("canonicalDirections", []) == DIRECTIONS)
	assert(contract.get("runtimeFormula", "") == (
		"final_position = body_head_socket - "
		+ "source_helmet_local_pivot(action,source_row,frame) + integer_nudge"
	))
	assert(contract.get("policies", {}).get("runtimeScalingForbidden", false))
	assert(contract.get("policies", {}).get("horizontalFlipForbidden", false))
	assert(contract.get("policies", {}).get("rotationForbidden", false))
	assert(contract.get("policies", {}).get("bakedPlayerFaceForbidden", false))
	assert(FileAccess.file_exists(str(contract.get("calibrationOverride", ""))))
	assert(contract.get("maskComposition", {}).get("ordinarySpriteOverlayForbidden", false))

	var pipeline: Array = contract.get("renderPipeline", [])
	assert(pipeline == [
		"helmet_back",
		"body_and_original_face",
		"helmet_front",
		"head_occlusion_mask",
	])
	var total_sockets := 0
	var unique_sockets: Dictionary = {}
	var moving_actions: Dictionary = {}
	for action: String in ACTIONS:
		var action_sockets: Dictionary = {}
		for direction_index: int in 8:
			for frame_index: int in int(ACTIONS[action]):
				var socket := HelmetVisualV2.body_head_socket(
					"player.male.cloth_002", action, direction_index, frame_index
				)
				assert(socket != Vector2i.ZERO)
				var frame_record: Dictionary = sockets.get("playerVisuals", {}).get(
					"player.male.cloth_002", {}
				).get("actions", {}).get(action, {}).get("directions", {}).get(
					DIRECTIONS[direction_index], []
				)[frame_index]
				var evidence: Dictionary = frame_record.get("evidence", {})
				assert(str(evidence.get("derivation", "")) == "round_same_frame_hair_alpha_centroid")
				assert(str(evidence.get("hairSourceRgbaSha256", "")).length() == 64)
				unique_sockets["%d,%d" % [socket.x, socket.y]] = true
				action_sockets["%d,%d" % [socket.x, socket.y]] = true
				total_sockets += 1
		moving_actions[action] = action_sockets.size()
	assert(total_sockets == 232)
	assert(unique_sockets.size() > 100)
	assert(int(moving_actions.attack) > 30)
	assert(int(moving_actions.cast) > 30)
	assert(int(moving_actions.hit) > 15)
	assert(int(moving_actions.death) > 25)

	var source_rows: Dictionary = {}
	for direction_index: int in 8:
		var record := HelmetVisualV2.direction_record(146, direction_index)
		assert(not record.is_empty())
		assert(int(record.get("source_row", -1)) == EXPECTED_ELF_ROWS[direction_index])
		assert(str(record.get("source_direction", "")) == DIRECTIONS[direction_index])
		assert(str(record.get("face_policy", "")) in ["open_crown", "half_open", "closed"])
		assert(str(record.get("hair_policy", "")) in ["keep", "clip", "hide"])
		assert(str(record.get("status", "")) == "valid")
		assert(bool(record.get("locked", false)))
		assert(record.get("pivotByActionFrame", {}).get("idle", []).size() == 4)
		assert(record.get("pivotByActionFrame", {}).get("attack", []).size() == 6)
		assert(record.get("pivotByActionFrame", {}).get("cast", []).size() == 6)
		var nudge: Variant = record.get("nudge", [])
		assert(nudge is Array and nudge.size() == 2)
		assert(float(nudge[0]) == floorf(float(nudge[0])))
		assert(float(nudge[1]) == floorf(float(nudge[1])))
		assert(record.get("runtime_scale", []) == [1.0, 1.0])
		assert(not bool(record.get("flip_h", true)))
		assert(record.get("layers", {}).get("helmet_back", "unexpected") == null)
		assert(record.get("layers", {}).get("head_occlusion_mask", "unexpected") == null)
		for action: String in ACTIONS:
			for frame_index: int in int(ACTIONS[action]):
				var delta := HelmetVisualV2.final_position_delta(
					146, "player.male.cloth_002", action, direction_index, frame_index
				)
				assert(delta.x is int and delta.y is int)
		source_rows[int(record.get("source_row", -1))] = true
	assert(source_rows.size() == 8)
	assert(str(HelmetVisualV2.direction_record(146, 0).get("openingVisibility", "")) == "none")
	assert(str(HelmetVisualV2.direction_record(146, 4).get("openingVisibility", "")) == "full")
	assert(str(contract.get("itemVisualAssetRefs", {}).get("147", "")) == "bronze_magic")
	assert(str(contract.get("itemVisualAssetRefs", {}).get("148", "")) == "bronze_magic")
	assert(
		contract.get("sharedVisualAssets", {}).get("bronze_magic", {}).get("itemIds", [])
		== [147.0, 148.0]
	)
	var item_refs: Dictionary = contract.get("itemVisualAssetRefs", {})
	assert(item_refs.size() == 12)
	var calibration_items: Array = HelmetVisualV2.calibration_items()
	assert(calibration_items.size() == EXPECTED_CALIBRATION_ITEMS.size())
	for index: int in calibration_items.size():
		var calibration_item: Dictionary = calibration_items[index]
		assert(
			int(calibration_item.get("calibrationItemId", -1))
			== EXPECTED_CALIBRATION_ITEMS[index]
		)
		var asset := HelmetVisualV2.visual_asset_for_item(
			int(calibration_item.get("calibrationItemId", -1))
		)
		assert(not asset.is_empty())
		for action: String in ACTIONS:
			assert(not HelmetVisualV2.base_action_texture_path(
				int(calibration_item.get("calibrationItemId", -1)),
				action,
				0,
				"helmet_front"
			).is_empty())
	assert(HelmetVisualV2.calibration_item_id_for_item(148) == 147)

	var golden := _json("res://assets/data/equipment_helmet_151_golden_reference.json")
	assert(not golden.get("readOnly", true))
	assert(golden.get("superseded", false))
	assert(not golden.get("runtimeValidationGate", true))
	assert(int(golden.get("historicalPixelDiffTolerance", -1)) == 0)
	assert(not str(golden.get("compatibilityPivotPolicy", "")).is_empty())
	var black_asset: Dictionary = HelmetVisualV2.visual_asset_for_item(151)
	assert(not HelmetVisualV2.is_read_only(151))
	assert(black_asset.get("editableSourceSlots", false))
	for action: String in ACTIONS:
		var source_evidence: Dictionary = black_asset.get(
			"source", {}
		).get("actions", {}).get(action, {})
		var source_path := str(source_evidence.get("path", ""))
		assert(FileAccess.file_exists(source_path))
		assert(
			FileAccess.get_sha256(source_path)
			== str(source_evidence.get("sha256", ""))
		)
		var source_image := (load(source_path) as Texture2D).get_image()
		for direction_index: int in 8:
			var saved_direction := HelmetVisualV2.saved_direction_override(
				151, direction_index
			)
			var expected_row: int = int(saved_direction.get(
				"source_row", EXPECTED_BLACK_ROWS[direction_index]
			))
			assert(
				HelmetVisualV2.source_direction_row(151, direction_index)
					== expected_row
			)
			assert(str(
				HelmetVisualV2.direction_record(151, direction_index).get(
					"source_slot_id", ""
				)
			) == "slot_%d" % expected_row)
			for frame_index: int in int(ACTIONS[action]):
				var cell := source_image.get_region(Rect2i(
					frame_index * 192,
					expected_row * 160,
					192,
					160
				))
				assert(_has_opaque_pixel(cell))
	var black_recipe: Dictionary = black_asset.get("bakedSourceOverrides", {})
	assert(str(black_recipe.get("recipeId", "")) == (
		"black_iron_151.user_authorized_nw_from_ne_mirror.v2"
	))
	assert(not bool(black_recipe.get("runtimeFlip", true)))
	var black_rows: Dictionary = black_recipe.get("rows", {})
	assert(black_rows.size() == 1)
	assert(int(black_rows.get("5", {}).get("sourceRow", -1)) == 1)
	assert(str(black_rows.get("5", {}).get("direction", "")) == "NW")
	assert(str(black_rows.get("5", {}).get("sourceDirection", "")) == "NE")

	var destination := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	destination.fill(Color(1, 1, 1, 1))
	var mask := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 1, 1, 1))
	var masked := HelmetVisualV2.apply_alpha_mask(destination, mask, Vector2i(1, 1))
	assert(masked.get_pixel(1, 1).a == 0.0)
	assert(masked.get_pixel(0, 0).a == 1.0)
	assert(HelmetVisualV2.set_session_calibration_override(
		146, 0, {"nudge": [1, 0]}
	))
	var session_nudge: Array = HelmetVisualV2.direction_record(146, 0).get("nudge", [])
	assert(Vector2i(int(session_nudge[0]), int(session_nudge[1])) == Vector2i.RIGHT)
	HelmetVisualV2.reload_data()
	assert(HelmetVisualV2.set_session_calibration_override(
		151, 0, {
			"source_row": 3,
			"source_slot_id": "slot_3",
			"nudge": [1, 0],
			"status": "valid",
		}
	))
	assert(HelmetVisualV2.source_direction_row(151, 0) == 3)
	HelmetVisualV2.reload_data()
	assert(HelmetVisualV2.set_session_calibration_override(
		148, 0, {
			"source_row": 2,
			"source_slot_id": "slot_2",
			"nudge": [2, 1],
			"status": "valid",
		}
	))
	assert(HelmetVisualV2.source_direction_row(147, 0) == 2)
	assert(HelmetVisualV2.source_direction_row(148, 0) == 2)
	HelmetVisualV2.reload_data()

	for file_name: String in [
		"helmet_146_idle_8dir_1x.png",
		"helmet_146_idle_8dir_8x.png",
		"helmet_146_direction_audit.json",
		"helmet_146_validation_report.json",
	]:
		assert(FileAccess.file_exists("%s/%s" % [OUTPUT_ROOT, file_name]), "missing %s" % file_name)
	var report := _json("%s/helmet_146_validation_report.json" % OUTPUT_ROOT)
	assert(bool(report.get("passed", false)))
	assert(int(report.get("headSocketRecords", 0)) == 232)
	assert(bool(report.get("historicalBaselineRejectedByUser", false)))
	assert(bool(report.get("source151", {}).get("passed", false)))
	print(
		"EQUIPMENT_HELMET_VISUAL_V2_TEST_PASS "
		+ "sockets=232 calibration_assets=11 item_ids=12 editable151=true cast=true"
	)
	get_tree().quit(0)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary)
	return parsed


func _has_opaque_pixel(image: Image) -> bool:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				return true
	return false
