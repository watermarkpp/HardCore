extends Node

const POLICY_PATH := "res://assets/data/equipment_world_helmet_runtime_policy.json"
const HELMET_CONTRACT_PATH := "res://assets/data/equipment_male_world_helmet.json"
const ITEM_IDS := [146, 147, 148, 149, 150, 151, 218, 224, 228, 232, 236, 240]
const ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
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


func _ready() -> void:
	_run.call_deferred()


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	assert(parsed is Dictionary, "%s is not valid JSON" % path)
	return parsed


func _run() -> void:
	var policy := _json(POLICY_PATH)
	assert(
		str(policy.get("contractId", ""))
		== EquipmentRules.WORLD_HELMET_RUNTIME_POLICY_CONTRACT_ID
	)
	assert(not EquipmentRules.world_helmet_is_visible())
	assert(not EquipmentRules.world_helmet_head_mask_enabled())
	assert(
		policy.get("preservedPresentationScopes", [])
		== ["paper_doll", "inventory", "ground"]
	)
	var hair_appearance := EquipmentRules.world_hair_appearance()
	assert(str(hair_appearance.get("sex", "")) == "male")
	assert(int(hair_appearance.get("genderOffset", -1)) == 0)
	assert(int(hair_appearance.get("appearance", -1)) == 1)
	assert(int(hair_appearance.get("appearanceStride", -1)) == 600)
	assert(int(hair_appearance.get("sourceBlock", -1)) == 2)
	assert(
		str(hair_appearance.get("source", {}).get("tier", ""))
		== "primary"
	)
	assert(
		str(hair_appearance.get("source", {}).get("lane", ""))
		== "client_assets"
	)
	assert(
		str(hair_appearance.get("source", {}).get(
			"distribution", ""
		)) == "client.classic_raw_complete"
	)
	assert(
		not bool(
			hair_appearance.get("source", {}).get("resampled", true)
		)
	)
	assert(
		not bool(
			hair_appearance.get("source", {}).get(
				"syntheticFrames", true
			)
		)
	)

	var helmet_contract := _json(HELMET_CONTRACT_PATH)
	var items: Dictionary = helmet_contract.get("itemsById", {})
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.equipment = {
		"衣服": {
			"item_id": 116,
			"name": "布衣(男)",
			"instance_id": "world_hair_default_dress",
		},
	}
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	var visual: Node2D = player.visual
	assert(visual != null)

	for item_id: int in ITEM_IDS:
		var item: Dictionary = items.get(str(item_id), {})
		assert(not item.is_empty(), "missing helmet item %d" % item_id)
		PlayerState.equipment["头盔"] = {
			"item_id": item_id,
			"name": str(item.get("itemName", "")),
			"instance_id": "world_hidden_helmet_%d" % item_id,
		}
		visual._refresh_equipment_visuals()
		assert(
			visual._helmet_action_textures.size() == ACTIONS.size(),
			"helmet assets stopped resolving for item %d" % item_id
		)
		for action: String in ACTIONS:
			var frame_count := int(
				visual._body_action_frame_counts.get(action, 0)
			)
			assert(frame_count > 0)
			var expected_body: Texture2D = (
				visual._dress_action_textures.get(action, null)
			)
			var expected_hair: Texture2D = (
				visual._hair_action_textures.get(action, null)
			)
			assert(expected_body != null and expected_hair != null)
			assert(
				str(hair_appearance.get("actions", {}).get(
					action, {}
				).get("path", "")).ends_with("hair_001_%s.png" % action)
			)
			for direction_index: int in DIRECTION_VECTORS.size():
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
					assert(
						visual.sprite.texture == expected_body,
						"body was alpha-masked for %d/%s/%d/%d"
						% [
							item_id,
							action,
							direction_index,
							frame_index,
						]
					)
					assert(visual.worn_hair_sprite.visible)
					assert(visual.worn_hair_sprite.texture == expected_hair)
					assert(
						visual.worn_hair_sprite.region_rect
						== visual.sprite.region_rect
					)
					assert(not visual.worn_helmet_sprite.visible)
					assert(not visual.worn_helmet_back_sprite.visible)
					assert(not visual.head_occlusion_mask_sprite.visible)

	print(
		"EQUIPMENT_WORLD_HELMET_HIDDEN_HAIR_PASS "
		+ "items=12 actions=6 directions=8 all_frames=true "
		+ "paper_inventory_ground=preserved"
	)
	get_tree().quit(0)


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
	player.velocity = (
		facing * 100.0 if action == "walk" else Vector2.ZERO
	)
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
		visual._elapsed = (
			(float(frame_index) + 0.1) / float(frame_count)
		)
	visual._process(0.0)
