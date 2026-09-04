extends Node

const Coordinate := preload("res://scripts/map_editor/map_editor_coordinate.gd")

const MAP_KEY := "world_bich_province"
const DESIGN_SIZE := Vector2i(80, 80)
const WORKSPACE_ROOT := "res://map_editor_workspace/%s" % MAP_KEY


func _ready() -> void:
	var manifest := _read_json(WORKSPACE_ROOT + "/ground/ground_manifest.json")
	var state := _read_json(WORKSPACE_ROOT + "/ground/ground_state.json")
	assert(
		str(manifest.get("coordinate_contract_id", ""))
		== Coordinate.GROUND_COORDINATE_CONTRACT_ID
	)
	assert(
		str(state.get("coordinate_contract_id", ""))
		== Coordinate.GROUND_COORDINATE_CONTRACT_ID
	)
	assert((state.get("dirty_chunks", []) as Array).is_empty())
	assert(
		Vector2i(
			int(manifest.get("ground_pixel_size", [0, 0])[0]),
			int(manifest.get("ground_pixel_size", [0, 0])[1])
		) == Coordinate.ground_image_size(DESIGN_SIZE)
	)

	var alpha_union := Rect2i()
	var has_alpha := false
	var materialized := 0
	for chunk: Dictionary in manifest.get("chunks", []):
		if not bool(chunk.get("materialized", false)):
			continue
		materialized += 1
		assert(
			str(chunk.get("baked_coordinate_contract_id", ""))
			== Coordinate.GROUND_COORDINATE_CONTRACT_ID
		)
		var raw_rect: Array = chunk.get("rect_px", [])
		assert(raw_rect.size() == 4)
		var chunk_origin := Vector2i(int(raw_rect[0]), int(raw_rect[1]))
		var relative_path := str(chunk.get("preview_png", ""))
		var image := Image.load_from_file(
			ProjectSettings.globalize_path(WORKSPACE_ROOT + "/" + relative_path)
		)
		assert(image != null and not image.is_empty())
		var used := image.get_used_rect()
		if not used.has_area():
			continue
		var global_used := Rect2i(chunk_origin + used.position, used.size)
		alpha_union = global_used if not has_alpha else alpha_union.merge(global_used)
		has_alpha = true

	assert(materialized == 13)
	assert(has_alpha)
	# The normalized diamond mask leaves one transparent corner pixel on each
	# horizontal tip. Vertically, however, the authored ground must now occupy
	# the complete 0..2560 canvas with no half-cell gap or clipping.
	assert(alpha_union.position.x == 1)
	assert(alpha_union.end.x == 5119)
	assert(alpha_union.position.y == 0)
	assert(alpha_union.end.y == 2560)
	print(
		"WORLD_BICH_GROUND_V2_PIXEL_ALIGNMENT_PASS chunks=%d alpha_union=%s"
		% [materialized, alpha_union]
	)
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
