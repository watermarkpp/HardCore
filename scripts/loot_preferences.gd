extends Node

## Device preference only; never an input to drop generation or inventory.
signal filter_changed(level: int)
var filter_level := 0
var storage_path := "user://loot_preferences_v1.cfg"
var dirty := false
var last_save_error := OK
var _tiers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_preferences()

func load_preferences() -> void:
	var saved := _read_level(storage_path)
	if saved < 0:
		saved = _read_level(storage_path + ".bak")
	filter_level = maxi(0, saved)
	filter_changed.emit(filter_level)

func set_filter_level(value: int) -> void:
	if value < 0 or value > 2 or value == filter_level:
		return
	filter_level = value
	dirty = true
	filter_changed.emit(value)

func filter_threshold_for_item(item_id: int) -> int:
	if _tiers.is_empty():
		# User-approved exact-ID rarity membership is the filter's classification.
		# Memory, rainbow and magicblood now follow their Wooma name tier.
		var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/ui/item_name_rarity_v1.json"))
		for id: String in table.get("records", {}):
			var row: Dictionary = table.records[id]
			var exempt := str(row.get("source_tier", "")) in ["MYSTERY_SIGNATURE","SPECIAL_RING","FUNCTIONAL_SPECIAL"]
			var style := str(row.get("name_style", "default"))
			_tiers[int(id)] = 0 if exempt or style not in ["default", "wooma"] else (1 if style == "default" else 2)
	return int(_tiers.get(item_id, 0))

func _read_level(path: String) -> int:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return -1
	var version: Variant = config.get_value("meta", "version", null)
	var value: Variant = config.get_value("loot", "filter_level", null)
	if not version is int or version != 1 or not value is int or value < 0 or value > 2:
		return -1
	return int(value)

func flush() -> Error:
	if not dirty:
		return OK
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("loot", "filter_level", filter_level)
	var error := config.save(storage_path + ".tmp")
	if error == OK and _read_level(storage_path + ".tmp") != filter_level:
		error = ERR_FILE_CORRUPT
	if error == OK and _read_level(storage_path) >= 0:
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(storage_path), ProjectSettings.globalize_path(storage_path + ".bak"))
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(storage_path + ".tmp"), ProjectSettings.globalize_path(storage_path))
	last_save_error = error
	if error == OK:
		dirty = false
	return error

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		flush()

func _exit_tree() -> void:
	flush()
