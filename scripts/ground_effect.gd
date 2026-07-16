class_name GroundSkillEffect
extends Node2D

const VISUAL_PATHS := {
	"wizard.fire_wall": "res://assets/art/characters/wizard/effects/fire_wall.png",
	"wizard.exploding_flame": "res://assets/art/characters/wizard/effects/area_burst.png",
	"wizard.ice_storm": "res://assets/art/characters/wizard/effects/ice_storm.png",
	"taoist.entrapment": "res://assets/art/characters/taoist/effects/binding_circle.png",
}

var damage := 1
var radius := 72.0
var duration := 4.0
var tick_interval := 0.8
var effect_color := Color(1.0, 0.25, 0.05)
var skill_id := ""
var _tick_timer := 0.0
var _sprite: Sprite2D


func setup(position_value: Vector2, damage_value: int, radius_value: float, duration_value: float, color: Color, source_skill_id := "") -> void:
	global_position = position_value
	damage = maxi(1, damage_value)
	radius = maxf(20.0, radius_value)
	duration = maxf(0.1, duration_value)
	effect_color = color
	skill_id = ProfessionRules.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	if skill_id.is_empty() and PlayerState != null:
		skill_id = "wizard.fire_wall" if PlayerState.profession == "法师" else ""


func _ready() -> void:
	add_to_group("zone_content")
	_install_visual()
	queue_redraw()


func _install_visual() -> void:
	var path := str(VISUAL_PATHS.get(skill_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	if texture == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	var maximum_dimension := maxf(float(texture.get_width()), float(texture.get_height()))
	_sprite.scale = Vector2.ONE * radius * 1.6 / maxf(1.0, maximum_dimension)
	_sprite.modulate = Color(1, 1, 1, 0.72)
	add_child(_sprite)


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
