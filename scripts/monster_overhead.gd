class_name MonsterOverhead
extends Node2D


const LAYOUT_CONTRACT := "monster.overhead_layout.v3"
const NAME_LABEL_SIZE := Vector2(140, 24)
const NAME_LABEL_HEALTH_BAR_GAP := 4.0
const HEALTH_BAR_HEIGHT := 5.0

var name_label: Label
var bar_width := 46.0
var current_hp := 1
var max_hp := 1


func setup(display_name: String, boss: bool, hp: int, hp_max: int) -> void:
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
	return name_label.get_global_rect().end.y


func _draw() -> void:
	var rect := bar_local_rect()
	draw_rect(rect, Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * float(current_hp) / float(max_hp), rect.size.y)), Color(0.85, 0.12, 0.08))
