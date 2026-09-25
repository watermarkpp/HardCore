class_name LootPickup
extends Node2D

signal collected(item_name: String, pickup: LootPickup)
signal gold_collected(amount: int, pickup: LootPickup)
signal collection_rejected(item_name: String, message: String)

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const LootVisualEffectScript := preload("res://scripts/loot_visual_effect.gd")
const ItemNameStyleScript := preload("res://scripts/ui_item_name_style.gd")
const COLLECTION_RADIUS_GU := 0.75
const OVERWEIGHT_RETRY_COOLDOWN_SECONDS := 5.0

var item_name := "金币"
var item_id := -1
var item_record: Dictionary = {}
var gold_amount := 0
var target: PlayerCharacter
var icon_sprite: Sprite2D
var name_label: Label
## Measured plate size of the name label (text width + padding). The layout
## authority uses it for honest overlap tests; the label rect is resized to
## match so the visible text and the tested rect are the same box.
var name_plate_size := Vector2(96, 24)
## Current display offset from the label home position (set only by the
## event-driven name layout; zero keeps the label at its home).
var name_label_display_offset := Vector2.ZERO
var _filter_threshold := 0
var filtered := false
var _overweight_retry_remaining := 0.0
var _collection_pending := false
var _collection_authority_check_count := 0
var _collection_manager: Node
var _visual_descriptor: Dictionary = {}
var loot_visual_effect: LootVisualEffect
static var _descriptor_cache: Dictionary = {}
static var _descriptor_build_count := 0


static func ground_visual_descriptor(name: String) -> Dictionary:
	if _descriptor_cache.has(name):
		return _descriptor_cache[name].duplicate(true)
	var record := GameData.get_item_record(name)
	return _ground_visual_descriptor_from_catalog_record(name, record, name)


## Resolve the presentation record carried by LootRuntime's stable identity
## record.  The source ID and output ID are intentionally separate: female
## equipment drops retain the source identity while drawing the explicit male
## output record.  No fuzzy name-to-ID conversion occurs here.
static func ground_visual_descriptor_for_record(identity_record: Dictionary) -> Dictionary:
	var output_record: Dictionary = {}
	var nested_output: Variant = identity_record.get("output_record", {})
	if nested_output is Dictionary:
		output_record = (nested_output as Dictionary).duplicate(true)
	var display_name := str(identity_record.get(
		"item_name",
		identity_record.get("name", identity_record.get("canonical_name", "")),
	))
	if output_record.is_empty() and not display_name.is_empty():
		return ground_visual_descriptor(display_name)
	if output_record.is_empty():
		return {}
	var output_item_id := int(identity_record.get("output_item_id", -1))
	var cache_key := (
		"item:%d" % output_item_id
		if output_item_id >= 0
		else "name:%s" % str(output_record.get("name", display_name))
	)
	return _ground_visual_descriptor_from_catalog_record(
		cache_key,
		output_record,
		display_name,
	)


static func _ground_visual_descriptor_from_catalog_record(
	cache_key: String,
	record: Dictionary,
	fallback_name: String,
) -> Dictionary:
	if _descriptor_cache.has(cache_key):
		return _descriptor_cache[cache_key].duplicate(true)
	var art: Variant = record.get("art", {})
	var ground: Variant = art.get("groundIcon", {}) if art is Dictionary else {}
	var path := str(ground.get("path", "")) if ground is Dictionary else str(ground)
	var kind := str(record.get("kind", "material"))
	if path.is_empty():
		var fallback_key := str({"skill_book": "book", "consumable": "potion", "scroll": "scroll", "quest_item": "quest", "currency": "material", "material": "material"}.get(kind, "material"))
		path = str(GameData.service_item_catalog.get("runtimeFallbackArt", {}).get(fallback_key, {}).get("ground", ""))
	var draw_color: Color = {"equipment": Color(0.35, 0.65, 0.95), "skill_book": Color(0.60, 0.38, 0.90), "consumable": Color(0.25, 0.75, 0.35), "quest_item": Color(0.90, 0.28, 0.12)}.get(kind, Color(0.95, 0.67, 0.12))
	var label_color: Color = {"equipment": Color(0.55, 0.82, 1.0), "skill_book": Color(0.72, 0.55, 1.0), "currency": Color(1.0, 0.82, 0.28), "consumable": Color(0.45, 0.92, 0.52), "quest_item": Color(1.0, 0.48, 0.25)}.get(kind, Color(0.90, 0.82, 0.66))
	var descriptor := {"path": path, "kind": kind, "label_color": label_color, "fallback_draw_color": draw_color}
	_descriptor_cache[cache_key] = descriptor
	_descriptor_build_count += 1
	return descriptor.duplicate(true)


static func prewarm_item_names(names: Array) -> int:
	LootVisualEffectScript.prewarm_authority()
	ItemNameStyleScript.ensure_loaded()
	var paths: Array[String] = []
	for raw_name: Variant in names:
		var path := str(ground_visual_descriptor(str(raw_name)).get("path", ""))
		if not path.is_empty():
			paths.append(path)
	return UIItemTextureCacheScript.request_threaded_paths(paths)


static func prewarm_item_records(records: Array) -> int:
	var paths: Array[String] = []
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			continue
		var path := str(ground_visual_descriptor_for_record(raw_record).get("path", ""))
		if not path.is_empty():
			paths.append(path)
	return UIItemTextureCacheScript.request_threaded_paths(paths)


static func clear_descriptor_cache_for_test() -> void:
	_descriptor_cache.clear()
	_descriptor_build_count = 0


func setup(label_text: String, player_target: PlayerCharacter) -> void:
	item_name = label_text
	item_id = -1
	item_record = {}
	gold_amount = 0
	target = player_target
	_visual_descriptor = ground_visual_descriptor(item_name)
	var catalog_record := GameData.get_item_record(label_text)
	if (
		not catalog_record.is_empty()
		and str(catalog_record.get("name", "")) == label_text
	):
		item_id = _catalog_item_id(catalog_record)
		if item_id >= 0:
			item_record = {
				"item_id": item_id,
				"canonical_item_id": item_id,
				"canonical_name": label_text,
				"item_name": label_text,
				"name": label_text,
				"output_item_id": item_id,
				"output_record": catalog_record.duplicate(true),
				"identity_status": "catalog_compatibility",
			}


## New stable identity path.  GameRoot can pass LootRuntime's item_records
## entry while retaining the old collected(item_name, pickup) signal.
func setup_item_record(identity_record: Dictionary, player_target: PlayerCharacter) -> void:
	item_record = identity_record.duplicate(true)
	item_id = int(item_record.get(
		"item_id",
		item_record.get("canonical_item_id", -1),
	))
	item_name = str(item_record.get(
		"item_name",
		item_record.get("name", item_record.get("canonical_name", "")),
	))
	gold_amount = 0
	target = player_target
	_visual_descriptor = ground_visual_descriptor_for_record(item_record)


func setup_gold(amount: int, player_target: PlayerCharacter) -> void:
	item_name = "金币"
	item_id = -1
	item_record = {}
	gold_amount = maxi(1, amount)
	target = player_target
	_visual_descriptor = ground_visual_descriptor(item_name)


func _ready() -> void:
	# Map ground is -20, ground decoration -5..-3, actors and skills >= 0.
	# This absolute plane keeps icons/beam/fallback draw below every actor even
	# when the pickup footpoint sorts after the player in GameRoot's Y-sort.
	z_as_relative = false
	z_index = -2
	add_to_group("loot_pickups")
	if _visual_descriptor.is_empty():
		_visual_descriptor = ground_visual_descriptor(item_name)
	var descriptor: Dictionary = _visual_descriptor
	_configure_instance_visual()
	var affix_highlighted := (
		loot_visual_effect != null and loot_visual_effect.affix_highlighted
	)
	var icon_path := str(descriptor.get("path", ""))
	var icon_texture := UIItemTextureCacheScript.texture_at_path(icon_path)
	if icon_texture != null:
		icon_sprite = Sprite2D.new()
		icon_sprite.name = "ClientGroundIcon"
		icon_sprite.texture = icon_texture
		icon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_sprite.position = Vector2(0, -5)
		add_child(icon_sprite)
	var label := Label.new()
	label.text = "金币 %d" % gold_amount if gold_amount > 0 else ("★" if affix_highlighted else "") + item_name
	label.position = Vector2(-48, -36)
	label.size = Vector2(96, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var template_item_color: Color = descriptor.get("label_color", Color(0.90, 0.82, 0.66))
	var item_color: Color = (
		loot_visual_effect.get_meta("loot_visual_label_color", template_item_color)
		if loot_visual_effect != null else template_item_color
	)
	label.add_theme_color_override("font_color", item_color)
	ItemNameStyleScript.apply_label_style(label, ItemNameStyleScript.describe({"item_id": LootVisualEffectScript.exact_item_id(item_record)}) if gold_amount <= 0 else {}, item_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	name_label = label
	# Measure the real text plate once: the layout authority and the drawn
	# label must share the same rectangle, and long names must not silently
	# overflow the tested box.
	name_plate_size = Vector2(maxf(48.0, label.get_minimum_size().x) + 8.0, 24.0)
	label.size = name_plate_size
	label.position = name_label_home_position()
	# Names remain readable above world actors; the item artwork stays at -2.
	name_label.z_as_relative = false
	name_label.z_index = 1
	var catalog: Dictionary = item_record.get("output_record", {})
	if gold_amount <= 0 and str(catalog.get("kind", "")) == "equipment" and not affix_highlighted:
		_filter_threshold = LootPreferences.filter_threshold_for_item(LootVisualEffectScript.exact_item_id(item_record))
	LootPreferences.filter_changed.connect(_apply_filter)
	_apply_filter(LootPreferences.filter_level)
	if icon_sprite == null:
		RuntimeDiagnostics.increment_performance_counter(&"loot_fallback_redraw_requests")
		queue_redraw()


## 2026-09-20 user principle: the label's HOME is the single-drop presentation
## position — horizontally centered on the item, 36px above the footpoint.
func name_label_home_position() -> Vector2:
	return Vector2(-name_plate_size.x * 0.5, -36.0)


## Only the event-driven ground-name layout writes offsets. Zero keeps the
## label at its home position above its own icon.
func set_name_label_display_offset(offset: Vector2) -> void:
	name_label_display_offset = offset
	if is_instance_valid(name_label):
		name_label.position = name_label_home_position() + offset


## Local-space rect of this pickup's ground icon. The name layout treats
## OTHER pickups' icon rects as association obstacles: a name plate must
## never cover another item's icon.
func ground_icon_rect_local() -> Rect2:
	var icon_size := Vector2(24, 24)
	if is_instance_valid(icon_sprite) and icon_sprite.texture != null:
		var texture_size := icon_sprite.texture.get_size()
		if texture_size.x > 1.0 and texture_size.y > 1.0:
			icon_size = Vector2(minf(texture_size.x, 48.0), minf(texture_size.y, 48.0))
	return Rect2(Vector2(0, -5) - icon_size * 0.5, icon_size)


func _apply_filter(level: int) -> void:
	filtered = _filter_threshold > 0 and level >= _filter_threshold
	if is_instance_valid(name_label):
		name_label.visible = not filtered
	if not filtered:
		_overweight_retry_remaining = 0.0


func _configure_instance_visual() -> void:
	if item_record.is_empty():
		return
	if loot_visual_effect == null or not is_instance_valid(loot_visual_effect):
		loot_visual_effect = LootVisualEffectScript.new()
		loot_visual_effect.name = "LootVisualEffect"
		# The helper is the first child so its static beam is behind the client
		# icon.  LootPickup remains the only lifetime owner.
		add_child(loot_visual_effect)
		move_child(loot_visual_effect, 0)
	var template_item_color: Color = _visual_descriptor.get("label_color", Color(0.90, 0.82, 0.66))
	loot_visual_effect.configure(item_record, template_item_color)


func loot_visual_snapshot() -> Dictionary:
	if loot_visual_effect == null or not is_instance_valid(loot_visual_effect):
		return {
			"contract": LootVisualEffectScript.VISUAL_CONTRACT,
			"item_id": LootVisualEffectScript.exact_item_id(item_record),
			"tier": LootVisualEffectScript.tier_for_record(item_record),
			"golden_beam": false,
			"affix_highlight": LootVisualEffectScript.affix_is_valid(item_record),
		}
	return loot_visual_effect.visual_descriptor()


static func _catalog_item_id(record: Dictionary) -> int:
	for key: String in ["item_id", "itemId", "stableItemId", "id"]:
		if not record.has(key):
			continue
		var value: Variant = record.get(key, -1)
		if value is String and not (value as String).is_valid_int():
			continue
		var parsed := int(value)
		if parsed >= 0:
			return parsed
	return -1



func set_collection_manager(manager: Node) -> void:
	_collection_manager = manager


## Called only by LootPickupRuntimeManager.  The manager owns candidate
## selection; this object retains the old pending/confirm/reject authority and
## emits the same signals in the same stable candidate order.
func manager_evaluate_collection(in_range: bool, delta_seconds: float) -> bool:
	manager_advance_time(delta_seconds)
	if is_queued_for_deletion() or filtered:
		return false
	if not in_range:
		manager_reset_attempt_context()
		return false
	if (
		_collection_pending
		or _overweight_retry_remaining > 0.0
		or not is_instance_valid(target)
	):
		return false
	_collection_authority_check_count += 1
	RuntimeDiagnostics.increment_performance_counter(
		&"loot_collection_authority_checks"
	)
	_collection_pending = true
	if gold_amount > 0:
		# Gold does not enter inventory: no weight / capacity gate.
		gold_collected.emit(gold_amount, self)
	else:
		collected.emit(item_name, self)
	return true


func manager_advance_time(delta_seconds: float) -> void:
	_overweight_retry_remaining = maxf(
		0.0,
		_overweight_retry_remaining - maxf(0.0, delta_seconds),
	)


func manager_reset_attempt_context() -> void:
	if not _collection_pending:
		# Leaving the pickup radius starts a fresh attempt context.
		_overweight_retry_remaining = 0.0


func manager_visual_tick(_delta_seconds: float) -> void:
	if is_instance_valid(icon_sprite) and not icon_sprite.position.is_equal_approx(Vector2(0.0, -5.0)):
		icon_sprite.position = Vector2(0.0, -5.0)


func _arm_collection_retry_cooldown() -> void:
	_overweight_retry_remaining = OVERWEIGHT_RETRY_COOLDOWN_SECONDS


func retry_cooldown_remaining() -> float:
	return _overweight_retry_remaining


func collection_pending() -> bool:
	return _collection_pending


func collection_authority_check_count() -> int:
	return _collection_authority_check_count


func confirm_collect() -> void:
	if not _collection_pending:
		return
	_collection_pending = false
	queue_free()


func reject_collection(message := "超过负重，无法拾取。") -> void:
	if not _collection_pending:
		return
	_collection_pending = false
	_arm_collection_retry_cooldown()
	collection_rejected.emit(item_name, message)


static func target_is_within_collection_range_screen_px(
	pickup_screen_position_px: Vector2,
	target_screen_position_px: Vector2
) -> bool:
	var target_delta_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target_screen_position_px - pickup_screen_position_px
		)
	)
	return (
		target_delta_ground_gu.length_squared()
		< COLLECTION_RADIUS_GU * COLLECTION_RADIUS_GU
	)


func _draw() -> void:
	if icon_sprite != null:
		return
	var color: Color = _visual_descriptor.get("fallback_draw_color", Color(0.95, 0.67, 0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -11), Vector2(10, 0), Vector2(0, 11), Vector2(-10, 0)]), color)
	draw_polyline(PackedVector2Array([Vector2(0, -11), Vector2(10, 0), Vector2(0, 11), Vector2(-10, 0), Vector2(0, -11)]), Color(1.0, 0.93, 0.55), 2.0)
