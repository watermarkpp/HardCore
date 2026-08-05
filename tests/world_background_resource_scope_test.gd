extends Node

# Verify WorldBackground lazy-loads atlases (no region preloads at class-init)
func _ready() -> void:
	const WorldBackgroundScript := preload("res://scripts/world_background.gd")
	var wb := WorldBackgroundScript.new()
	
	# Verify _region_atlas public API
	assert(wb.has_method("_region_atlas"))
	assert(wb.has_method("_bich_ground_atlas"))
	
	# Initial atlas cache should be empty (no preloads)
	assert(wb._atlas_cache.is_empty())
	
	# First access loads and caches
	var at := wb._bich_ground_atlas()
	assert(at != null)
	assert(wb._atlas_cache.has("bich_ground"))
	
	# Second access hits cache
	var at2 := wb._bich_ground_atlas()
	assert(at2 == at)
	
	wb.free()
	print("WORLD_BACKGROUND_RESOURCE_SCOPE_TEST_PASS")
	get_tree().quit(0)
