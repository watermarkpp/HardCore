extends RefCounted
const WorkingGraph := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
var _owner := OS.get_thread_caller_id()
var _content: RefCounted
var _item_instance_rules: RefCounted
var _authority_by_id: Dictionary
var _descriptor_cache: Dictionary
var _descriptor_build_count: int

func _init(content: RefCounted, item_instance_rules: RefCounted, publication: Dictionary) -> void:
	assert(_owner != OS.get_main_thread_id())
	assert(publication.get("contract_id") == "world.loot.descriptors.original_handoff.v1")
	assert(content != null and item_instance_rules != null and item_instance_rules.has_method("is_affixed_instance"))
	assert(publication.get("authority_by_id") is Dictionary and publication.get("descriptor_cache") is Dictionary and publication.get("descriptor_build_count") is int)
	var copied: Dictionary = WorkingGraph.restore_runtime_roots(publication)
	assert(copied.ok)
	_content = content
	_item_instance_rules = item_instance_rules
	_authority_by_id = copied.value.authority_by_id
	_descriptor_cache = copied.value.descriptor_cache
	_descriptor_build_count = copied.value.descriptor_build_count

func owner_thread_id() -> int: return _owner
func _ensure_authority() -> void:
	assert(OS.get_thread_caller_id() == _owner)

func instance_visual_facts(identity_record: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return {"item_id":exact_item_id(identity_record), "tier":tier_for_record(identity_record),
		"golden_beam":has_golden_beam_for_record(identity_record), "affix_highlighted":affix_is_valid(identity_record)}

static func capture_original_main() -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var source_pickup: Script = load("res://scripts/loot_pickup.gd")
	var source_visual: Script = load("res://scripts/loot_visual_effect.gd")
	source_visual.prewarm_authority()
	return {"contract_id":"world.loot.descriptors.original_handoff.v1",
		"authority_by_id":source_visual._authority_by_id,
		"descriptor_cache":source_pickup._descriptor_cache,
		"descriptor_build_count":source_pickup._descriptor_build_count}

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

const EQUIPMENT_AUTHORITY_ITEM_TYPES := {
	"武器": true,
	"戒指": true,
	"盔甲": true,
	"手镯": true,
	"头盔": true,
	"项链": true,
}

func ground_visual_descriptor(name: String) -> Dictionary:
	if _descriptor_cache.has(name):
		return _descriptor_cache[name].duplicate(true)
	var record: Variant = _content.get_item_record(name)
	return _ground_visual_descriptor_from_catalog_record(name, record, name)

func ground_visual_descriptor_for_record(identity_record: Dictionary) -> Dictionary:
	var output_record: Dictionary = {}
	var nested_output: Variant = identity_record.get("output_record", {})
	if nested_output is Dictionary:
		output_record = (nested_output as Dictionary).duplicate(true)
	var display_name: Variant = str(identity_record.get(
		"item_name",
		identity_record.get("name", identity_record.get("canonical_name", "")),
	))
	if output_record.is_empty() and not display_name.is_empty():
		return ground_visual_descriptor(display_name)
	if output_record.is_empty():
		return {}
	var output_item_id: Variant = int(identity_record.get("output_item_id", -1))
	var cache_key: Variant = (
		"item:%d" % output_item_id
		if output_item_id >= 0
		else "name:%s" % str(output_record.get("name", display_name))
	)
	return _ground_visual_descriptor_from_catalog_record(
		cache_key,
		output_record,
		display_name,
	)

func _ground_visual_descriptor_from_catalog_record(
	cache_key: String,
	record: Dictionary,
	fallback_name: String,
) -> Dictionary:
	if _descriptor_cache.has(cache_key):
		return _descriptor_cache[cache_key].duplicate(true)
	var art: Variant = record.get("art", {})
	var ground: Variant = art.get("groundIcon", {}) if art is Dictionary else {}
	var path: Variant = str(ground.get("path", "")) if ground is Dictionary else str(ground)
	var kind: Variant = str(record.get("kind", "material"))
	if path.is_empty():
		var fallback_key: Variant = str({"skill_book": "book", "consumable": "potion", "scroll": "scroll", "quest_item": "quest", "currency": "material", "material": "material"}.get(kind, "material"))
		path = str(_content.service_item_catalog.get("runtimeFallbackArt", {}).get(fallback_key, {}).get("ground", ""))
	var draw_color: Color = {"equipment": Color(0.35, 0.65, 0.95), "skill_book": Color(0.60, 0.38, 0.90), "consumable": Color(0.25, 0.75, 0.35), "quest_item": Color(0.90, 0.28, 0.12)}.get(kind, Color(0.95, 0.67, 0.12))
	var label_color: Color = {"equipment": Color(0.55, 0.82, 1.0), "skill_book": Color(0.72, 0.55, 1.0), "currency": Color(1.0, 0.82, 0.28), "consumable": Color(0.45, 0.92, 0.52), "quest_item": Color(1.0, 0.48, 0.25)}.get(kind, Color(0.90, 0.82, 0.66))
	var display_size: Variant = _content.get_item_art_display_size(record, "groundIcon")
	var descriptor: Variant = {"path": path, "kind": kind, "label_color": label_color, "fallback_draw_color": draw_color, "display_size": display_size}
	_descriptor_cache[cache_key] = descriptor
	_descriptor_build_count += 1
	return descriptor.duplicate(true)

func tier_for_record(identity_record: Dictionary) -> String:
	var record: Variant = authority_record_for_record(identity_record)
	return str(record.get("tier", ""))

func authority_record_for_record(identity_record: Dictionary) -> Dictionary:
	_ensure_authority()
	var exact_id: Variant = exact_item_id(identity_record)
	var record: Variant = _authority_by_id.get(exact_id, {})
	return record.duplicate(true) if record is Dictionary else {}

func has_golden_beam_for_record(identity_record: Dictionary) -> bool:
	var authority: Variant = authority_record_for_record(identity_record)
	if authority.is_empty():
		return false
	var tier: Variant = str(authority.get("tier", ""))
	if not GOLDEN_BEAM_TIERS.has(tier):
		return false
	var presentation: Variant = _presentation_record(identity_record)
	return _record_is_equipment(presentation, authority)

func affix_is_valid(identity_record: Dictionary) -> bool:
	# W7 places the immutable roll under the complete identity record's
	# `item_instance`.  A top-level drop_affix/modifiers pair is intentionally
	# ignored: accepting it would let a template or forged presentation payload
	# recolor an ordinary item.
	var instance_value: Variant = identity_record.get("item_instance", null)
	if not instance_value is Dictionary:
		return false
	var authority: Variant = authority_record_for_record(identity_record)
	if authority.is_empty():
		return false
	var presentation: Variant = _presentation_record(identity_record)
	if not _record_is_equipment(presentation, authority):
		return false
	# Reuse the formal W7 validator and its exact primary attribute mappings;
	# visual code never creates or widens an instance contract.
	return _item_instance_rules.is_affixed_instance(
		preload("res://scripts/items/item_extension_codec.gd").base_record(instance_value as Dictionary),
		presentation,
	)

func exact_item_id(identity_record: Dictionary) -> int:
	var output_item_id: Variant = _integer_field(identity_record, "output_item_id")
	if output_item_id >= 0:
		return output_item_id
	var nested_value: Variant = identity_record.get("output_record", {})
	if nested_value is Dictionary:
		var nested_id: Variant = _catalog_id(nested_value as Dictionary)
		if nested_id >= 0:
			return nested_id
	return _catalog_id(identity_record)

func _presentation_record(identity_record: Dictionary) -> Dictionary:
	var nested_value: Variant = identity_record.get("output_record", {})
	if nested_value is Dictionary:
		return nested_value as Dictionary
	return identity_record

func _record_is_equipment(record: Dictionary, authority: Dictionary) -> bool:
	if str(record.get("kind", "")).to_lower() != "equipment":
		return false
	var authority_type: Variant = str(authority.get("item_type", ""))
	return EQUIPMENT_AUTHORITY_ITEM_TYPES.has(authority_type)

func _catalog_id(record: Dictionary) -> int:
	for key: String in ["item_id", "itemId", "canonical_item_id", "canonicalItemId", "stableItemId", "id"]:
		var parsed: Variant = _integer_field(record, key)
		if parsed >= 0:
			return parsed
	return -1

func _integer_field(record: Dictionary, key: String) -> int:
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
	var parsed: Variant = int(value)
	return parsed if parsed >= 0 and float(parsed) == float(value) else -1
