extends Node


func _ready()->void:
	var tents:Array=[]
	for asset:Dictionary in MapAssetCatalogService.all_assets():
		assert(asset.has("collision_policy"),str(asset.get("asset_id","")))
		assert(asset.has("collision_profile_id"),str(asset.get("asset_id","")))
		assert(asset.has("approved_scale"),str(asset.get("asset_id","")))
		assert(asset.has("placement_anchor_px"),str(asset.get("asset_id","")))
		if str(asset.get("object_class",""))=="tent":tents.append(asset)
	assert(tents.size()==6)
	for tent:Dictionary in tents:
		assert(tent.class_profile_id=="tent_blacksmith_standard")
		assert(int(tent.footprint_tiles[0])==8 and int(tent.footprint_tiles[1])==8 and int(tent.collision_footprint_tiles[0])==8 and int(tent.collision_footprint_tiles[1])==8)
	var document:=MapEditorTypes.new_map("v351",991351,"V351",Vector2i(64,64))
	var placement:=MapEditorPlacementResolver.resolve(document,tents[0].asset_id,Vector2i(10,10),"object_base","building")
	assert(placement.valid and placement.footprint_tiles==Vector2i(8,8))
	var npc:=MapEditorGameplaySemanticService.add_entry(document,"npc",Vector2i(20,20),{"content_id":"npc.4.005","npc_id":"npc.4.005","display_name":"比奇老兵","facing":"south"})
	assert(npc.ok and MapEditorNpcPlaceholderService.ensure_entry(document,npc.entry.semantic_id).ok)
	assert(document.layers.npc_points[0].editor_visual_only and document.layers.npc_points[0].selectable)
	assert(MapEditorGameplaySemanticService.move_entry(document,npc.entry.semantic_id,Vector2i(1,0)).ok and document.layers.npc_points[0].tile==[21,20])
	assert(MapEditorGroundService.initialize(document).ok)
	assert(MapEditorBuildRuntimeService.approve_for_runtime(document).ok)
	var built:=MapEditorBuildRuntimeService.build(document,"user://v351_runtime.json"); assert(built.ok)
	assert(not built.runtime.semantics.npc_points[0].has("editor_visual_asset_id"))
	assert(built.runtime.semantics.npc_points[0].npc_id=="npc.4.005")
	print("MSE_V351_PROFILES_SELECTION_PASS")
	get_tree().quit()
