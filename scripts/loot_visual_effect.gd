class_name LootVisualEffect
extends Node2D

## Lightweight ground presentation owned by one LootPickup.
##
## The effect has no ParticleSystem, PointLight, timer, or global scan.  Its
## only dynamic state is the immutable item-instance snapshot supplied at
## construction, so the pickup remains the sole lifetime owner.
const TIER_AUTHORITY_PATH := "res://assets/data/drop/dpv2_item_tier_authority_v1.json"
const ItemDropInstanceRulesScript := preload("res://scripts/item_drop_instance_rules.gd")
const ItemNameStyle := preload("res://scripts/ui_item_name_style.gd")
const VISUAL_CONTRACT := "loot.ground_visual.tier_beam_affix_label.v1"
const AFFIX_CONTRACT_ID := "item.drop.affix.v1"
const GOLDEN_BEAM_COLOR := Color("f6c75b")
const AFFIX_LABEL_COLOR := Color("ffd86b")
const GOLDEN_BEAM_TIERS := {
	"WOOMA_GEAR": true,
	"ZUMA_GEAR": true,
	"REDMOON_SET": true,
	"HIGH_CLASS_WEAPON": true,
	"EXPANDED_HIGH_WEAPON": true,
	"LEGENDARY_WEAPON": true,
	"NEW_CLOTHES": true,
	"MAGICBLOOD_RAINBOW": true,
	"SPECIAL_RING": true,
}
## The frozen tier table stores the exact equipment slot in `item_type` rather
## than a generic kind string.  Keep this finite allowlist in lockstep with that
## authority; an unknown or empty item_type must fail closed.
const EQUIPMENT_AUTHORITY_ITEM_TYPES := {
	"武器": true,
	"戒指": true,
	"盔甲": true,
	"手镯": true,
	"头盔": true,
	"项链": true,
}

static var _authority_loaded := false
static var _authority_by_id: Dictionary = {}


static func prewarm_authority() -> void:
	_ensure_authority()

var item_id := -1
var item_tier := ""
var beam_visible := false
var affix_highlighted := false
var _item_record: Dictionary = {}


func configure(identity_record: Dictionary, template_label_color := Color(0.90, 0.82, 0.66)) -> void:
	_item_record = identity_record.duplicate(true)
	item_id = exact_item_id(_item_record)
	item_tier = tier_for_record(_item_record)
	beam_visible = has_golden_beam_for_record(_item_record)
	affix_highlighted = affix_is_valid(_item_record)
	set_meta("loot_visual_contract", VISUAL_CONTRACT)
	set_meta("loot_visual_item_id", item_id)
	set_meta("loot_visual_tier", item_tier)
	set_meta("loot_visual_beam", beam_visible)
	set_meta("loot_visual_affix_highlight", affix_highlighted)
	set_meta("loot_visual_template_label_color", template_label_color)
	set_meta("loot_visual_label_color", label_color_for_record(_item_record, template_label_color))
	queue_redraw()


func has_golden_beam() -> bool:
	return beam_visible


func is_affix_highlighted() -> bool:
	return affix_highlighted


func visual_descriptor() -> Dictionary:
	return {
		"contract": VISUAL_CONTRACT,
		"item_id": item_id,
		"tier": item_tier,
		"golden_beam": beam_visible,
		"affix_highlight": affix_highlighted,
	}


static func tier_for_record(identity_record: Dictionary) -> String:
	var record := authority_record_for_record(identity_record)
	return str(record.get("tier", ""))


static func authority_record_for_record(identity_record: Dictionary) -> Dictionary:
	_ensure_authority()
	var exact_id := exact_item_id(identity_record)
	var record: Variant = _authority_by_id.get(exact_id, {})
	return record.duplicate(true) if record is Dictionary else {}


static func has_golden_beam_for_record(identity_record: Dictionary) -> bool:
	var authority := authority_record_for_record(identity_record)
	if authority.is_empty():
		return false
	var tier := str(authority.get("tier", ""))
	if not GOLDEN_BEAM_TIERS.has(tier):
		return false
	var presentation := _presentation_record(identity_record)
	return _record_is_equipment(presentation, authority)


static func label_color_for_record(identity_record: Dictionary, template_color: Color) -> Color:
	# Names share the same exact-ID palette as the inventory and pickup toast.
	# The instance's affix and golden beam remain independent visual metadata.
	var id := exact_item_id(identity_record)
	return ItemNameStyle.describe({"item_id": id}).color if id > 0 else template_color


static func affix_is_valid(identity_record: Dictionary) -> bool:
	# W7 places the immutable roll under the complete identity record's
	# `item_instance`.  A top-level drop_affix/modifiers pair is intentionally
	# ignored: accepting it would let a template or forged presentation payload
	# recolor an ordinary item.
	var instance_value: Variant = identity_record.get("item_instance", null)
	if not instance_value is Dictionary:
		return false
	var authority := authority_record_for_record(identity_record)
	if authority.is_empty():
		return false
	var presentation := _presentation_record(identity_record)
	if not _record_is_equipment(presentation, authority):
		return false
	# Reuse the formal W7 validator and its exact primary attribute mappings;
	# visual code never creates or widens an instance contract.
	return ItemDropInstanceRulesScript.is_affixed_instance(
		instance_value as Dictionary,
		presentation,
	)


static func exact_item_id(identity_record: Dictionary) -> int:
	var output_item_id := _integer_field(identity_record, "output_item_id")
	if output_item_id >= 0:
		return output_item_id
	var nested_value: Variant = identity_record.get("output_record", {})
	if nested_value is Dictionary:
		var nested_id := _catalog_id(nested_value as Dictionary)
		if nested_id >= 0:
			return nested_id
	return _catalog_id(identity_record)


static func reset_cache_for_test() -> void:
	_authority_loaded = false
	_authority_by_id.clear()


func _draw() -> void:
	if not beam_visible:
		return
	# A small static beam is cheap to draw and is intentionally behind the icon;
	# no per-item particle emitter or offscreen simulation is created.
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-5.0, -9.0), Vector2(5.0, -9.0),
			Vector2(9.0, 10.0), Vector2(-9.0, 10.0),
		]),
		Color(GOLDEN_BEAM_COLOR.r, GOLDEN_BEAM_COLOR.g, GOLDEN_BEAM_COLOR.b, 0.16),
	)
	draw_line(Vector2(-2.0, -10.0), Vector2(-2.0, 10.0), Color(GOLDEN_BEAM_COLOR.r, GOLDEN_BEAM_COLOR.g, GOLDEN_BEAM_COLOR.b, 0.50), 1.0)
	draw_line(Vector2(2.0, -10.0), Vector2(2.0, 10.0), Color(GOLDEN_BEAM_COLOR.r, GOLDEN_BEAM_COLOR.g, GOLDEN_BEAM_COLOR.b, 0.50), 1.0)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 16, Color(GOLDEN_BEAM_COLOR.r, GOLDEN_BEAM_COLOR.g, GOLDEN_BEAM_COLOR.b, 0.38), 1.0)


static func _ensure_authority() -> void:
	if _authority_loaded:
		return
	_authority_loaded = true
	var file := FileAccess.open(TIER_AUTHORITY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var raw_records: Variant = (parsed as Dictionary).get("records", [])
	if not raw_records is Array:
		return
	for raw_record: Variant in raw_records as Array:
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var record_id := int(record.get("canonical_item_id", -1))
		if record_id >= 0:
			_authority_by_id[record_id] = record.duplicate(true)


static func _presentation_record(identity_record: Dictionary) -> Dictionary:
	var nested_value: Variant = identity_record.get("output_record", {})
	if nested_value is Dictionary:
		return nested_value as Dictionary
	return identity_record


static func _record_is_equipment(record: Dictionary, authority: Dictionary) -> bool:
	if str(record.get("kind", "")).to_lower() != "equipment":
		return false
	var authority_type := str(authority.get("item_type", ""))
	return EQUIPMENT_AUTHORITY_ITEM_TYPES.has(authority_type)


static func _catalog_id(record: Dictionary) -> int:
	for key: String in ["item_id", "itemId", "canonical_item_id", "canonicalItemId", "stableItemId", "id"]:
		var parsed := _integer_field(record, key)
		if parsed >= 0:
			return parsed
	return -1


static func _integer_field(record: Dictionary, key: String) -> int:
	if not record.has(key):
		return -1
	var value: Variant = record.get(key)
	if value is String:
		if not (value as String).is_valid_int():
			return -1
	elif typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return -1
	if not is_finite(float(value)):
		return -1
	var parsed := int(value)
	return parsed if parsed >= 0 and float(parsed) == float(value) else -1
