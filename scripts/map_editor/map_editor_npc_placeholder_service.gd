class_name MapEditorNpcPlaceholderService
extends RefCounted


static func ensure_entry(document:Dictionary,semantic_id:String)->Dictionary:
	for index in document.layers.get("npc_points",[]).size():
		var entry:Dictionary=document.layers.npc_points[index]
		if str(entry.get("semantic_id",""))!=semantic_id:continue
		entry.merge({"placeholder_instance_id":"npc_placeholder_%s"%semantic_id,"object_role":"npc_placeholder","editor_visual_asset_id":"editor_npc_placeholder_humanoid","editor_visual_only":true,"tile_anchor":entry.get("tile",[0,0]),"offset_px":[0,0],"placement_anchor_px":[32,48],"selection_shape":{"type":"bounds","padding_px":4},"occupancy_footprint_tiles":[1,1],"npc_occupancy_profile_id":"npc_humanoid_1x1","collision_policy":"profile","collision_profile_id":"small_prop_1x1","selectable":true,"movable":true},true)
		document.layers.npc_points[index]=entry
		return {"ok":true,"entry":entry}
	return {"ok":false,"errors":["未找到NPC"]}
