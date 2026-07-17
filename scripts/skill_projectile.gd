class_name SkillProjectile
extends Node2D

const VISUAL_PATHS := {
	"wizard.fireball": "res://assets/art/characters/wizard/effects/arcane_projectile.png",
	"wizard.great_fireball": "res://assets/art/characters/wizard/effects/great_fireball.png",
	"taoist.soul_fire_talisman": "res://assets/art/characters/taoist/effects/soul_fire_talisman.png",
}

var direction := Vector2.RIGHT
var speed := 520.0
var remaining_range := 360.0
var damage := 1
var effect := "damage"
var effect_strength := 0
var effect_duration := 0.0
var projectile_color := Color(0.35, 0.7, 1.0)
var hit_radius := 24.0
var skill_id := ""
var _sprite: Sprite2D


func setup(start: Vector2, cast_direction: Vector2, value: int, travel_range: float, color: Color, status_effect := "damage", status_strength := 0, status_duration := 0.0, source_skill_id := "") -> void:
	global_position = start
	direction = cast_direction.normalized() if cast_direction.length() > 0.0 else Vector2.RIGHT
	damage = maxi(0, value)
	remaining_range = maxf(40.0, travel_range)
	projectile_color = color
	effect = status_effect
	effect_strength = status_strength
	effect_duration = status_duration
	skill_id = ProfessionRules.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	if skill_id.is_empty() and PlayerState != null:
		if PlayerState.profession == "法师":
			skill_id = "wizard.fireball"
		elif PlayerState.profession == "道士":
			skill_id = "taoist.soul_fire_talisman"


func _ready() -> void:
	add_to_group("zone_content")
	_install_visual()
	queue_redraw()


func _install_visual() -> void:
	var texture := CasterSkillVisualRegistry.texture(skill_id)
	if texture == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	var maximum_dimension := maxf(float(texture.get_width()), float(texture.get_height()))
	_sprite.scale = Vector2.ONE * 34.0 / maxf(1.0, maximum_dimension)
	add_child(_sprite)


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
	if not skill_id.is_empty():
		return
	draw_line(-direction * 30.0, Vector2.ZERO, Color(projectile_color, 0.25), 10.0)
	if _sprite == null:
		draw_circle(Vector2.ZERO, 9.0, projectile_color)
	draw_circle(Vector2.ZERO, 14.0, Color(projectile_color, 0.22), false, 4.0)
