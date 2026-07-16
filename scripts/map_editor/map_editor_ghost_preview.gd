class_name MapEditorGhostPreview
extends RefCounted


static func build(document: Dictionary, asset_id: String, anchor_tile: Vector2i, layer := "ground_base") -> Dictionary:
	var placement := MapEditorPlacementResolver.resolve(document,asset_id,anchor_tile,layer)
	var validation: Dictionary = placement.validation
	var footprint:Vector2i = placement.footprint_tiles
	var design_size: Array = document.design.design_size
	var size := Vector2i(int(design_size[0]), int(design_size[1]))
	var width:int = footprint.x
	var height:int = footprint.y
	var points := PackedVector2Array([
		MapEditorCoordinate.tile_to_ground_px(anchor_tile, size),
		MapEditorCoordinate.tile_to_ground_px(anchor_tile + Vector2i(width, 0), size),
		MapEditorCoordinate.tile_to_ground_px(anchor_tile + Vector2i(width, height), size),
		MapEditorCoordinate.tile_to_ground_px(anchor_tile + Vector2i(0, height), size),
	])
	var color := Color("5ecf7a") if validation.level == "ok" else Color("e5b85c") if validation.level == "warning" else Color("e35b5b")
	return {"validation": validation, "placement":placement, "polygon_ground_px": points, "color": color}
