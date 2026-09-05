extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich();assert(not runtime.is_empty())
	assert(runtime.semantics.safe_area.size()==1)
	var authored_safe:Dictionary=runtime.semantics.safe_area[0]
	assert(bool(authored_safe.runtime_export))
	assert(str(authored_safe.shape)=="polygon")
	assert(float(authored_safe.radius_gu)==0.0)
	var safe_polygon:Array=authored_safe.get("polygon_ground_gu",[])
	assert(safe_polygon.size()>=3 and safe_polygon[0]==safe_polygon[safe_polygon.size()-1])
	var safe_tile:Array=authored_safe.get("tile",[32,32])
	var expected_home:=MapEditorRuntimeBridge.grid_cell_to_screen_position_px(runtime,safe_tile)
	assert(MapEditorRuntimeBridge.home_screen_position_px().is_equal_approx(expected_home))
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.safe_areas.size()==1 and content.spawns.size()==runtime.semantics.monster_spawn.size() and content.npcs.size()==7)
	var runtime_npc_ids:=[]
	var veteran_at_target:=0
	for npc:Dictionary in runtime.semantics.npc_points:
		runtime_npc_ids.append(str(npc.get("semantic_id","")))
		if str(npc.get("service_identity_id",""))=="npc.service.veteran.v1" and npc.get("tile")==[24.0,39.0]:
			veteran_at_target+=1
	assert(runtime_npc_ids.size()==7 and runtime_npc_ids.has("npc_000005") and not runtime_npc_ids.has("npc_000008"))
	assert(veteran_at_target==1)
	var roles:=[]
	for npc:Dictionary in content.npcs:roles.append(str(npc.kind))
	assert(roles.count("shop")==4 and roles.has("trainer") and roles.has("quest") and roles.has("warehouse"))
	var safe_center_ground_gu:=MapEditorRuntimeBridge.cell_to_ground_position_gu(safe_tile)
	assert(safe_center_ground_gu.is_equal_approx(MapEditorRuntimeBridge.home_position_ground_gu()))
	for spawn:Dictionary in content.spawns:
		assert(not GameData.get_monster_by_id(int(spawn.monster_id)).is_empty())
		assert(not WorldSpatialRules.point_inside_safe_zone_ground_gu(spawn.position_ground_gu,authored_safe))
	assert(WorldSpatialRules.point_inside_safe_zone_ground_gu(safe_center_ground_gu,authored_safe))
	var outside_ground_gu:=Vector2(0.5,0.5)
	assert(not WorldSpatialRules.point_inside_safe_zone_ground_gu(outside_ground_gu,authored_safe))
	for raw_point:Variant in safe_polygon:
		assert(raw_point is Array and raw_point.size()==2)
		var authored_point:=Vector2(float(raw_point[0]),float(raw_point[1]))
		var projected_point:=MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime,authored_point)
		var restored_point:=MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(runtime,projected_point)
		assert(restored_point.is_equal_approx(authored_point))
	var outside_screen_px:=MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime,outside_ground_gu)
	var restored_outside_ground_gu:=MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(runtime,outside_screen_px)
	assert(not WorldSpatialRules.point_inside_safe_zone_ground_gu(restored_outside_ground_gu,authored_safe))
	print("BICH_CONTENT_1_PASS")
	get_tree().quit()
