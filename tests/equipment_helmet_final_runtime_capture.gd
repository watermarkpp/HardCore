extends Node

const FINALIZATION_PATH := "res://assets/data/equipment_helmet_finalization_manifest.json"
const HELMET_CONTRACT_PATH := "res://assets/data/equipment_male_world_helmet.json"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/helmet_final_runtime"
const ITEM_IDS := [146, 147, 148, 149, 150, 151, 218, 224, 228, 232, 236, 240]
const ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIRECTION_VECTORS := [
	Vector2.UP,
	Vector2(0.70710678, -0.70710678),
	Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678),
	Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
]
const CELL_SIZE := Vector2i(192, 160)
const RUNTIME_FOOT_ANCHOR := Vector2i(96, 108)


func _ready() -> void:
	_run.call_deferred()


func _json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "%s must contain a Dictionary" % path)
	return parsed


func _run() -> void:
	var finalization := _json(FINALIZATION_PATH)
	assert(finalization.get("contractId", "") == "equipment.helmet.finalization.v1")
	var helmet_contract := _json(HELMET_CONTRACT_PATH)
	var contract_items: Dictionary = helmet_contract.get("itemsById", {})
	PlayerState.test_mode = true
	PlayerState.ensure_developer_test_character()
	assert(PlayerState.select_character("developer_warrior_30"))
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.equipment = {
		"衣服": {"name": "布衣(男)", "instance_id": "final_helmet_default_dress"},
	}

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player
	var visual: Node2D = player.get_node("PlayerVisual")
	assert(visual != null)
	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var capture_manifest := {
		"schemaVersion": 1,
		"contractId": "equipment.helmet.final.runtime.capture.v1",
		"sourceFinalizationContract": finalization.get("contractId", ""),
		"actions": ACTIONS,
		"directions": DIRECTIONS,
		"cellSize": [CELL_SIZE.x, CELL_SIZE.y],
		"items": [],
	}

	for item_id: int in ITEM_IDS:
		var item_contract: Dictionary = contract_items.get(str(item_id), {})
		assert(not item_contract.is_empty(), "missing helmet item %d" % item_id)
		var final_item := _final_item(finalization, item_id)
		assert(not final_item.is_empty(), "missing finalization item %d" % item_id)
		PlayerState.equipment["头盔"] = {
			"item_id": item_id,
			"name": str(item_contract.get("itemName", "")),
			"instance_id": "final_helmet_%d" % item_id,
		}
		visual._refresh_equipment_visuals()
		assert(visual.worn_helmet_sprite.visible)
		assert(visual.worn_helmet_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
		assert(visual.worn_helmet_sprite.scale == Vector2.ONE)

		var sheet := Image.create(
			CELL_SIZE.x * ACTIONS.size(),
			CELL_SIZE.y * DIRECTIONS.size(),
			false,
			Image.FORMAT_RGBA8
		)
		sheet.fill(Color("111418"))
		var action_records: Array[Dictionary] = []
		for action_index: int in ACTIONS.size():
			var action: String = ACTIONS[action_index]
			var action_metrics: Dictionary = final_item.get(
				"actionMetrics", {}
			).get(action, {})
			var frame_count := int(action_metrics.get("frameCount", 0))
			assert(frame_count > 0)
			assert(int(visual._helmet_action_frame_counts.get(action, 0)) == frame_count)
			var expected_path := str(
				final_item.get("runtimeAtlases", {}).get(action, "")
			)
			assert(not expected_path.is_empty())
			var capture_frame := frame_count - 1 if action == "death" else frame_count / 2
			var direction_records: Array[Dictionary] = []
			for direction_index: int in DIRECTIONS.size():
				for frame_index: int in frame_count:
					_set_pose(
						visual,
						player,
						action,
						direction_index,
						frame_index,
						frame_count
					)
					assert(visual.current_direction == direction_index)
					assert(visual.current_frame == frame_index)
					assert(visual.worn_helmet_sprite.visible)
					assert(
						visual._v2_layer_texture_cache.get(expected_path, null)
							== visual.worn_helmet_sprite.texture,
						"%d %s did not resolve final atlas %s" % [
							item_id,
							action,
							expected_path,
						]
					)
					assert(
						int(visual.worn_helmet_sprite.region_rect.position.x)
							== frame_index * CELL_SIZE.x
					)
					var source_row := int(
						final_item.get("directionCalibration", {})
							.get(DIRECTIONS[direction_index], {})
							.get("source_row", -1)
					)
					assert(
						int(visual.worn_helmet_sprite.region_rect.position.y)
							== source_row * CELL_SIZE.y
					)
					var helmet_cell: Image = (
						visual.worn_helmet_sprite.texture.get_image()
						.get_region(Rect2i(visual.worn_helmet_sprite.region_rect))
					)
					assert(helmet_cell.get_used_rect().has_area())
				_set_pose(
					visual,
					player,
					action,
					direction_index,
					capture_frame,
					frame_count
				)
				var runtime_cell := _compose_runtime_cell(visual)
				sheet.blend_rect(
					runtime_cell,
					Rect2i(Vector2i.ZERO, CELL_SIZE),
					Vector2i(
						action_index * CELL_SIZE.x,
						direction_index * CELL_SIZE.y
					)
				)
				direction_records.append({
					"direction": DIRECTIONS[direction_index],
					"captureFrame": capture_frame,
					"helmetPosition": [
						visual.worn_helmet_sprite.position.x,
						visual.worn_helmet_sprite.position.y,
					],
				})
			action_records.append({
				"action": action,
				"frameCount": frame_count,
				"runtimeAtlas": expected_path,
				"directions": direction_records,
			})
		var sheet_name := "item_%03d_all_actions.png" % item_id
		assert(sheet.save_png(output_dir.path_join(sheet_name)) == OK)
		capture_manifest["items"].append({
			"itemId": item_id,
			"itemName": item_contract.get("itemName", ""),
			"visualAssetId": final_item.get("visualAssetId", ""),
			"sheet": "%s/%s" % [OUTPUT_ROOT, sheet_name],
			"actions": action_records,
		})

	var manifest_path := output_dir.path_join("capture_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(capture_manifest, "\t", false))
	file.close()
	print(
		"EQUIPMENT_HELMET_FINAL_RUNTIME_CAPTURE_PASS "
		+ "item_ids=12 actions=6 directions=8 all_frames=true "
		+ "runtime_scale=1 runtime_filter=nearest"
	)
	get_tree().quit(0)


func _final_item(finalization: Dictionary, item_id: int) -> Dictionary:
	for value: Variant in finalization.get("items", {}).values():
		if not value is Dictionary:
			continue
		for shared_item_id: Variant in value.get("sharedItemIds", []):
			if int(shared_item_id) == item_id:
				return value
	return {}


func _set_pose(
	visual: Node2D,
	player: PlayerCharacter,
	action: String,
	direction_index: int,
	frame_index: int,
	frame_count: int
) -> void:
	var facing: Vector2 = DIRECTION_VECTORS[direction_index]
	player.facing = facing
	player.actual_motion_facing = facing
	player.velocity = facing * 100.0 if action == "walk" else Vector2.ZERO
	visual._action_remaining = 0.0
	if action == "idle":
		visual._last_state = "idle"
		visual._elapsed = float(frame_index) / 6.0 + 0.001
	elif action == "walk":
		visual._last_state = "walk"
		visual._elapsed = float(frame_index) / 10.0 + 0.001
	else:
		visual._action_name = action
		visual._action_duration = 1.0
		visual._action_remaining = 1.0
		visual._last_state = "action"
		visual._elapsed = (float(frame_index) + 0.1) / float(frame_count)
	visual._process(0.0)


func _compose_runtime_cell(visual: Node2D) -> Image:
	var composed := Image.create(
		CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8
	)
	composed.fill(Color("111418"))
	for layer: Sprite2D in [
		visual.worn_helmet_back_sprite,
		visual.sprite,
		visual.worn_helmet_sprite,
	]:
		if layer == null or not layer.visible or layer.texture == null:
			continue
		assert(layer.region_enabled and not layer.centered)
		var cell := layer.texture.get_image().get_region(
			Rect2i(layer.region_rect)
		)
		var destination := RUNTIME_FOOT_ANCHOR + Vector2i(layer.position.round())
		composed.blend_rect(
			cell, Rect2i(Vector2i.ZERO, cell.get_size()), destination
		)
	return composed
