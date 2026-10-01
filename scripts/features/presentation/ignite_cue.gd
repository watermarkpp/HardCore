extends Node2D

var actor_ref: RefCounted
var effect_handle := ""
var strength := 0
func _ready() -> void:
	position = Vector2(0,-34)
	z_index = 5
	queue_redraw()
func _process(_delta: float) -> void:
	if actor_ref == null or actor_ref.resolve(false) == null: queue_free()
func _draw() -> void:
	# Built-in procedural cue: no texture decode, filesystem access, timer or
	# damage callback exists in this presentation node.
	draw_circle(Vector2.ZERO,8.0,Color(1.0,0.27,0.04,0.35))
	draw_colored_polygon(PackedVector2Array([Vector2(-6,5),Vector2(-3,-8),Vector2(0,-3),Vector2(4,-12),Vector2(7,5)]),Color(1.0,0.48,0.08,0.85))
	draw_circle(Vector2(0,2),3.0,Color(1.0,0.92,0.45,0.9))
