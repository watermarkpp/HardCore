extends Node

func _ready() -> void:
	var document := MapEditorTypes.new_map_from_catalog("interaction_regression", "quest_room", 999998, "交互回归")
	var monster_entries := MapEditorContentCatalogService.entries("monster_spawn", 4)
	var boss_entries := MapEditorContentCatalogService.entries("boss_spawn", 4)
	assert(not monster_entries.is_empty())
	assert(not boss_entries.is_empty())
	var monster_id := str(monster_entries[0].content_id)
	var boss_id := str(boss_entries[0].content_id)
	assert(MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", Vector2i(10,10), {"content_id":monster_id,"monster_id":monster_id,"count":1,"max_alive":1,"respawn_seconds":60}).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "boss_spawn", Vector2i(12,12), {"content_id":boss_id,"boss_id":boss_id,"count":1,"max_alive":1,"respawn_seconds":60}).ok)
	var monster_layer: Array = document.layers.monster_spawn
	monster_layer.append(monster_layer[0].duplicate(true))
	document.layers.monster_spawn = monster_layer
	assert(MapEditorGameplaySemanticService.repair_duplicate_ids(document) == 1)
	assert(str(document.layers.monster_spawn[0].semantic_id) != str(document.layers.monster_spawn[1].semantic_id))
	var portal_asset := ""
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("object_class", "")) == "map_entrance": portal_asset = str(asset.asset_id); break
	assert(not portal_asset.is_empty())
	var map_size: Array = document.design.design_size
	var edge_portal := MapEditorInstanceService.create_instance(document, portal_asset, "terrain", Vector2i(int(map_size[0])-1,int(map_size[1])-1))
	assert(edge_portal.ok)
	assert(int(edge_portal.instance.collision_footprint_tiles[0]) == 0 and int(edge_portal.instance.collision_footprint_tiles[1]) == 0)
	var tree_asset := ""
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("object_class", "")) == "tree": tree_asset = str(asset.asset_id); break
	assert(not tree_asset.is_empty())
	var placed := MapEditorInstanceService.create_instance(document, tree_asset, "obstacle", Vector2i(20,20))
	assert(placed.ok)
	var before: Dictionary = placed.instance.duplicate(true)
	var resized := MapEditorInstanceService.resize_instance(document, str(before.instance_id), 1)
	assert(resized.ok)
	assert(maxi(int(resized.instance.footprint_tiles[0]),int(resized.instance.footprint_tiles[1])) == maxi(int(before.footprint_tiles[0]),int(before.footprint_tiles[1])) + 1)
	var collision_size := MapEditorCollisionService._collision_footprint(resized.instance)
	var collision_origin := MapEditorCollisionService._collision_origin(resized.instance)
	var visual_tile: Array = resized.instance.tile
	var visual_fp: Array = resized.instance.footprint_tiles
	var visual_anchor := Vector2(float(visual_tile[0]) + float(visual_fp[0]) * 0.5, float(visual_tile[1]) + float(visual_fp[1]) * 0.5)
	var collision_bottom := Vector2(float(collision_origin.x + collision_size.x), float(collision_origin.y + collision_size.y))
	assert(absf((collision_bottom.x + collision_bottom.y) - (visual_anchor.x + visual_anchor.y)) <= 1.0)
	print("MSE_INTERACTION_REGRESSION_PASS")
	get_tree().quit()
