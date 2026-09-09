class_name MonsterDisplayFormatter
extends RefCounted

## Presentation-only projection for monster labels and rank markers.
##
## The catalog remains the identity authority.  This helper is deliberately
## read-only and only runs when an overhead/target label is built or updated;
## it never mutates the actor's canonical name, ID, classification, or combat
## state.
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const RANK_BOSS := "boss"
const RANK_ELITE := "elite"
const RANK_ORDINARY := "ordinary"
const BOSS_SPAWN_CLASSIFICATIONS := ["boss", "boss_spawn"]
const ELITE_SPAWN_CLASSIFICATIONS := ["elite", "elite_spawn"]

static var _catalog_loaded := false
static var _catalog_by_id: Dictionary = {}


static func display_name(raw_name: String, monster_id := -1) -> String:
	_ensure_catalog()
	# A display suffix is removable only when this exact stable ID owns the
	# canonical name and explicitly declares the suffix as variant_code.  A
	# name-only lookup would silently rename unknown actors that happen to share
	# a legacy name, so unknown/mismatched IDs remain byte-for-byte unchanged.
	if monster_id < 0 or not _catalog_by_id.has(monster_id):
		return raw_name
	var entry: Dictionary = _catalog_by_id[monster_id]
	var canonical_name := str(entry.get("canonical_name", ""))
	var variant_code := str(entry.get("variant_code", ""))
	if (
		canonical_name.is_empty()
		or variant_code.is_empty()
		or not canonical_name.ends_with(variant_code)
		or raw_name != canonical_name
	):
		return raw_name
	var base_name := canonical_name.left(canonical_name.length() - variant_code.length())
	if not base_name.is_empty():
		return base_name
	return raw_name


static func display_name_for_actor(actor: Node) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	var actor_id := _actor_monster_id(actor)
	var raw_name := str(actor.get("display_name")) if _has_property(actor, "display_name") else ""
	if raw_name.is_empty():
		var data_value: Variant = actor.get("monster_data") if _has_property(actor, "monster_data") else {}
		if data_value is Dictionary:
			raw_name = str((data_value as Dictionary).get("canonical_name", ""))
	return display_name(raw_name, actor_id)


static func rank_for_actor(actor: Node, setup_boss := false) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return rank_for_context(-1, "", "", setup_boss)
	var actor_id := _actor_monster_id(actor)
	var classification := ""
	var data_value: Variant = actor.get("monster_data") if _has_property(actor, "monster_data") else {}
	if data_value is Dictionary:
		classification = str((data_value as Dictionary).get("classification", ""))
	var spawn_classification := ""
	var context_value: Variant = actor.get_meta("spawn_context", {})
	if context_value is Dictionary:
		spawn_classification = str((context_value as Dictionary).get("spawn_classification", ""))
	if spawn_classification.is_empty() and actor.has_meta("spawn_classification"):
		spawn_classification = str(actor.get_meta("spawn_classification"))
	var explicit_boss := setup_boss
	if actor.has_meta("spawn_is_boss"):
		explicit_boss = explicit_boss or bool(actor.get_meta("spawn_is_boss"))
	return rank_for_context(
		actor_id,
		classification,
		spawn_classification,
		explicit_boss,
	)


static func rank_for_context(
	monster_id := -1,
	classification_hint := "",
	spawn_classification_hint := "",
	explicit_boss := false,
) -> Dictionary:
	_ensure_catalog()
	var exact_classification := ""
	var placement_kind := ""
	if monster_id >= 0 and _catalog_by_id.has(monster_id):
		var entry: Dictionary = _catalog_by_id[monster_id]
		exact_classification = str(entry.get("classification", ""))
		var placement_value: Variant = entry.get("editor_placement", {})
		if placement_value is Dictionary:
			placement_kind = str((placement_value as Dictionary).get("placement_kind", ""))
	var classification := exact_classification if not exact_classification.is_empty() else str(classification_hint)
	var spawn_classification := str(spawn_classification_hint)
	var is_boss := (
		explicit_boss
		or classification == RANK_BOSS
		or BOSS_SPAWN_CLASSIFICATIONS.has(spawn_classification)
		or placement_kind == "boss_spawn"
	)
	if is_boss:
		return {
			"rank": RANK_BOSS,
			"marker_texture": "res://assets/ui/monster_markers/boss_horned_gold_skull.svg",
			"reason": "canonical_or_trusted_spawn_boss",
		}
	var is_elite := (
		classification == RANK_ELITE
		or ELITE_SPAWN_CLASSIFICATIONS.has(spawn_classification)
	)
	if is_elite:
		return {
			"rank": RANK_ELITE,
			"marker_texture": "res://assets/ui/monster_markers/elite_skull.svg",
			"reason": "canonical_or_trusted_spawn_elite",
		}
	return {
		"rank": RANK_ORDINARY,
		"marker_texture": "",
		"reason": "canonical_or_trusted_spawn_ordinary",
	}


static func catalog_entry(monster_id: int) -> Dictionary:
	_ensure_catalog()
	var entry: Variant = _catalog_by_id.get(monster_id, {})
	return entry.duplicate(true) if entry is Dictionary else {}


static func reset_cache_for_test() -> void:
	_catalog_loaded = false
	_catalog_by_id.clear()


static func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var raw_entries: Variant = (parsed as Dictionary).get("entries_by_id", {})
	if not raw_entries is Dictionary:
		return
	for raw_id: Variant in (raw_entries as Dictionary).keys():
		var raw_entry: Variant = (raw_entries as Dictionary).get(raw_id)
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = (raw_entry as Dictionary).duplicate(true)
		var monster_id := int(raw_id)
		if monster_id < 0:
			monster_id = int(entry.get("monster_id", -1))
		if monster_id < 0:
			continue
		_catalog_by_id[monster_id] = entry
		var canonical_name := str(entry.get("canonical_name", ""))
		var variant_code := str(entry.get("variant_code", ""))
		# Keep variant metadata in the exact-ID table.  Do not build a secondary
		# name index: names are presentation text and are not identity authority.
		if canonical_name.is_empty() or variant_code.is_empty() or not canonical_name.ends_with(variant_code):
			continue


static func _actor_monster_id(actor: Node) -> int:
	if not _has_property(actor, "monster_id"):
		return -1
	var raw_id: Variant = actor.get("monster_id")
	if raw_id is String and not (raw_id as String).is_valid_int():
		return -1
	var parsed_id := int(raw_id)
	return parsed_id if parsed_id >= 0 else -1


static func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false
