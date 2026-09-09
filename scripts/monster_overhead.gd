class_name MonsterOverhead
extends Node2D


const LAYOUT_CONTRACT := "monster.overhead_layout.v3"
const MonsterDisplayFormatterScript := preload("res://scripts/monster_display_formatter.gd")
const NAME_LABEL_SIZE := Vector2(140, 24)
const NAME_LABEL_HEALTH_BAR_GAP := 4.0
const HEALTH_BAR_HEIGHT := 5.0
const RANK_MARKER_CONTRACT := "monster.overhead.rank_marker.v1"
const RANK_BOSS := "boss"
const RANK_ELITE := "elite"
const RANK_ORDINARY := "ordinary"

var name_label: Label
var rank_marker: Sprite2D
var bar_width := 46.0
var current_hp := 1
var max_hp := 1
var _setup_boss := false
var _rank := RANK_ORDINARY
var _rank_marker_texture_path := ""


func setup(display_name: String, boss: bool, hp: int, hp_max: int) -> void:
	# Keep this four-argument entry point stable for EnemyActor and older scene
	# fixtures.  Classification/rank is resolved by exact ID/context after the
	# node enters the actor tree; the caller's boss bit is only a trusted spawn
	# signal and never changes the actor identity.
	_setup_boss = boss
	bar_width = 80.0 if boss else 46.0
	current_hp = maxi(0, hp)
	max_hp = maxi(1, hp_max)
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.position = Vector2(-NAME_LABEL_SIZE.x * 0.5, -NAME_LABEL_SIZE.y - NAME_LABEL_HEALTH_BAR_GAP)
	name_label.size = NAME_LABEL_SIZE
	name_label.custom_minimum_size = NAME_LABEL_SIZE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override("font_color", Color(1.0, 0.60, 0.34) if boss else Color(0.82, 0.78, 0.66))
	add_child(name_label)
	set_meta("monster_overhead_layout_contract", LAYOUT_CONTRACT)
	queue_redraw()


func _ready() -> void:
	_refresh_rank_visuals()


func _refresh_rank_visuals() -> void:
	var actor := get_parent()
	var rank_context := MonsterDisplayFormatterScript.rank_for_actor(actor, _setup_boss)
	_rank = str(rank_context.get("rank", RANK_ORDINARY))
	_rank_marker_texture_path = str(rank_context.get("marker_texture", ""))
	if name_label != null:
		var resolved_name := MonsterDisplayFormatterScript.display_name_for_actor(actor)
		if resolved_name.is_empty():
			resolved_name = MonsterDisplayFormatterScript.display_name(name_label.text)
		if not resolved_name.is_empty():
			name_label.text = resolved_name
		name_label.add_theme_color_override("font_color", _rank_name_color())
	if rank_marker != null and is_instance_valid(rank_marker):
		rank_marker.queue_free()
	rank_marker = null
	if _rank == RANK_ORDINARY or _rank_marker_texture_path.is_empty():
		set_meta("monster_overhead_rank", _rank)
		set_meta("monster_overhead_rank_marker_texture", "")
		set_meta("monster_overhead_rank_contract", RANK_MARKER_CONTRACT)
		return
	if not ResourceLoader.exists(_rank_marker_texture_path):
		# Keep the rank contract visible to diagnostics while failing closed on a
		# missing optional texture.  Do not substitute a different marker.
		set_meta("monster_overhead_rank", _rank)
		set_meta("monster_overhead_rank_marker_texture", "")
		set_meta("monster_overhead_rank_contract", RANK_MARKER_CONTRACT)
		return
	rank_marker = Sprite2D.new()
	rank_marker.name = "RankMarker"
	rank_marker.texture = load(_rank_marker_texture_path)
	rank_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rank_marker.position = Vector2(-bar_width * 0.5 - 12.0, HEALTH_BAR_HEIGHT * 0.5)
	rank_marker.z_as_relative = true
	rank_marker.z_index = 1
	rank_marker.show_behind_parent = false
	add_child(rank_marker)
	set_meta("monster_overhead_rank", _rank)
	set_meta("monster_overhead_rank_marker_texture", _rank_marker_texture_path)
	set_meta("monster_overhead_rank_contract", RANK_MARKER_CONTRACT)


func _rank_name_color() -> Color:
	match _rank:
		RANK_BOSS:
			return Color("f1c45a")
		RANK_ELITE:
			return Color("e8edf2")
		_:
			return Color(0.82, 0.78, 0.66)


func marker_rank() -> String:
	return _rank


func marker_texture_path() -> String:
	return _rank_marker_texture_path


func set_anchor_y(anchor_y: float) -> void:
	position = Vector2(0.0, anchor_y)


func set_health(hp: int, hp_max: int) -> void:
	current_hp = maxi(0, hp)
	max_hp = maxi(1, hp_max)
	queue_redraw()


func bar_local_rect() -> Rect2:
	return Rect2(-bar_width * 0.5, 0.0, bar_width, HEALTH_BAR_HEIGHT)


func bar_global_top_y() -> float:
	return to_global(Vector2.ZERO).y


func name_global_bottom_y() -> float:
	return name_label.get_global_rect().end.y if name_label != null else global_position.y


func _draw() -> void:
	var rect := bar_local_rect()
	draw_rect(rect, Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * float(current_hp) / float(max_hp), rect.size.y)), Color(0.85, 0.12, 0.08))
