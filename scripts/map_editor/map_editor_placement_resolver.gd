class_name MapEditorPlacementResolver
extends RefCounted


static func resolve(document: Dictionary, asset_id: String, tile: Vector2i, layer := "object_base", role := "decoration") -> Dictionary:
	var validation := MapEditorPlacementValidator.validate(document, asset_id, tile, layer, role)
	var asset: Dictionary = validation.get("asset", {})
	var footprint: Array = asset.get("footprint_tiles", [1,1])
	var size_raw: Array = document.design.get("design_size", [64,64])
	var size := Vector2i(int(size_raw[0]),int(size_raw[1]))
	var foot_tile := Vector2(float(tile.x)+float(footprint[0])*.5,float(tile.y)+float(footprint[1])*.5)
	var anchor_ground_px := MapEditorCoordinate.tile_to_ground_px(foot_tile,size)
	var anchor: Array = asset.get("placement_anchor_px",asset.get("anchor_px",[0,0]))
	return {"target_tile":tile,"anchor_ground_px":anchor_ground_px,"placement_anchor_px":Vector2(float(anchor[0]),float(anchor[1])),"sprite_top_left_ground_px":anchor_ground_px-Vector2(float(anchor[0]),float(anchor[1])),"footprint_tiles":Vector2i(int(footprint[0]),int(footprint[1])),"valid":validation.ok,"validation":validation}
