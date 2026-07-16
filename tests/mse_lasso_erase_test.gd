extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("lasso_erase", 990009, "Lasso Erase", Vector2i(32, 32))
	assert(MapEditorGroundService.initialize(document).ok)
	var paints: Array[Dictionary] = [
		{"tile": [4, 4], "asset_id": "v1_5.a001_01"},
		{"tile": [5, 4], "asset_id": "v1_5.a001_02"},
		{"tile": [5, 5], "asset_id": "v1_5.a001_03"},
	]
	var painted := MapEditorGroundService.record_tile_paint_batch(document, paints)
	assert(painted.ok)
	assert(MapEditorGroundService.tile_overrides(painted.state).size() == 3)
	var erased := MapEditorGroundService.record_tile_erase_batch(document, [Vector2i(4, 4), Vector2i(5, 5)])
	assert(erased.ok)
	var remaining := MapEditorGroundService.tile_overrides(erased.state)
	assert(remaining.size() == 1 and remaining.has("5,4"))
	print("MSE_LASSO_ERASE_PASS")
	get_tree().quit()
