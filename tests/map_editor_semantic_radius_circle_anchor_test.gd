extends Node

## Regression: semantic radius rings (monster_spawn / boss_spawn / safe_area /
## light / region_trigger) must be projected into the editor canvas ground-px
## space (tile_to_ground_px), the same space as the marker diamonds.  The
## radius_tiles -> radius_gu migration briefly projected center-relative GU
## deltas instead, which drew every ring with a positive radius off the map
## toward the canvas top-left.  The midpoint assertions below fail under that
## projection and pass only when the ring stays anchored on its marker.

const PreviewScript := preload("res://scripts/map_editor/map_editor_canvas_preview.gd")


func _ready() -> void:
	for synthetic_size: Vector2i in [Vector2i(80, 80), Vector2i(64, 48)]:
		for tile: Vector2i in [Vector2i(12, 9), Vector2i(40, 40), Vector2i(63, 47)]:
			var center_ground_gu := Vector2(tile) + Vector2(0.5, 0.5)
			var radius_gu := 3.0
			var circle: PackedVector2Array = PreviewScript.semantic_area_circle_ground_px(
				center_ground_gu, radius_gu, synthetic_size
			)
			assert(circle.size() == 33, "ring must keep 33 closed samples")
			assert(
				circle[0].is_equal_approx(circle[32]),
				"ring polyline must be closed"
			)
			var marker_center := MapEditorCoordinate.cell_center_to_ground_px(
				Vector2(tile), synthetic_size
			)
			assert(
				((circle[0] + circle[16]) * 0.5).is_equal_approx(marker_center),
				"east/west ring midpoint must equal marker center size=%s tile=%s" % [
					synthetic_size, tile
				]
			)
			assert(
				((circle[8] + circle[24]) * 0.5).is_equal_approx(marker_center),
				"south/north ring midpoint must equal marker center size=%s tile=%s" % [
					synthetic_size, tile
				]
			)
			assert(
				circle[0].is_equal_approx(MapEditorCoordinate.tile_to_ground_px(
					center_ground_gu + Vector2(radius_gu, 0.0), synthetic_size
				)),
				"ring east point must use the canvas ground-px projection"
			)
	print("MAP_EDITOR_SEMANTIC_RADIUS_CIRCLE_ANCHOR_PASS sizes=80x80,64x48 tiles=3")
	get_tree().quit(0)
