extends RefCounted

## Shared fixture helper for the R6.1-review real-panel matrix (executor-owned,
## NOT the locked assertion script). Builds the expected per-ID set from the
## real runtime catalog + rarity mapping and formats evidence rows.

const Style := preload("res://scripts/ui_item_name_style.gd")
const Formatter := preload("res://scripts/item_detail_presenter.gd")

static func ensure_data() -> bool:
	return GameData.ensure_loaded() and Style.ensure_loaded()

static func expected_items() -> Array[Dictionary]:
	# One entry per canonical stable id in the real runtime catalog.
	var out: Array[Dictionary] = []
	var seen := {}
	for value: Variant in GameData.item_catalog:
		if not value is Dictionary or (value as Dictionary).is_empty():
			continue
		var item: Dictionary = value
		var canonical := int(Style.canonical_id(item))
		if canonical <= 0 or seen.has(canonical):
			continue
		seen[canonical] = true
		var described: Dictionary = Style.describe(item, {})
		out.append({
			"item_id": canonical,
			"name": Style.display_name(item),
			"kind": str(item.get("kind", "")),
			"group": str(described.get("group", "default")),
			"color": described.get("color", Color(0.902, 0.867, 0.796)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.item_id) < int(b.item_id))
	return out

static func seed_record(name_value: String) -> Dictionary:
	# Authoritative receive path; the created instance (and any legal affixes)
	# come from PlayerState/_make_item_instance, never invented here.
	var result: Dictionary = PlayerState.add_item(name_value, 1)
	if not bool(result.get("success", false)):
		return {}
	var record: Dictionary = PlayerState.inventory.back() if not PlayerState.inventory.is_empty() else {}
	return record.duplicate(true)

static func instance_affixes(record: Dictionary) -> Array:
	# W7 affixes are observable as the instance's modifiers array (the rules
	# test asserts (affixed.item_instance.modifiers).size() == 1).
	var modifiers: Variant = record.get("modifiers", [])
	return modifiers if modifiers is Array else []

static func affixed_drop_instance(identity_record: Dictionary, key_prefix: String, max_tries := 24) -> Dictionary:
	# Legal random instances: the authoritative drop-rules factory rolls the
	# 1/20 affix from a deterministic stable drop key; affixed instances are
	# detected with the rules contract's own predicate.
	var rules := load("res://scripts/item_drop_instance_rules.gd")
	var catalog: Dictionary = identity_record.get("output_record", {})
	for i: int in range(max_tries):
		var created: Dictionary = PlayerState.create_drop_item_instance(identity_record, "%s:%d" % [key_prefix, i])
		var instance: Dictionary = created.get("item_instance", {})
		if instance.is_empty():
			continue
		if bool(rules.is_affixed_instance(instance, catalog)):
			created["review_drop_key"] = "%s:%d" % [key_prefix, i]
			return created
	return {}

static func base_row(zone: String, expected: Dictionary, record: Dictionary) -> Dictionary:
	return {
		"zone": zone,
		"item_id": expected.item_id,
		"name": str(expected.name),
		"instance_id": str(record.get("instance_id", "")),
		"affixes": instance_affixes(record),
		"expected_group": str(expected.group),
		"expected_color": str(expected.color),
	}

static func rects_of(owner_control: Control, nodes: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node: Variant in nodes:
		if node is Control and (node as Control).is_visible_in_tree():
			out.append(HelperRects.rect_in(owner_control, node))
	return out

class HelperRects:
	static func rect_in(owner_control: Control, control: Control) -> Rect2:
		var owner_transform := owner_control.get_global_transform_with_canvas()
		if absf(owner_transform.determinant()) < 0.000001:
			return Rect2()
		var transform := owner_transform.affine_inverse() * control.get_global_transform_with_canvas()
		var result := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
		for point: Vector2 in [Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]:
			result = result.expand(transform * point)
		return result
