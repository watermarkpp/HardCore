extends Node

const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")
const CONTRACT_PATH := "res://assets/data/equipment_male_world_helmet.json"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/equipment_helmet_directions"
const ITEM_IDS := ["146", "147", "148", "149", "150", "151", "218", "224", "228", "232", "236", "240"]
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
const CAPTURE_SIZE := Vector2i(256, 256)
const RUNTIME_FOOT_POINT := Vector2i(128, 190)
const CAPTURE_LAYER_NODES := ["BodySprite", "ClientHelmetLayer"]


func _ready() -> void:
	_capture.call_deferred()


func _json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "%s must contain a Dictionary" % path)
	return parsed


func _capture() -> void:
	PlayerState.test_mode = true
	PlayerState.ensure_developer_test_character()
	assert(PlayerState.select_character("developer_warrior_30"))
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	# The review fixture intentionally contains only the formal male player,
	# the default male cloth dress, and one helmet. It never routes through the
	# StateItem/paper-doll presentation code.
	PlayerState.equipment = {
		"衣服": {"name": "布衣(男)", "instance_id": "helmet_capture_default_dress"},
	}

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player
	var visual: Node2D = player.get_node("PlayerVisual")
	assert(visual != null and visual.get_script() == load("res://scripts/player_visual.gd"))
	var contract := _json(CONTRACT_PATH)
	assert(contract.get("actorContract", {}).get("directions", []) == DIRECTIONS)
	var items: Dictionary = contract.get("itemsById", {})
	var identities: Dictionary = contract.get("visualIdentities", {})

	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var manifest_items: Array[Dictionary] = []
	for item_id: String in ITEM_IDS:
		var item: Dictionary = items.get(item_id, {})
		assert(not item.is_empty(), "helmet contract missing itemId %s" % item_id)
		var item_name := str(item.get("itemName", ""))
		var identity_id := str(item.get("identityId", ""))
		var identity: Dictionary = identities.get(identity_id, {})
		assert(not identity.is_empty(), "helmet identity missing: %s" % identity_id)
		var source_order: Array = identity.get("sourceSlotDirectionOrder", [])
		var canonical_source_slots: Array = identity.get("canonicalRowSourceSlots", [])
		assert(source_order.size() == 8 and canonical_source_slots.size() == 8)
		PlayerState.equipment["头盔"] = {
			"item_id": int(item_id),
			"name": item_name,
			"instance_id": "helmet_capture_%s" % item_id,
		}
		visual._refresh_equipment_visuals()
		assert(not visual.worn_weapon_sprite.visible, "%s unexpectedly rendered a weapon" % item_name)
		assert(visual.worn_helmet_sprite.visible, "%s runtime helmet layer is hidden" % item_name)

		var captures: Array[Dictionary] = []
		for direction_index: int in DIRECTIONS.size():
			player.velocity = Vector2.ZERO
			player.facing = DIRECTION_VECTORS[direction_index]
			visual._action_remaining = 0.0
			visual._elapsed = 0.0
			visual._last_state = ""
			visual._process(0.01)
			assert(visual.current_state == "idle")
			assert(visual.current_direction == direction_index)
			assert(visual.current_frame == 0)
			var source_slot := int(canonical_source_slots[direction_index])
			assert(
				str(source_order[source_slot]) == DIRECTIONS[direction_index],
				"%s failed source-slot reorder for %s" % [identity_id, DIRECTIONS[direction_index]]
			)
			assert(
				visual.sprite.region_rect.position
				== Vector2(0, direction_index * ArtSpec.WARRIOR_FRAME.y)
			)
			var expected_helmet_row := HelmetVisualV2.source_direction_row(int(item_id), direction_index)
			assert(
				int(visual.worn_helmet_sprite.region_rect.position.y)
				== expected_helmet_row * ArtSpec.WARRIOR_FRAME.y
			)
			var image := _compose_player_visual(visual)
			var file_name := "%s_%s.png" % [item_id, DIRECTIONS[direction_index]]
			var output_path := output_dir.path_join(file_name)
			assert(image.save_png(output_path) == OK, "failed to save %s" % output_path)
			captures.append({
				"direction": DIRECTIONS[direction_index],
				"runtimeDirectionRow": direction_index,
				"sourceSlot": source_slot,
				"path": "%s/%s" % [OUTPUT_ROOT, file_name],
				"bodyTexture": visual.sprite.texture.resource_path,
				"helmetTexture": visual.worn_helmet_sprite.texture.resource_path,
				"bodyRegion": _rect_array(visual.sprite.region_rect),
				"helmetRegion": _rect_array(visual.worn_helmet_sprite.region_rect),
			})
		manifest_items.append({
			"itemId": int(item_id),
			"itemName": item_name,
			"identityId": identity_id,
			"sourceSlotDirectionOrder": source_order,
			"canonicalRowSourceSlots": canonical_source_slots,
			"captures": captures,
		})

	var manifest := {
		"schemaVersion": 1,
		"contractId": "equipment.world_helmet.male.idle_direction_capture.v1",
		"sourceContractId": str(contract.get("contractId", "")),
		"runtimeComposite": "PlayerVisual/BodySprite + PlayerVisual/ClientHelmetLayer",
		"paperDollOrStateItemPixelsUsed": false,
		"profession": "战士",
		"gender": "男",
		"defaultDress": "布衣(男)",
		"action": "idle",
		"directions": DIRECTIONS,
		"captureSize": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"runtimeFootPoint": [RUNTIME_FOOT_POINT.x, RUNTIME_FOOT_POINT.y],
		"transparentBackground": true,
		"items": manifest_items,
	}
	var manifest_path := output_dir.path_join("capture_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(file != null, "cannot write capture manifest")
	file.store_string(JSON.stringify(manifest, "\t", false))
	file.close()
	print(
		"EQUIPMENT_HELMET_DIRECTION_CAPTURE_PASS "
		+ "items=12 directions=8 frames=96 runtime=PlayerVisual"
	)
	get_tree().quit(0)


func _compose_player_visual(visual: Node2D) -> Image:
	var composed := Image.create(CAPTURE_SIZE.x, CAPTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	composed.fill(Color(0, 0, 0, 0))
	for layer_name: String in CAPTURE_LAYER_NODES:
		var layer := visual.get_node(layer_name) as Sprite2D
		assert(layer != null and layer.visible and layer.texture != null)
		assert(layer.region_enabled and not layer.centered)
		var source := layer.texture.get_image()
		assert(source != null and not source.is_empty())
		var region := Rect2i(layer.region_rect)
		assert(region.size == ArtSpec.WARRIOR_FRAME)
		var cell := source.get_region(region)
		var destination := (
			RUNTIME_FOOT_POINT
			+ Vector2i(visual.position.round())
			+ Vector2i(layer.position.round())
		)
		composed.blend_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), destination)
	return composed


func _rect_array(rect: Rect2) -> Array[int]:
	return [int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)]
