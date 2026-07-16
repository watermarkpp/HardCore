class_name GroundSkillEffect
extends Node2D

var damage := 1
var radius := 72.0
var duration := 4.0
var tick_interval := 0.8
var effect_color := Color(1.0, 0.25, 0.05)
var _tick_timer := 0.0


func setup(position_value: Vector2, damage_value: int, radius_value: float, duration_value: float, color: Color) -> void:
	global_position = position_value
	damage = maxi(1, damage_value)
	radius = maxf(20.0, radius_value)
	duration = maxf(0.1, duration_value)
	effect_color = color


func _ready() -> void:
	add_to_group("zone_content")
	queue_redraw()


func _physics_process(delta: float) -> void:
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if node is EnemyActor and not node.is_queued_for_deletion() and global_position.distance_to(node.global_position) <= radius:
				node.take_damage(damage)
	if duration <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var pulse := 0.78 + sin(Time.get_ticks_msec() * 0.01) * 0.12
	draw_circle(Vector2.ZERO, radius * pulse, Color(effect_color, 0.16))
	draw_circle(Vector2.ZERO, radius * pulse, Color(effect_color, 0.70), false, 4.0)
