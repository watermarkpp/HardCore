extends Node2D
## Pure Main artwork. No collection/group/physics/profile/save authority.
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const LootVisualEffectScript := preload("res://scripts/loot_visual_effect.gd")
const ItemNameStyleScript := preload("res://scripts/ui_item_name_style.gd")
var item_name: String
var item_record: Dictionary
var gold_amount: int
var icon_sprite: Sprite2D
var name_label: Label
var name_plate_size := Vector2(96,24)
var name_label_display_offset := Vector2.ZERO
var filtered := false
var _visual_descriptor: Dictionary
var loot_visual_effect: LootVisualEffect
var _configured := false
var _source_screen_position := Vector2.ZERO

static func visual_facts(record: Dictionary) -> Dictionary:
	return {"item_id":LootVisualEffectScript.exact_item_id(record),"tier":LootVisualEffectScript.tier_for_record(record),"golden_beam":LootVisualEffectScript.has_golden_beam_for_record(record),"affix_highlighted":LootVisualEffectScript.affix_is_valid(record)}

func configure_main(label_text: String, record: Dictionary, amount: int, screen_position: Vector2, descriptor: Dictionary, facts: Dictionary, is_filtered: bool) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _configured or is_inside_tree() or facts!=visual_facts(record): return false
	item_name=label_text;item_record=record.duplicate(true);gold_amount=amount
	_source_screen_position=screen_position;_visual_descriptor=descriptor.duplicate(true);filtered=is_filtered
	_configured=true
	set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
	return true

func apply_source_filter(value: bool) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not _configured or not is_inside_tree() or not is_instance_valid(name_label): return false
	filtered=value;name_label.visible=not filtered
	return true

func _ready() -> void:
	assert(_configured and OS.get_thread_caller_id()==OS.get_main_thread_id())
	# Map ground is -20, ground decoration -5..-3, actors and skills >= 0.
	# This absolute plane keeps icons/beam/fallback draw below every actor even
	# when the pickup footpoint sorts after the player in GameRoot's Y-sort.
	z_as_relative = false
	z_index = -2
	global_position=_source_screen_position
	var descriptor: Dictionary = _visual_descriptor
	_configure_instance_visual()
	var affix_highlighted: bool = (
		loot_visual_effect != null and loot_visual_effect.affix_highlighted
	)
	var icon_path := str(descriptor.get("path", ""))
	var icon_texture := UIItemTextureCacheScript.texture_at_path(icon_path)
	if icon_texture != null:
		icon_sprite = Sprite2D.new()
		icon_sprite.name = "ClientGroundIcon"
		icon_sprite.texture = icon_texture
		var target_size: Vector2 = descriptor.get("display_size", Vector2.ZERO)
		if icon_sprite.texture != null and target_size.x > 0.0 and target_size.y > 0.0:
			var native_size := icon_sprite.texture.get_size()
			icon_sprite.scale = Vector2.ONE * minf(target_size.x / native_size.x, target_size.y / native_size.y)
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
	# Measure text once so even a long name is centered on its own icon.
	# Neighboring names may overlap; they never move this label.
	name_plate_size = Vector2(maxf(48.0, label.get_minimum_size().x) + 8.0, 24.0)
	label.size = name_plate_size
	label.position = name_label_home_position()
	# Names remain readable above world actors; the item artwork stays at -2.
	name_label.z_as_relative = false
	name_label.z_index = 1
	if icon_sprite == null: queue_redraw()
	name_label.visible=not filtered

func name_label_home_position() -> Vector2:
	return Vector2(-name_plate_size.x * 0.5, -36.0)


## Name placement keeps a fixed home above this item's icon. The setter also
## lets an explicit placement pass clear an obsolete displacement.
func set_name_label_display_offset(offset: Vector2) -> void:
	name_label_display_offset = offset
	if is_instance_valid(name_label):
		name_label.position = name_label_home_position() + offset

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

func manager_visual_tick(_delta_seconds: float) -> void:
	if is_instance_valid(icon_sprite) and not icon_sprite.position.is_equal_approx(Vector2(0.0, -5.0)):
		icon_sprite.position = Vector2(0.0, -5.0)

func _draw() -> void:
	if icon_sprite != null:
		return
	var color: Color = _visual_descriptor.get("fallback_draw_color", Color(0.95, 0.67, 0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -11), Vector2(10, 0), Vector2(0, 11), Vector2(-10, 0)]), color)
	draw_polyline(PackedVector2Array([Vector2(0, -11), Vector2(10, 0), Vector2(0, 11), Vector2(-10, 0), Vector2(0, -11)]), Color(1.0, 0.93, 0.55), 2.0)
