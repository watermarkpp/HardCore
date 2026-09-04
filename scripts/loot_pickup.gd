class_name LootPickup
extends Node2D

signal collected(item_name: String, pickup: LootPickup)
signal gold_collected(amount: int, pickup: LootPickup)
signal collection_rejected(item_name: String, message: String)

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const COLLECTION_RADIUS_GU := 0.75
const OVERWEIGHT_RETRY_COOLDOWN_SECONDS := 5.0

var item_name := "金币"
var gold_amount := 0
var target: PlayerCharacter
var _bob_time := 0.0
var icon_sprite: Sprite2D
var _overweight_retry_remaining := 0.0
var _collection_pending := false
var _collection_authority_check_count := 0
static var _descriptor_cache: Dictionary = {}
static var _descriptor_build_count := 0


static func ground_visual_descriptor(name: String) -> Dictionary:
	if _descriptor_cache.has(name):
		return _descriptor_cache[name].duplicate(true)
	var record := GameData.get_item_record(name)
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
	_descriptor_cache[name] = descriptor
	_descriptor_build_count += 1
	return descriptor.duplicate(true)


static func prewarm_item_names(names: Array) -> int:
	var paths: Array[String] = []
	for raw_name: Variant in names:
		var path := str(ground_visual_descriptor(str(raw_name)).get("path", ""))
		if not path.is_empty():
			paths.append(path)
	return UIItemTextureCacheScript.request_threaded_paths(paths)


static func clear_descriptor_cache_for_test() -> void:
	_descriptor_cache.clear()
	_descriptor_build_count = 0


func setup(label_text: String, player_target: PlayerCharacter) -> void:
	item_name = label_text
	gold_amount = 0
	target = player_target


func setup_gold(amount: int, player_target: PlayerCharacter) -> void:
	item_name = "金币"
	gold_amount = maxi(1, amount)
	target = player_target


func _ready() -> void:
	add_to_group("loot_pickups")
	var descriptor := ground_visual_descriptor(item_name)
	var icon_path := str(descriptor.get("path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_sprite = Sprite2D.new()
		icon_sprite.name = "ClientGroundIcon"
		icon_sprite.texture = UIItemTextureCacheScript.texture_at_path(icon_path)
		icon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_sprite.position = Vector2(0, -5)
		add_child(icon_sprite)
	var label := Label.new()
	label.text = "金币 %d" % gold_amount if gold_amount > 0 else item_name
	label.position = Vector2(-48, -36)
	label.size = Vector2(96, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var item_color: Color = descriptor.get("label_color", Color(0.90, 0.82, 0.66))
	label.add_theme_color_override("font_color", item_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	if icon_sprite == null:
		RuntimeDiagnostics.increment_performance_counter(&"loot_fallback_redraw_requests")
		queue_redraw()


func _process(delta: float) -> void:
	RuntimeDiagnostics.increment_performance_counter(&"loot_pickup_process_calls")
	_bob_time += delta
	_overweight_retry_remaining = maxf(0.0, _overweight_retry_remaining - delta)
	if icon_sprite != null:
		icon_sprite.position.y = -5.0 + sin(_bob_time * 3.0) * 2.0
		RuntimeDiagnostics.increment_performance_counter(&"loot_visual_updates")
	if icon_sprite == null:
		RuntimeDiagnostics.increment_performance_counter(&"loot_fallback_redraw_requests")
		queue_redraw()
	if not is_instance_valid(target):
		return
	if _collection_pending:
		return
	RuntimeDiagnostics.increment_performance_counter(&"loot_collection_global_checks")
	RuntimeDiagnostics.increment_performance_counter(&"loot_collection_spatial_queries")
	RuntimeDiagnostics.increment_performance_counter(&"loot_collection_candidates")
	var in_range := target_is_within_collection_range_screen_px(global_position, target.global_position)
	if not in_range:
		# Leaving the pickup radius is a new attempt context, so don't carry a
		# stale failure cooldown back when the player returns.
		_overweight_retry_remaining = 0.0
		return
	if _overweight_retry_remaining > 0.0:
		return
	_collection_authority_check_count += 1
	RuntimeDiagnostics.increment_performance_counter(&"loot_collection_authority_checks")
	if gold_amount > 0:
		# Gold does not enter inventory: no weight / capacity gate.
		_collection_pending = true
		gold_collected.emit(gold_amount, self)
		return
	_collection_pending = true
	collected.emit(item_name, self)


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
	var bob := sin(_bob_time * 3.0) * 3.0
	var color: Color = ground_visual_descriptor(item_name).get("fallback_draw_color", Color(0.95, 0.67, 0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -11 + bob), Vector2(10, bob), Vector2(0, 11 + bob), Vector2(-10, bob)]), color)
	draw_polyline(PackedVector2Array([Vector2(0, -11 + bob), Vector2(10, bob), Vector2(0, 11 + bob), Vector2(-10, bob), Vector2(0, -11 + bob)]), Color(1.0, 0.93, 0.55), 2.0)
