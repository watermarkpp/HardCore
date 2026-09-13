class_name UIItemNameStyle
extends RefCounted

## Presentation only. Never consult price, drop denominators, rolls or instance_id.
## The installer compiles frozen membership into an exact canonical-ID UI table.
const DATA_PATH := "res://assets/data/ui/item_name_rarity_v1.json"
const CONTRACT := "ui.item_name.rarity.v1"
const DEFAULT_COLOR := Color("E6DDCB")
const MESSAGE_COLOR := Color("F2C783")
static var _loaded := false
static var _valid := false
static var _records: Dictionary = {}
static var _colors: Dictionary = {}
static var _outlines: Dictionary = {}

static func ensure_loaded() -> bool:
	if _loaded:
		return _valid
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_error("R6_NAME_STYLE_DATA_MISSING")
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not data is Dictionary or str(data.get("contract_id", "")) != CONTRACT:
		push_error("R6_NAME_STYLE_DATA_INVALID")
		return false
	var records: Variant = data.get("records", {})
	var palette: Variant = data.get("palette", {})
	if not records is Dictionary or not palette is Dictionary:
		push_error("R6_NAME_STYLE_SCHEMA_INVALID")
		return false
	for group: String in ["default", "wooma", "zuma", "redmoon", "ultra_rare"]:
		if not palette.has(group) or not Color.html_is_valid(str(palette[group])):
			push_error("R6_NAME_STYLE_PALETTE_INVALID")
			return false
		_colors[group] = Color(str(palette[group]))
	_records = records
	_outlines = data.get("outline_styles", {})
	_valid = true
	return true

static func canonical_id(record: Dictionary) -> int:
	# These are catalog IDs, not the opaque identity of a specific rolled item.
	for key: String in ["canonical_item_id", "item_id", "itemId", "stableItemId", "id"]:
		if not record.has(key):
			continue
		var value: Variant = record[key]
		if value is bool:
			continue
		if value is String:
			if (value as String).is_valid_int() and int(value) > 0:
				return int(value)
		elif value is int:
			if value > 0:
				return int(value)
		elif value is float:
			if is_finite(value) and value > 0.0 and value == floorf(value):
				return int(value)
	return -1

static func display_name(item: Dictionary, instance: Dictionary = {}) -> String:
	for record: Dictionary in [instance, item]:
		for key: String in ["name", "display_name", "item_name", "itemName"]:
			var value: Variant = record.get(key, "")
			if value is String and not (value as String).strip_edges().is_empty():
				return (value as String).strip_edges()
	ensure_loaded()
	var item_id := canonical_id(item)
	if item_id <= 0:
		item_id = canonical_id(instance)
	var row: Dictionary = _records.get(str(item_id), {})
	var fallback := str(row.get("canonical_name", "")).strip_edges()
	return fallback if not fallback.is_empty() else "未知物品"

static func describe(item: Dictionary, instance: Dictionary = {}) -> Dictionary:
	ensure_loaded()
	var item_id := canonical_id(item)
	var instance_item_id := canonical_id(instance)
	var conflict := item_id > 0 and instance_item_id > 0 and item_id != instance_item_id
	if item_id <= 0:
		item_id = instance_item_id
	var row: Dictionary = _records.get(str(item_id), {}) if not conflict else {}
	var group := str(row.get("name_style", "default"))
	return {
		"item_id": item_id,
		"name": display_name(item, instance),
		"tier": str(row.get("source_tier", "UNCLASSIFIED")),
		"group": group,
		"color": _colors.get(group, DEFAULT_COLOR),
		"outline": _outlines.get(group, {}),
		"identity_conflict": conflict,
		"known": not row.is_empty(),
	}


static func apply_label_style(label: Label, style: Dictionary, fallback_color := DEFAULT_COLOR) -> void:
	label.add_theme_color_override("font_color", style.get("color", fallback_color))
	var outline: Dictionary = style.get("outline", {})
	if not outline.is_empty():
		label.add_theme_color_override("font_outline_color", Color(str(outline["color"])))
		label.add_theme_constant_override("outline_size", int(outline["size"]))
	else:
		# Reused detail titles, shop cards and toast labels must shed the rare
		# outline when they next display an ordinary item, message or currency.
		label.remove_theme_color_override("font_outline_color")
		label.remove_theme_constant_override("outline_size")
