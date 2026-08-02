extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich();assert(not runtime.is_empty())
	assert(runtime.semantics.safe_area.size()==1)
	var safe:Dictionary=runtime.semantics.safe_area[0]
	assert(bool(safe.runtime_export))
	var expected_home:=MapEditorRuntimeBridge.grid_cell_to_screen_position_px(runtime,safe.get("return_tile",safe.get("tile",[32,32])))
	assert(MapEditorRuntimeBridge.home_position().is_equal_approx(expected_home))
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.safe_areas.size()==1 and content.spawns.size()==runtime.semantics.monster_spawn.size() and content.npcs.size()==7)
	var roles:=[]
	for npc:Dictionary in content.npcs:roles.append(str(npc.kind))
	assert(roles.count("shop")==4 and roles.has("trainer") and roles.has("quest") and roles.has("warehouse"))
	var safe_zone:Dictionary=content.safe_areas[0]
	var safe_center_ground_gu:Vector2=safe_zone.center_ground_gu
	var safe_radius_gu:=float(safe_zone.radius_gu)
	assert(safe_zone.shape=="circle" and safe_zone.polygon_ground_gu.is_empty())
	assert(safe_center_ground_gu.is_equal_approx(MapEditorRuntimeBridge.home_position_ground_gu()))
	assert(is_equal_approx(safe_radius_gu,9.0))
	assert(not safe_zone.has("radius") and not safe_zone.has("radius_tiles"))
	for spawn:Dictionary in content.spawns:
		assert(not GameData.get_monster(str(spawn.name)).is_empty())
		assert(spawn.position_ground_gu.distance_to(safe_center_ground_gu)>safe_radius_gu)
	assert(WorldSpatialRules.point_inside_safe_zone_ground_gu(safe_center_ground_gu,safe_zone))
	for direction_index in range(32):
		var angle:=TAU*float(direction_index)/32.0
		var direction_ground_gu:=Vector2(cos(angle),sin(angle))
		var inside_ground_gu:=safe_center_ground_gu+direction_ground_gu*(safe_radius_gu-0.1)
		var outside_ground_gu:=safe_center_ground_gu+direction_ground_gu*(safe_radius_gu+0.1)
		var inside_screen_px:=MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime,inside_ground_gu)
		var restored_inside_ground_gu:=MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(runtime,inside_screen_px)
		assert(restored_inside_ground_gu.distance_to(inside_ground_gu)<=0.0001)
		assert(WorldSpatialRules.point_inside_safe_zone_ground_gu(restored_inside_ground_gu,safe_zone))
		assert(not WorldSpatialRules.point_inside_safe_zone_ground_gu(outside_ground_gu,safe_zone))
	print("BICH_CONTENT_1_PASS")
	get_tree().quit()
