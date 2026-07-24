extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")

const STAGE_SIZE := Vector2(232.0, 325.0)
const VIEWPORT_ORIGIN := Vector2(0.0, -44.0)
const BASE_HOT := Vector2(7.0, -44.0)
const HAIR_HOT := Vector2(87.0, 0.0)
const DRESS_HOT := Vector2(47.0, 14.0)
const WEAPON_HOT := Vector2(25.0, -39.0)
const HELMET_HOT := Vector2(79.0, -8.0)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var source_document := _fixture_document()
	var preview := PreviewScript.new()
	preview.size = Vector2(230.0, 286.0)
	preview.configure_source_document(source_document)
	add_child(preview)
	await get_tree().process_frame

	assert(preview.uses_original_client_stage())
	assert(
		PreviewScript.ORIGINAL_CLIENT_STAGE_CONTRACT_ID
		== "equipment.paper_doll.original_client_stage.v1"
	)
	assert(PreviewScript.ORIGINAL_CLIENT_BASE_SCREEN_ORIGIN == Vector2.ZERO)
	_assert_draw_order_and_offsets(preview)
	_assert_aspect_fit_and_inverse_mapping(preview)
	_assert_immediate_equipment_refresh(preview)
	await _assert_female_stage_is_not_consumed(source_document)

	print("EQUIPMENT_ORIGINAL_CLIENT_STAGE_PASS")
	get_tree().quit(0)


func _assert_female_stage_is_not_consumed(source_document: Dictionary) -> void:
	var female_document := source_document.duplicate(true)
	female_document["sex"] = "female"
	var female_preview := PreviewScript.new()
	female_preview.configure_source_document(female_document)
	add_child(female_preview)
	await get_tree().process_frame
	assert(female_preview.uses_original_client_stage())
	assert(not female_preview.has_renderable_assets())
	female_preview.queue_free()


func _assert_draw_order_and_offsets(preview: EquipmentCharacterPreview) -> void:
	var commands := preview.original_stage_draw_commands()
	var kinds: Array[String] = []
	for command: Dictionary in commands:
		kinds.append(str(command.get("kind", "")))
	assert(kinds == PreviewScript.ORIGINAL_CLIENT_DRAW_ORDER)
	assert(commands[0].stagePosition == BASE_HOT)
	assert(
		is_equal_approx(
			commands[0].targetRect.position.y,
			preview.original_stage_rect().position.y
		),
		"Prguse376 top edge was clipped instead of honoring viewportOrigin"
	)
	assert(
		commands[1].stagePosition
		== PreviewScript.ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR + HAIR_HOT
	)
	assert(
		commands[2].stagePosition
		== PreviewScript.ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR + DRESS_HOT
	)
	assert(
		commands[3].stagePosition
		== PreviewScript.ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR + WEAPON_HOT
	)
	assert(
		commands[4].stagePosition
		== PreviewScript.ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR + HELMET_HOT
	)
	var helmet_texture: Texture2D = commands[4].texture
	var helmet_rect: Rect2 = commands[4].targetRect
	assert(
		helmet_rect.size.is_equal_approx(helmet_texture.get_size() * preview.original_stage_scale()),
		"StateItem helmet record was cropped instead of drawing its complete rectangle"
	)


func _assert_aspect_fit_and_inverse_mapping(preview: EquipmentCharacterPreview) -> void:
	var expected_scale := minf(preview.size.x / STAGE_SIZE.x, preview.size.y / STAGE_SIZE.y)
	assert(is_equal_approx(preview.original_stage_scale(), expected_scale))
	var fitted := preview.original_stage_rect()
	assert(fitted.size.is_equal_approx(STAGE_SIZE * expected_scale))
	assert(fitted.position.is_equal_approx((preview.size - fitted.size) * 0.5))
	assert(
		preview.original_stage_to_local(VIEWPORT_ORIGIN).is_equal_approx(
			fitted.position
		)
	)
	var stage_point := Vector2(31.0, 96.0)
	var local_point := preview.original_stage_to_local(stage_point)
	assert(preview.local_to_original_stage(local_point).is_equal_approx(stage_point))
	var stage_hit_rect := Rect2(Vector2(12.0, 24.0), Vector2(40.0, 56.0))
	var local_hit_rect := preview.original_hit_rect_to_local(stage_hit_rect)
	assert(
		preview.local_to_original_stage(local_hit_rect.position).is_equal_approx(
			stage_hit_rect.position
		)
	)
	assert(
		(local_hit_rect.size / preview.original_stage_scale()).is_equal_approx(
			stage_hit_rect.size
		)
	)
	assert(preview.original_stage_contains_local_point(fitted.get_center()))
	assert(not preview.original_stage_contains_local_point(fitted.position - Vector2.ONE))


func _assert_immediate_equipment_refresh(preview: EquipmentCharacterPreview) -> void:
	var weapon_slot := str(PreviewScript.PAPER_LAYER_SLOTS[1])
	var revision_before := preview.render_revision()
	PlayerState.equipment[weapon_slot] = {"item_id": "weapon.second", "name": "fixture weapon 2"}
	PlayerState.equipment_changed.emit()
	assert(preview.render_revision() == revision_before + 1)
	assert(preview.paper_layer_source_index(weapon_slot) == 56)
	var commands := preview.original_stage_draw_commands()
	assert(int(commands[3].sourceIndex) == 56)
	assert(commands[3].stagePosition == Vector2(31.0 + 33.0, 96.0 - 37.0))


func _fixture_document() -> Dictionary:
	var dress_slot := str(PreviewScript.PAPER_LAYER_SLOTS[0])
	var weapon_slot := str(PreviewScript.PAPER_LAYER_SLOTS[1])
	var helmet_slot := str(PreviewScript.PAPER_LAYER_SLOTS[2])
	PlayerState.equipment[dress_slot] = {"item_id": "dress.first", "name": "fixture dress"}
	PlayerState.equipment[weapon_slot] = {"item_id": "weapon.first", "name": "fixture weapon"}
	PlayerState.equipment[helmet_slot] = {"item_id": "helmet.first", "name": "fixture helmet"}
	return {
		"contractId": PreviewScript.ORIGINAL_CLIENT_STAGE_CONTRACT_ID,
		"sex": "male",
		"canvasSize": [STAGE_SIZE.x, STAGE_SIZE.y],
		"viewportOrigin": [VIEWPORT_ORIGIN.x, VIEWPORT_ORIGIN.y],
		"stage": {
			"source": "Prguse.wil",
			"sourceIndex": 376,
			"texture": _solid_texture(Vector2i(168, 199), Color("24170f")),
			"size": [168, 199],
			"hotX": BASE_HOT.x,
			"hotY": BASE_HOT.y,
		},
		"hair": {
			"source": "Prguse.wil",
			"sourceIndex": 442,
			"texture": _solid_texture(Vector2i(16, 14), Color("422918")),
			"hotX": HAIR_HOT.x,
			"hotY": HAIR_HOT.y,
		},
		"composition": {
			"canvasSize": [STAGE_SIZE.x, STAGE_SIZE.y],
			"viewportOrigin": [VIEWPORT_ORIGIN.x, VIEWPORT_ORIGIN.y],
			"equipmentScreenAnchor": [31, 96],
			"drawOrder": PreviewScript.ORIGINAL_CLIENT_DRAW_ORDER,
		},
		"itemMappings": {
			"dress.first": {
				"slot": dress_slot,
				"sourceIndex": 62,
				"texture": _solid_texture(Vector2i(84, 140), Color("3c6a35")),
				"hotX": DRESS_HOT.x,
				"hotY": DRESS_HOT.y,
			},
			"weapon.first": {
				"slot": weapon_slot,
				"sourceIndex": 55,
				"texture": _solid_texture(Vector2i(44, 145), Color("a9abb0")),
				"hotX": WEAPON_HOT.x,
				"hotY": WEAPON_HOT.y,
			},
			"weapon.second": {
				"slot": weapon_slot,
				"sourceIndex": 56,
				"texture": _solid_texture(Vector2i(32, 117), Color("d5c073")),
				"hotX": 33,
				"hotY": -37,
			},
			"helmet.first": {
				"slot": helmet_slot,
				"sourceIndex": 344,
				# Deliberately opaque: original StateItem restore pixels must
				# survive intact rather than being keyed/cropped as background.
				"texture": _solid_texture(Vector2i(28, 32), Color("17120e")),
				"hotX": HELMET_HOT.x,
				"hotY": HELMET_HOT.y,
			},
		},
	}


func _solid_texture(texture_size: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
