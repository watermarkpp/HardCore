class_name PlayerHealthBar
extends Node2D

const BAR_SIZE := Vector2(50.0, 5.0)
const BACKGROUND := Color(0.12, 0.05, 0.04, 0.92)
const HEALTH := Color(0.75, 0.12, 0.08, 1.0)

var current_hp := 1
var max_hp := 1


func setup(current_value: int, maximum_value: int) -> void:
	set_health(current_value, maximum_value)


func set_health(current_value: int, maximum_value: int) -> void:
	max_hp = maxi(1, maximum_value)
	current_hp = clampi(current_value, 0, max_hp)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-BAR_SIZE.x * 0.5, 0.0, BAR_SIZE.x, BAR_SIZE.y)
	draw_rect(rect, BACKGROUND)
	var ratio := float(current_hp) / float(max_hp)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), HEALTH)
