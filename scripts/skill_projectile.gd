class_name SkillProjectile
extends Node2D

var direction := Vector2.RIGHT
var speed := 520.0
var remaining_range := 360.0
var damage := 1
var effect := "damage"
var effect_strength := 0
var effect_duration := 0.0
var projectile_color := Color(0.35, 0.7, 1.0)
var hit_radius := 24.0


func setup(start: Vector2, cast_direction: Vector2, value: int, travel_range: float, color: Color, status_effect := "damage", status_strength := 0, status_duration := 0.0) -> void:
	global_position = start
	direction = cast_direction.normalized() if cast_direction.length() > 0.0 else Vector2.RIGHT
	damage = maxi(0, value)
	remaining_range = maxf(40.0, travel_range)
	projectile_color = color
	effect = status_effect
	effect_strength = status_strength
	effect_duration = status_duration


func _ready() -> void:
	add_to_group("zone_content")
	queue_redraw()


func _physics_process(delta: float) -> void:
	var travel := minf(speed * delta, remaining_range)
	global_position += direction * travel
	remaining_range -= travel
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		if global_position.distance_to(node.global_position) > hit_radius:
			continue
		_apply_hit(node)
		queue_free()
		return
	if remaining_range <= 0.0:
		queue_free()


func _apply_hit(enemy: EnemyActor) -> void:
	if damage > 0:
		enemy.take_damage(damage)
	if not is_instance_valid(enemy):
		return
	match effect:
		"poison": enemy.apply_poison(maxi(1, effect_strength), maxf(1.0, effect_duration))
		"control": enemy.apply_control(maxf(0.5, effect_duration))
		"charm": enemy.apply_charm(maxf(1.0, effect_duration))


func _draw() -> void:
	draw_line(-direction * 30.0, Vector2.ZERO, Color(projectile_color, 0.25), 10.0)
	draw_circle(Vector2.ZERO, 9.0, projectile_color)
	draw_circle(Vector2.ZERO, 14.0, Color(projectile_color, 0.22), false, 4.0)
