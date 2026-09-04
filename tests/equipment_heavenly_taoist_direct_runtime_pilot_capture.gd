extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const ArtSpec := preload("res://scripts/art_spec.gd")
const EDITOR_SCENE := preload("res://tools/helmet_calibration_tool.tscn")
const ITEM_ID := 240
const DRAFT_PATH := "res://assets/data/helmet_calibration_drafts/item_240.json"
const ACTIVE_TARGET_PATH := "res://assets/data/helmet_calibration_active_target.json"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_direct_runtime_pilot_240"
const PROTECTED_PATHS := [
	DRAFT_PATH,
	"res://assets/data/equipment_visual_catalog.json",
	"res://assets/data/equipment_helmet_visual_v2_overrides.json",
	"res://assets/data/equipment_classic_avatar_head_patches.json",
]
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
const WORLD_CELL := Vector2i(192, 160)
const WORLD_FOOT_POINT := Vector2i(128, 190)
const FULL_FIGURE_DETAIL_CELL := Vector2i(256, 240)
const FULL_FIGURE_PADDING := 12
const FULL_FIGURE_MAX_ZOOM := 4.0
const PAPER_CANVAS := Vector2i(540, 340)
const BACKGROUND := Color("111418")
const PLAYER_VISUAL_ID := "player.male.cloth_002"


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
	assert(not bool(draft.get("finalized", true)))

	var editor: Node = EDITOR_SCENE.instantiate()
	editor.auto_run = false
	add_child(editor)
	assert(await editor.initialize_editor_runtime(true))
	assert(editor._load_active_target_manifest(ACTIVE_TARGET_PATH))
	editor.select_item(ITEM_ID)
	await get_tree().process_frame

	var world_capture := _capture_world(editor, draft)
	var presentation_capture := _capture_presentation(editor, draft)
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	assert(world_capture["sheet"].save_png(
		output_dir.path_join("item_240_direct_world_all_actions.png")
	) == OK)
	assert(world_capture["headDetail"].save_png(
		output_dir.path_join("item_240_direct_world_head_detail_4x.png")
	) == OK)
	assert(world_capture["fullFigureDetail"].save_png(
		output_dir.path_join("item_240_direct_world_full_figure_detail.png")
	) == OK)
	assert(presentation_capture["paperDoll"].save_png(
		output_dir.path_join("item_240_direct_paper_doll.png")
	) == OK)
	assert(presentation_capture["overview"].save_png(
		output_dir.path_join("item_240_direct_presentation_overview.png")
	) == OK)

	var manifest := {
		"schemaVersion": 1,
		"contractId": "equipment.helmet.direct_runtime_pilot_capture.v1",
		"itemId": ITEM_ID,
		"isolatedPilotOnly": true,
		"formalRuntimeMappingModified": false,
		"sourceDraft": DRAFT_PATH,
		"sourceDraftSha256": FileAccess.get_sha256(DRAFT_PATH),
		"renderPolicy": {
			"worldSource": "original_high_resolution_direction_png",
			"worldTextureScaleFormula": (
				"sourcePixelSize * 0.08 * savedScalePercent / 100"
			),
			"worldPlacement": "bodyHeadSocket + savedNudge",
			"actionRotation": (
				"angle(bodyFootAnchor->currentHeadSocket) "
				+ "- angle(bodyFootAnchor->idleHeadSocket)"
			),
			"rotationBaseline": "idle; walk remains authored zero-angle",
			"rotationPivot": "authored source visual centre at saved head centre",
			"actionDeformation": "uniform only; no aspect-ratio distortion",
			"persistentDownsample": false,
			"captureRasterizationOnly": true,
			"paperDoll": "original_high_resolution_selected_direction",
			"inventory": "original_high_resolution_dedicated_source",
			"ground": "original_high_resolution_dedicated_source",
		},
		"outputs": {
			"world": OUTPUT_ROOT + "/item_240_direct_world_all_actions.png",
			"worldHeadDetail": (
				OUTPUT_ROOT + "/item_240_direct_world_head_detail_4x.png"
			),
			"worldFullFigureDetail": (
				OUTPUT_ROOT
				+ "/item_240_direct_world_full_figure_detail.png"
			),
			"paperDoll": OUTPUT_ROOT + "/item_240_direct_paper_doll.png",
			"presentationOverview": (
				OUTPUT_ROOT + "/item_240_direct_presentation_overview.png"
			),
		},
		"world": world_capture["records"],
		"presentation": presentation_capture["records"],
		"protectedHashesBefore": protected_before,
	}
	assert(_protected_hashes() == protected_before)
	manifest["protectedHashesAfter"] = _protected_hashes()
	var manifest_file := FileAccess.open(
		output_dir.path_join("capture_manifest.json"), FileAccess.WRITE
	)
	assert(manifest_file != null)
	manifest_file.store_string(JSON.stringify(manifest, "\t", false) + "\n")
	manifest_file.close()
	print(
		"EQUIPMENT_HEAVENLY_TAOIST_DIRECT_RUNTIME_PILOT_CAPTURE_PASS "
		+ "isolated=true source=original_high_resolution "
		+ "actions=6 directions=8 rotation=body_axis_delta "
		+ "deformation=uniform_only formal_changes=0"
	)
	get_tree().quit(0)


func _capture_world(editor: Node, draft: Dictionary) -> Dictionary:
	var sheet := Image.create(
		WORLD_CELL.x * ACTION_ORDER.size(),
		WORLD_CELL.y * DIRECTIONS.size(),
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(BACKGROUND)
	var full_figure_detail := Image.create(
		FULL_FIGURE_DETAIL_CELL.x * ACTION_ORDER.size(),
		FULL_FIGURE_DETAIL_CELL.y * DIRECTIONS.size(),
		false,
		Image.FORMAT_RGBA8
	)
	full_figure_detail.fill(BACKGROUND)
	var records: Array[Dictionary] = []
	for action_index: int in ACTION_ORDER.size():
		var action: String = ACTION_ORDER[action_index]
		var frame_count := int(ACTIONS[action])
		var frame_index := frame_count - 1 if action == "death" else frame_count / 2
		for direction_index: int in DIRECTIONS.size():
			var direction: String = DIRECTIONS[direction_index]
			var direction_record: Dictionary = draft.get(
				"directions", {}
			).get(direction, {})
			var source_row := int(direction_record.get("source_row", -1))
			assert(source_row >= 0 and source_row < DIRECTIONS.size())
			var source: Image = editor._authored_source_cutout(source_row)
			assert(not source.is_empty())
			var scale_percent := int(
				direction_record.get("scale_percent", 100)
			)
			var display_size: Vector2 = editor.authored_world_display_size(
				source_row, scale_percent
			)
			var body: Image = editor._runtime_frame(
				action, direction_index, frame_index, false, false
			)
			var actor := Image.create(
				WORLD_CELL.x, WORLD_CELL.y, false, Image.FORMAT_RGBA8
			)
			actor.fill(Color(0, 0, 0, 0))
			actor.blend_rect(
				body,
				Rect2i(Vector2i.ZERO, body.get_size()),
				Vector2i.ZERO
			)
			var pivot: Vector2i = editor._calibration_pivot_for_source_row(
				action, source_row, frame_index
			)
			var helmet_layer := (
				editor._visual.get_node("ClientHelmetLayer") as Sprite2D
			)
			var centre: Vector2 = (
				Vector2(WORLD_FOOT_POINT)
				+ editor._visual.position
				+ helmet_layer.position
				+ Vector2(pivot)
			)
			var target_size := Vector2i(
				maxi(1, roundi(display_size.x)),
				maxi(1, roundi(display_size.y))
			)
			var rotation_radians := _pose_rotation_radians(
				action, direction_index, frame_index
			)
			var rotated_source := _rotated_high_resolution_copy(
				source, rotation_radians
			)
			var world_scale := (
				float(target_size.x) / float(source.get_width())
			)
			var rotated_target_size := Vector2i(
				maxi(1, roundi(rotated_source.get_width() * world_scale)),
				maxi(1, roundi(rotated_source.get_height() * world_scale))
			)
			var capture_texture := _scaled_copy(
				rotated_source,
				rotated_target_size,
				Image.INTERPOLATE_LANCZOS
			)
			var top_left := Vector2i(
				(centre - Vector2(rotated_target_size) * 0.5).round()
			)
			actor.blend_rect(
				capture_texture,
				Rect2i(Vector2i.ZERO, capture_texture.get_size()),
				top_left
			)
			var composed := Image.create(
				WORLD_CELL.x, WORLD_CELL.y, false, Image.FORMAT_RGBA8
			)
			composed.fill(BACKGROUND)
			composed.blend_rect(
				actor,
				Rect2i(Vector2i.ZERO, actor.get_size()),
				Vector2i.ZERO
			)
			sheet.blend_rect(
				composed,
				Rect2i(Vector2i.ZERO, WORLD_CELL),
				Vector2i(
					action_index * WORLD_CELL.x,
					direction_index * WORLD_CELL.y
				)
			)
			var full_figure_cell := _full_figure_detail_cell(actor)
			full_figure_detail.blend_rect(
				full_figure_cell,
				Rect2i(
					Vector2i.ZERO,
					FULL_FIGURE_DETAIL_CELL
				),
				Vector2i(
					action_index * FULL_FIGURE_DETAIL_CELL.x,
					direction_index * FULL_FIGURE_DETAIL_CELL.y
				)
			)
			records.append({
				"action": action,
				"direction": direction,
				"frame": frame_index,
				"sourceRow": source_row,
				"sourcePath": draft.get(
					"source", {}
				).get("preparedDirectionFiles", {}).get(direction, ""),
				"sourceSize": [source.get_width(), source.get_height()],
				"scalePercent": scale_percent,
				"displaySize": [display_size.x, display_size.y],
				"capturePixelSize": [target_size.x, target_size.y],
				"rotatedCapturePixelSize": [
					rotated_target_size.x, rotated_target_size.y,
				],
				"savedNudge": direction_record.get("nudge", [0, 0]),
				"headCentre": [centre.x, centre.y],
				"topLeft": [top_left.x, top_left.y],
				"rotationDegrees": rad_to_deg(rotation_radians),
				"rotationRule": (
					"idle_walk_zero"
					if action in ["idle", "walk"]
					else "head_socket_body_axis_delta"
				),
				"deformation": [1.0, 1.0],
			})
	return {
		"sheet": sheet,
		"headDetail": full_figure_detail,
		"fullFigureDetail": full_figure_detail,
		"records": records,
	}


func _pose_rotation_radians(
	action: String,
	direction_index: int,
	frame_index: int
) -> float:
	# Idle is the user's calibrated directional baseline. Walk already passed
	# visual review and therefore remains an exact zero-angle derivative.
	if action in ["idle", "walk"]:
		return 0.0
	var idle_socket := Vector2(HelmetVisualV2.body_head_socket(
		PLAYER_VISUAL_ID, "idle", direction_index, 0
	))
	var pose_socket := Vector2(HelmetVisualV2.body_head_socket(
		PLAYER_VISUAL_ID, action, direction_index, frame_index
	))
	assert(idle_socket != Vector2.ZERO)
	assert(pose_socket != Vector2.ZERO)
	var foot := Vector2(ArtSpec.WARRIOR_FOOT_ANCHOR)
	var idle_axis := idle_socket - foot
	var pose_axis := pose_socket - foot
	assert(idle_axis.length_squared() > 0.0)
	assert(pose_axis.length_squared() > 0.0)
	return wrapf(pose_axis.angle() - idle_axis.angle(), -PI, PI)


func _full_figure_detail_cell(actor: Image) -> Image:
	var cell := Image.create(
		FULL_FIGURE_DETAIL_CELL.x,
		FULL_FIGURE_DETAIL_CELL.y,
		false,
		Image.FORMAT_RGBA8
	)
	cell.fill(BACKGROUND)
	var used := actor.get_used_rect()
	if used.size == Vector2i.ZERO:
		return cell
	var actor_bounds := Rect2i(Vector2i.ZERO, actor.get_size())
	var padded := Rect2i(
		used.position - Vector2i(FULL_FIGURE_PADDING, FULL_FIGURE_PADDING),
		used.size + Vector2i(
			FULL_FIGURE_PADDING * 2,
			FULL_FIGURE_PADDING * 2
		)
	).intersection(actor_bounds)
	var figure := actor.get_region(padded)
	var available := Vector2(
		FULL_FIGURE_DETAIL_CELL
		- Vector2i(FULL_FIGURE_PADDING * 2, FULL_FIGURE_PADDING * 2)
	)
	var zoom := minf(
		FULL_FIGURE_MAX_ZOOM,
		minf(
			available.x / float(figure.get_width()),
			available.y / float(figure.get_height())
		)
	)
	var target_size := Vector2i(
		maxi(1, roundi(figure.get_width() * zoom)),
		maxi(1, roundi(figure.get_height() * zoom))
	)
	var enlarged := _scaled_copy(
		figure, target_size, Image.INTERPOLATE_NEAREST
	)
	var destination := Vector2i(
		(FULL_FIGURE_DETAIL_CELL - target_size) / 2
	)
	cell.blend_rect(
		enlarged,
		Rect2i(Vector2i.ZERO, target_size),
		destination
	)
	return cell


func _rotated_high_resolution_copy(
	source: Image,
	radians: float
) -> Image:
	if is_zero_approx(radians):
		return source.duplicate()
	var cosine := cos(radians)
	var sine := sin(radians)
	var source_size := Vector2(source.get_size())
	var rotated_size := Vector2i(
		maxi(1, ceili(
			absf(source_size.x * cosine)
			+ absf(source_size.y * sine)
		)),
		maxi(1, ceili(
			absf(source_size.x * sine)
			+ absf(source_size.y * cosine)
		))
	)
	var result := Image.create(
		rotated_size.x,
		rotated_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	result.fill(Color(0, 0, 0, 0))
	var source_centre := (source_size - Vector2.ONE) * 0.5
	var result_centre := (Vector2(rotated_size) - Vector2.ONE) * 0.5
	for y: int in rotated_size.y:
		for x: int in rotated_size.x:
			var offset := Vector2(x, y) - result_centre
			var sample := Vector2(
				cosine * offset.x + sine * offset.y,
				-sine * offset.x + cosine * offset.y
			) + source_centre
			if (
				sample.x < 0.0
				or sample.y < 0.0
				or sample.x > source_size.x - 1.0
				or sample.y > source_size.y - 1.0
			):
				continue
			result.set_pixel(x, y, _sample_bilinear_premultiplied(
				source, sample
			))
	return result


func _sample_bilinear_premultiplied(
	source: Image,
	point: Vector2
) -> Color:
	var x0 := clampi(floori(point.x), 0, source.get_width() - 1)
	var y0 := clampi(floori(point.y), 0, source.get_height() - 1)
	var x1 := mini(x0 + 1, source.get_width() - 1)
	var y1 := mini(y0 + 1, source.get_height() - 1)
	var tx := point.x - float(x0)
	var ty := point.y - float(y0)
	var c00 := _premultiplied(source.get_pixel(x0, y0))
	var c10 := _premultiplied(source.get_pixel(x1, y0))
	var c01 := _premultiplied(source.get_pixel(x0, y1))
	var c11 := _premultiplied(source.get_pixel(x1, y1))
	var top := c00.lerp(c10, tx)
	var bottom := c01.lerp(c11, tx)
	var mixed := top.lerp(bottom, ty)
	if mixed.a <= 0.00001:
		return Color(0, 0, 0, 0)
	return Color(
		mixed.r / mixed.a,
		mixed.g / mixed.a,
		mixed.b / mixed.a,
		mixed.a
	)


func _premultiplied(color: Color) -> Color:
	return Color(
		color.r * color.a,
		color.g * color.a,
		color.b * color.a,
		color.a
	)


func _capture_presentation(editor: Node, draft: Dictionary) -> Dictionary:
	var preview: EquipmentCharacterPreview = editor._paper_doll_preview
	var paper: Dictionary = draft.get(
		"presentationCalibration", {}
	).get("paperDoll", {})
	var source_row := int(paper.get("source_row", 4))
	var paper_source: Image = editor._authored_source_cutout(source_row)
	assert(not paper_source.is_empty())
	var paper_size: Vector2 = editor._paper_doll_display_size(
		paper_source, int(paper.get("scale_percent", 100))
	)
	var paper_position := Vector2(
		float(paper.get("offset", [0, 0])[0]),
		float(paper.get("offset", [0, 0])[1])
	)
	var paper_canvas := Image.create(
		PAPER_CANVAS.x, PAPER_CANVAS.y, false, Image.FORMAT_RGBA8
	)
	paper_canvas.fill(BACKGROUND)
	_blend_preview_texture(
		paper_canvas,
		preview._base_texture,
		preview.composition_draw_origin(),
		preview._canvas_size * preview.preview_scale
	)
	if preview._helmet_texture == null:
		_blend_preview_layer(
			paper_canvas, preview, preview._hair_layer
		)
	for layer: Dictionary in preview._paper_layers:
		if str(layer.get("equipmentSlot", "")) == "头盔":
			continue
		_blend_preview_layer(paper_canvas, preview, layer)
	_blend_image(
		paper_canvas,
		paper_source,
		paper_position,
		paper_size,
		Image.INTERPOLATE_LANCZOS
	)

	var inventory_source: Image = editor._authored_presentation_cutout(
		"inventory"
	)
	var ground_source: Image = editor._authored_presentation_cutout("ground")
	assert(not inventory_source.is_empty())
	assert(not ground_source.is_empty())
	var overview := Image.create(1152, 420, false, Image.FORMAT_RGBA8)
	overview.fill(BACKGROUND)
	overview.blend_rect(
		paper_canvas,
		Rect2i(Vector2i.ZERO, paper_canvas.get_size()),
		Vector2i(20, 40)
	)
	_blend_fit_panel(
		overview, inventory_source, Rect2i(590, 40, 250, 340)
	)
	_blend_fit_panel(
		overview, ground_source, Rect2i(872, 40, 250, 340)
	)
	return {
		"paperDoll": paper_canvas,
		"overview": overview,
		"records": {
			"paperDoll": {
				"sourceRow": source_row,
				"sourceDirection": paper.get("source_direction", "S"),
				"sourceSize": [
					paper_source.get_width(), paper_source.get_height(),
				],
				"scalePercent": int(paper.get("scale_percent", 100)),
				"displaySize": [paper_size.x, paper_size.y],
				"offset": [paper_position.x, paper_position.y],
			},
			"inventory": {
				"sourceVariant": "dedicated_inventory",
				"sourceSize": [
					inventory_source.get_width(),
					inventory_source.get_height(),
				],
			},
			"ground": {
				"sourceVariant": "dedicated_ground",
				"sourceSize": [
					ground_source.get_width(), ground_source.get_height(),
				],
			},
		},
	}


func _blend_preview_layer(
	target: Image,
	preview: EquipmentCharacterPreview,
	layer: Dictionary
) -> void:
	if layer.is_empty():
		return
	var texture: Texture2D = layer.get("texture")
	if texture == null:
		return
	_blend_preview_texture(
		target,
		texture,
		preview.layer_draw_origin(layer),
		texture.get_size() * preview.preview_scale
	)


func _blend_preview_texture(
	target: Image,
	texture: Texture2D,
	position: Vector2,
	size: Vector2
) -> void:
	if texture == null:
		return
	var source := texture.get_image()
	if source == null or source.is_empty():
		return
	_blend_image(
		target, source, position, size, Image.INTERPOLATE_NEAREST
	)


func _blend_image(
	target: Image,
	source: Image,
	position: Vector2,
	size: Vector2,
	interpolation: Image.Interpolation
) -> void:
	var pixel_size := Vector2i(
		maxi(1, roundi(size.x)),
		maxi(1, roundi(size.y))
	)
	var scaled := _scaled_copy(source, pixel_size, interpolation)
	target.blend_rect(
		scaled,
		Rect2i(Vector2i.ZERO, scaled.get_size()),
		Vector2i(position.round())
	)


func _blend_fit_panel(
	target: Image,
	source: Image,
	panel: Rect2i
) -> void:
	var border := Color("36506b")
	for x: int in range(panel.position.x, panel.end.x):
		target.set_pixel(x, panel.position.y, border)
		target.set_pixel(x, panel.end.y - 1, border)
	for y: int in range(panel.position.y, panel.end.y):
		target.set_pixel(panel.position.x, y, border)
		target.set_pixel(panel.end.x - 1, y, border)
	var inner := Vector2i(panel.size.x - 32, panel.size.y - 32)
	var factor := minf(
		float(inner.x) / float(source.get_width()),
		float(inner.y) / float(source.get_height())
	)
	var size := Vector2(
		source.get_width() * factor,
		source.get_height() * factor
	)
	var position := Vector2(panel.position) + (
		Vector2(panel.size) - size
	) * 0.5
	_blend_image(
		target, source, position, size, Image.INTERPOLATE_LANCZOS
	)


func _scaled_copy(
	source: Image,
	target_size: Vector2i,
	interpolation: Image.Interpolation
) -> Image:
	var copy := source.duplicate()
	copy.resize(target_size.x, target_size.y, interpolation)
	return copy


func _protected_hashes() -> Dictionary:
	var result := {}
	for path: String in PROTECTED_PATHS:
		result[path] = FileAccess.get_sha256(path)
	return result
