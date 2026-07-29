extends Node

const EDITOR_SCENE := preload("res://tools/helmet_calibration_tool.tscn")
const ITEM_ID := 240
const DRAFT_PATH := "res://assets/data/helmet_calibration_drafts/item_240.json"
const ACTIVE_TARGET_PATH := "res://assets/data/helmet_calibration_active_target.json"
const PREVIEW_ROOT := (
	"res://outputs/visual_acceptance/helmet_240_loaded_preview"
)
const RUNTIME_ROOT := PREVIEW_ROOT + "/runtime"
const ACTIONS := {
	"idle": 4,
	"walk": 6,
	"attack": 6,
	"cast": 6,
	"hit": 3,
	"death": 4,
}
const ACTION_ORDER := ["idle", "walk", "attack", "cast", "hit", "death"]
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const FRAME_CANVAS := Vector2i(256, 256)
const ATLAS_CELL := Vector2i(192, 160)
const FOOT_POINT := Vector2i(128, 190)
const BACKGROUND := Color("111418")
const PROTECTED_PATHS := [
	DRAFT_PATH,
	"res://assets/data/helmet_calibration_drafts/item_146.json",
	"res://assets/data/helmet_calibration_drafts/item_147.json",
	"res://assets/data/helmet_calibration_drafts/item_149.json",
	"res://assets/data/helmet_calibration_drafts/item_150.json",
	"res://assets/data/helmet_calibration_drafts/item_151.json",
	"res://assets/data/helmet_calibration_drafts/item_218.json",
	"res://assets/data/helmet_calibration_drafts/item_224.json",
	"res://assets/data/helmet_calibration_drafts/item_228.json",
	"res://assets/data/helmet_calibration_drafts/item_232.json",
	"res://assets/data/helmet_calibration_drafts/item_236.json",
	"res://assets/data/equipment_helmet_visual_v2_overrides.json",
	"res://assets/data/equipment_visual_catalog.json",
	"res://assets/data/equipment_classic_avatar_head_patches.json",
	"res://assets/data/equipment_helmet_finalization_manifest.json",
]


func _ready() -> void:
	_run.call_deferred()


func _json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed


func _run() -> void:
	var protected_before := _protected_hashes()
	var draft := _json(DRAFT_PATH)
	assert(int(draft.get("itemId", -1)) == ITEM_ID)
	assert(bool(draft.get("previewPolicy", {}).get(
		"poseFrameIndependentSource", false
	)))
	var preview_manifest := _json(RUNTIME_ROOT + "/preview_manifest.json")
	assert(str(preview_manifest.get("draftSha256", "")) == (
		FileAccess.get_sha256(DRAFT_PATH)
	))
	assert(preview_manifest.get("hiddenHelmetActions", []) == ["death"])

	var editor: Node = EDITOR_SCENE.instantiate()
	editor.auto_run = false
	add_child(editor)
	assert(await editor.initialize_editor_runtime(false))
	assert(editor._load_active_target_manifest(ACTIVE_TARGET_PATH))
	editor.select_item(ITEM_ID)
	await get_tree().process_frame

	var output_dir := ProjectSettings.globalize_path(PREVIEW_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var atlas_by_action: Dictionary = {}
	for action: String in ACTION_ORDER:
		var atlas_path := (
			RUNTIME_ROOT + "/heavenly_taoist_%s.png" % action
		)
		assert(FileAccess.file_exists(atlas_path), atlas_path)
		var atlas := Image.load_from_file(
			ProjectSettings.globalize_path(atlas_path)
		)
		assert(not atlas.is_empty())
		atlas_by_action[action] = atlas

	var records: Array[Dictionary] = []
	var overview := Image.create(
		FRAME_CANVAS.x * ACTION_ORDER.size(),
		FRAME_CANVAS.y * DIRECTIONS.size(),
		false,
		Image.FORMAT_RGBA8
	)
	overview.fill(BACKGROUND)
	for action_index: int in ACTION_ORDER.size():
		var action: String = ACTION_ORDER[action_index]
		var frame_count := int(ACTIONS[action])
		var action_sheet := Image.create(
			FRAME_CANVAS.x * frame_count,
			FRAME_CANVAS.y * DIRECTIONS.size(),
			false,
			Image.FORMAT_RGBA8
		)
		action_sheet.fill(BACKGROUND)
		for direction_index: int in DIRECTIONS.size():
			var direction: String = DIRECTIONS[direction_index]
			var runtime_row := int(draft.get(
				"directions", {}
			).get(direction, {}).get("source_row", direction_index))
			for frame_index: int in frame_count:
				var actor := _loaded_actor_frame(
					editor,
					atlas_by_action[action],
					action,
					direction_index,
					runtime_row,
					frame_index
				)
				action_sheet.blend_rect(
					actor,
					Rect2i(Vector2i.ZERO, FRAME_CANVAS),
					Vector2i(
						frame_index * FRAME_CANVAS.x,
						direction_index * FRAME_CANVAS.y
					)
				)
				var pose: Dictionary = editor.pose_transform(
					action, direction_index, frame_index
				)
				records.append({
					"action": action,
					"direction": direction,
					"frame": frame_index,
					"runtimeRow": runtime_row,
					"sourceRow": int(pose.get(
						"source_row", runtime_row
					)),
					"offset": pose.get("offset", [0, 0]),
					"scaleXPercent": int(pose.get(
						"scale_x_percent", 100
					)),
					"scaleYPercent": int(pose.get(
						"scale_y_percent", 100
					)),
					"rotationDegrees": float(pose.get(
						"rotation_degrees", 0.0
					)),
					"helmetVisible": action != "death",
				})
				if (
					frame_index == mini(
						frame_count / 2, frame_count - 1
					)
				):
					overview.blend_rect(
						actor,
						Rect2i(Vector2i.ZERO, FRAME_CANVAS),
						Vector2i(
							action_index * FRAME_CANVAS.x,
							direction_index * FRAME_CANVAS.y
						)
					)
		assert(action_sheet.save_png(
			output_dir.path_join("item_240_%s_all_frames.png" % action)
		) == OK)
	assert(overview.save_png(
		output_dir.path_join("item_240_loaded_overview.png")
	) == OK)
	assert(_protected_hashes() == protected_before)
	var manifest := {
		"schemaVersion": 1,
		"contractId": "equipment.helmet.loaded_preview.capture.v1",
		"itemId": ITEM_ID,
		"isolatedPreviewOnly": true,
		"formalRuntimeMappingModified": false,
		"draftPath": DRAFT_PATH,
		"draftSha256": FileAccess.get_sha256(DRAFT_PATH),
		"hiddenHelmetActions": ["death"],
		"sheetOrder": {
			"directionsTopToBottom": DIRECTIONS,
			"framesLeftToRight": true,
			"overviewActionsLeftToRight": ACTION_ORDER,
		},
		"records": records,
		"protectedHashesBefore": protected_before,
		"protectedHashesAfter": _protected_hashes(),
	}
	var manifest_file := FileAccess.open(
		output_dir.path_join("capture_manifest.json"), FileAccess.WRITE
	)
	assert(manifest_file != null)
	manifest_file.store_string(JSON.stringify(manifest, "\t", false) + "\n")
	manifest_file.close()
	editor.dispose_runtime_for_test()
	editor.queue_free()
	print(
		"EQUIPMENT_HELMET_240_LOADED_PREVIEW_CAPTURE_PASS "
		+ "all_frames=232 death_hidden=32 formal_changes=0"
	)
	get_tree().quit(0)


func _loaded_actor_frame(
	editor: Node,
	atlas: Image,
	action: String,
	direction_index: int,
	runtime_row: int,
	frame_index: int
) -> Image:
	var body: Image = editor._runtime_frame(
		action, direction_index, frame_index, false, false
	)
	var actor := Image.create(
		FRAME_CANVAS.x, FRAME_CANVAS.y, false, Image.FORMAT_RGBA8
	)
	actor.fill(Color(0, 0, 0, 0))
	actor.blend_rect(
		body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i.ZERO
	)
	var helmet_cell := atlas.get_region(Rect2i(
		frame_index * ATLAS_CELL.x,
		runtime_row * ATLAS_CELL.y,
		ATLAS_CELL.x,
		ATLAS_CELL.y
	))
	if action == "death":
		assert(
			helmet_cell.get_used_rect().size == Vector2i.ZERO,
			"death helmet cell must be transparent"
		)
		return actor
	assert(
		helmet_cell.get_used_rect().size != Vector2i.ZERO,
		"visible helmet cell is empty: %s/%s/%d"
		% [action, DIRECTIONS[direction_index], frame_index]
	)
	var helmet_layer := (
		editor._visual.get_node("ClientHelmetLayer") as Sprite2D
	)
	var destination := (
		FOOT_POINT
		+ Vector2i(editor._visual.position.round())
		+ Vector2i(helmet_layer.position.round())
	)
	actor.blend_rect(
		helmet_cell,
		Rect2i(Vector2i.ZERO, helmet_cell.get_size()),
		destination
	)
	return actor


func _protected_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in PROTECTED_PATHS:
		assert(FileAccess.file_exists(path), path)
		result[path] = FileAccess.get_sha256(path)
	return result
