extends SceneTree

const MAP_ID := "bich_province"
const WORKSPACE := "res://map_editor_workspace/bich_province_map1_final2"


func _init() -> void:
	var document := MapEditorTypes.new_map_from_catalog(MAP_ID, "bich_city_outdoor", 4, "比奇省·单机重构版")
	document.editor_meta.workspace = WORKSPACE
	document.editor_meta.revision = 1
	document.editor_meta["milestone"] = "BICH-MAP-1"
	document.editor_meta["layout_policy"] = "compact_single_player_256x256"
	document.ground.blank_fill_asset_id = "ground.dark_grass.001"
	document.design["city_rect"] = [96, 96, 64, 64]
	document.design["safe_area_rect"] = [112, 112, 32, 32]
	document.design["functional_zones"] = [
		{"zone_id":"central_plaza", "name":"中央安全广场", "rect":[112,112,32,32], "purpose":"return_spawn_social"},
		{"zone_id":"west_supply", "name":"仓库与补给区", "rect":[98,116,14,28], "purpose":"storage_general_shop"},
		{"zone_id":"east_trade", "name":"武器与药品区", "rect":[144,116,14,28], "purpose":"weapon_armor_medicine"},
		{"zone_id":"north_admin", "name":"老兵与任务区", "rect":[116,98,28,14], "purpose":"guide_quest_travel"},
		{"zone_id":"south_craft", "name":"铁匠与训练区", "rect":[116,144,28,14], "purpose":"repair_craft_training"},
	]
	for zone: Dictionary in document.design.functional_zones:
		document.layers.editor_guides.append({"guide_id":zone.zone_id, "kind":"functional_zone", "name":zone.name, "rect":zone.rect, "purpose":zone.purpose, "editor_only":true})

	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok, str(initialized.get("errors", [])))
	var paints: Array[Dictionary] = []
	# City ground: stone/mud districts with a brighter central plaza.
	for y in range(96, 160):
		for x in range(96, 160):
			var asset := "v1_5.a013_%02d" % (1 + posmod(x * 3 + y * 5, 8))
			if x >= 112 and x < 144 and y >= 112 and y < 144:
				asset = "v1_5.a008_%02d" % (1 + posmod(x + y, 8))
			elif (x < 112 or x >= 144) and y >= 116 and y < 144:
				asset = "v1_5.a004_%02d" % (1 + posmod(x + y * 2, 6))
			paints.append({"op":"paint_tile", "tile":[x,y], "asset_id":asset})
	# Four main roads plus a southwest mine spur. Width is four logical tiles.
	_add_road(paints, Rect2i(126, 0, 4, 112))
	_add_road(paints, Rect2i(126, 144, 4, 112))
	_add_road(paints, Rect2i(0, 126, 112, 4))
	_add_road(paints, Rect2i(144, 126, 112, 4))
	for step in range(0, 82):
		var cx := 112 - step
		var cy := 144 + step
		for width in range(-2, 2):
			if cx + width >= 0 and cy < 256:
				paints.append({"op":"paint_tile", "tile":[cx + width,cy], "asset_id":"v1_5.a006_%02d" % (1 + posmod(step + width, 8))})
	var painted := MapEditorGroundService.record_tile_paint_batch(document, paints)
	assert(painted.ok, str(painted.get("errors", [])))

	# Initial architectural anchors. They remain fully editable in the shared editor.
	_place(document, "direct.prop.02_tents.02_tents_01_r01_c01", Vector2i(100, 116), "building")
	_place(document, "direct.prop.03_storage_props.03_storage_props_01_r01_c01", Vector2i(101, 132), "interactable")
	_place(document, "direct.prop.02_tents.02_tents_03_r01_c03", Vector2i(147, 116), "building")
	_place(document, "direct.prop.04_blacksmith_props.04_blacksmith_props_01_r01_c01", Vector2i(119, 148), "interactable")
	_place(document, "direct.prop.02_tents.02_tents_05_r02_c02", Vector2i(119, 100), "building")
	for tile: Vector2i in [Vector2i(126,94),Vector2i(126,160),Vector2i(94,126),Vector2i(160,126)]:
		_place(document, "v1_5.b012_01", tile, "terrain")

	assert(MapEditorGameplaySemanticService.add_entry(document, "safe_area", Vector2i(128,128), {"area_id":"safe.bich_city", "radius_gu":16, "return_anchor":true}).ok)
	_add_door(document, Vector2i(128,1), "exit.wooma_forest", "268", "沃玛森林")
	_add_door(document, Vector2i(254,128), "exit.orc_tomb", "217", "兽人古墓")
	_add_door(document, Vector2i(128,254), "exit.snake_valley", "338", "毒蛇山谷")
	_add_door(document, Vector2i(1,128), "exit.natural_cave", "248", "天然洞穴")
	_add_door(document, Vector2i(31,225), "exit.bich_mine", "401", "比奇废矿")

	var save := MapEditorSaveService.save_document(document)
	assert(save.ok, str(save.get("errors", [])))
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	assert(bake.ok, str(bake.get("errors", [])))
	print("BICH_MAP_1_PASS paints=%d instances=%d exits=5 baked=%d path=%s" % [paints.size(), MapEditorInstanceService.all_instances(document).size(), bake.baked_chunks.size(), save.path])
	quit()


func _add_road(paints: Array[Dictionary], rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			paints.append({"op":"paint_tile", "tile":[x,y], "asset_id":"v1_5.a006_%02d" % (1 + posmod(x + y, 8))})


func _place(document: Dictionary, asset_id: String, tile: Vector2i, role: String) -> void:
	var placed := MapEditorInstanceService.create_instance(document, asset_id, role, tile, "terrain_base" if role == "terrain" else "object_base")
	assert(placed.ok, "%s %s" % [asset_id, placed.get("errors", [])])


func _add_door(document: Dictionary, tile: Vector2i, door_id: String, target: String, label: String) -> void:
	var result := MapEditorGameplaySemanticService.add_entry(document, "door", tile, {"door_id":door_id, "target_map_id":target, "target_tile":[0,0], "display_name":label, "source":"vanilla_176_recomposed"})
	assert(result.ok, str(result.get("errors", [])))
