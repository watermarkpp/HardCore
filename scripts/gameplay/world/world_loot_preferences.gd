extends RefCounted
## S mirror consumes actual Main device preference input; only Main persists it.
signal filter_changed(level: int)
var _owner := OS.get_thread_caller_id()
var filter_level: int
var _tiers: Dictionary
var _published_rarity_table: Dictionary

func _init(publication: Dictionary) -> void:
	assert(_owner != OS.get_main_thread_id())
	assert(publication.get("contract_id") == "world.loot.preferences.original_handoff.v1")
	assert(publication.get("filter_level") is int and publication.filter_level >= 0 and publication.filter_level <= 2)
	assert(publication.get("tiers") is Dictionary and publication.get("rarity_table") is Dictionary and publication.rarity_table.get("records") is Dictionary)
	filter_level = publication.filter_level
	_tiers = publication.tiers.duplicate(true)
	_published_rarity_table = publication.rarity_table

func owner_thread_id() -> int: return _owner
func accept_original_main_filter_input(level: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if level < 0 or level > 2: return false
	if level == filter_level: return true
	filter_level = level
	filter_changed.emit(level)
	return true

static func capture_original_main(source: Node) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	assert(source != null and source.get_script() == load("res://scripts/loot_preferences.gd"))
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/ui/item_name_rarity_v1.json"))
	assert(table is Dictionary and table.get("records") is Dictionary)
	return {"contract_id":"world.loot.preferences.original_handoff.v1",
		"filter_level":source.filter_level,"tiers":source._tiers,"rarity_table":table}

func filter_threshold_for_item(item_id: int) -> int:
	if _tiers.is_empty():
		# User-approved exact-ID rarity membership is the filter's classification.
		# Memory, rainbow and magicblood now follow their Wooma name tier.
		var table: Dictionary = _published_rarity_table
		for id: String in table.get("records", {}):
			var row: Dictionary = table.records[id]
			var exempt := str(row.get("source_tier", "")) in ["MYSTERY_SIGNATURE","SPECIAL_RING","FUNCTIONAL_SPECIAL"]
			var style := str(row.get("name_style", "default"))
			_tiers[int(id)] = 0 if exempt or style not in ["default", "wooma"] else (1 if style == "default" else 2)
	return int(_tiers.get(item_id, 0))
