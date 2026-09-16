class_name EditorChunkGroundCanvas
extends Node2D

## FW-STRIPES (user device report 2026-09-16, top-priority ruling): authored
## ground chunks carry 1px baked diamond grid lines. Under the frozen
## CAMERA_ZOOM 1.06 with NEAREST sampling, every grid line's screen width
## oscillates between ~0 and ~2px while the smoothed camera transform moves,
## and the whole diamond grid shimmers in crawling row patterns - the
## "ground refresh stripes" the user reported as dizzying.
##
## This dedicated canvas item renders ALL authored ground chunks on ONE
## CanvasItem (preserving the established single-item contract that avoids
## per-chunk culling and deferred GPU uploads) with LINEAR sampling, which
## renders the grid lines at a stable sub-pixel width while the camera
## moves. At the frozen zoom of 1.06 the interpolation cost is negligible
## and no atlas sub-region sampling happens on this path, so there is no
## edge-bleed risk. The camera constraint solver, its frozen parameters and
## the position smoothing are deliberately untouched.

var _chunk_draws: Array[Dictionary] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func set_chunk_draws(chunk_draws: Array[Dictionary]) -> void:
	_chunk_draws = chunk_draws
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func chunk_draw_count() -> int:
	return _chunk_draws.size()


func _draw() -> void:
	for chunk_draw: Dictionary in _chunk_draws:
		var texture: Texture2D = chunk_draw.get("texture")
		var rect: Rect2 = chunk_draw.get("rect", Rect2())
		if texture != null and rect.size.x > 0.0 and rect.size.y > 0.0:
			draw_texture_rect(texture, rect, false)
