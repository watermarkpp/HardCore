extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const ACTIONS := {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "death": 4}
const EXPECTED_ELF_ROWS := [4, 3, 2, 1, 0, 7, 6, 5]
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
		+ "helmet_local_pivot(action,direction,frame) + integer_nudge"
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
	assert(total_sockets == 184)
	assert(unique_sockets.size() > 100)
	assert(int(moving_actions.attack) > 30)
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
		assert(record.get("nudge", []) == [0.0, 0.0])
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

	var golden := _json("res://assets/data/equipment_helmet_151_golden_reference.json")
	assert(golden.get("readOnly", false))
	assert(int(golden.get("pixelDiffTolerance", -1)) == 0)
	assert(not str(golden.get("compatibilityPivotPolicy", "")).is_empty())
	for action: String in ACTIONS:
		var golden_action: Dictionary = golden.get("actions", {}).get(action, {})
		assert(not str(golden_action.get("bodyAtlasSha256", "")).is_empty())
		assert(not str(golden_action.get("helmetAtlasSha256", "")).is_empty())
		assert(FileAccess.file_exists(
			"res://assets/art/items/client/world_wear/dress/male/dress_002_%s.png" % action
		))
		assert(FileAccess.file_exists(
			"res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_%s.png" % action
		))
		for direction_index: int in 8:
			assert(HelmetVisualV2.source_direction_row(151, direction_index) == direction_index)
			for frame_index: int in int(ACTIONS[action]):
				assert(
					HelmetVisualV2.final_position_delta(
						151,
						"player.male.cloth_002",
						action,
						direction_index,
						frame_index
					) == Vector2i.ZERO
				)

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
	assert(not HelmetVisualV2.persist_calibration_override(
		151, 0, {"nudge": [1, 0]}
	))

	for file_name: String in [
		"helmet_146_idle_8dir_1x.png",
		"helmet_146_idle_8dir_8x.png",
		"helmet_146_direction_audit.json",
		"helmet_146_validation_report.json",
	]:
		assert(FileAccess.file_exists("%s/%s" % [OUTPUT_ROOT, file_name]), "missing %s" % file_name)
	var report := _json("%s/helmet_146_validation_report.json" % OUTPUT_ROOT)
	assert(bool(report.get("passed", false)))
	assert(int(report.get("headSocketRecords", 0)) == 184)
	assert(int(report.get("golden151PixelDiff", -1)) == 0)
	print("EQUIPMENT_HELMET_VISUAL_V2_TEST_PASS sockets=184 pilot=146 golden151_diff=0")
	get_tree().quit(0)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary)
	return parsed
