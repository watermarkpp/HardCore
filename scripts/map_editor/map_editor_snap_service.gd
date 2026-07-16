class_name MapEditorSnapService
extends RefCounted

enum SnapMode { TILE, HALF_TILE, QUARTER_TILE, PIXEL_FREE }


static func snap_tile(tile: Vector2, mode: SnapMode) -> Vector2:
	var step := 1.0
	match mode:
		SnapMode.HALF_TILE: step = 0.5
		SnapMode.QUARTER_TILE: step = 0.25
		SnapMode.PIXEL_FREE: return tile
	return (tile / step).round() * step
