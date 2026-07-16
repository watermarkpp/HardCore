class_name MapEditorGridService
extends RefCounted


static func visible_grid_lines(design_size: Vector2i, interval := 1) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var step := maxi(1, interval)
	for x in range(0, design_size.x + 1, step):
		lines.append(PackedVector2Array([
			MapEditorCoordinate.tile_to_ground_px(Vector2(x, 0), design_size),
			MapEditorCoordinate.tile_to_ground_px(Vector2(x, design_size.y), design_size),
		]))
	for y in range(0, design_size.y + 1, step):
		lines.append(PackedVector2Array([
			MapEditorCoordinate.tile_to_ground_px(Vector2(0, y), design_size),
			MapEditorCoordinate.tile_to_ground_px(Vector2(design_size.x, y), design_size),
		]))
	return lines
