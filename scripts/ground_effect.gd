class_name GroundSkillEffect
extends Node2D

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")

const VISUAL_PATHS := {
	"wizard.fire_wall": "res://assets/art/characters/wizard/effects/fire_wall.png",
}

var damage := 1
var radius := 72.0
var duration := 4.0
var tick_interval := 0.8
var effect_color := Color(1.0, 0.25, 0.05)
var skill_id := ""
var source_actor: Node2D
var runtime_tick_adapter := Callable()
var visual_rejection_reason := ""
var _tick_timer := 0.0
var _sprite: Sprite2D


func setup(position_value: Vector2, damage_value: int, radius_value: float, duration_value: float, color: Color, source_skill_id := "", tick_interval_value := 0.8) -> void:
	global_position = position_value
	damage = maxi(0, damage_value)
	radius = maxf(20.0, radius_value)
	duration = maxf(0.1, duration_value)
	tick_interval = maxf(0.05, tick_interval_value)
	effect_color = color
	skill_id = ProfessionRules.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	if skill_id.is_empty() and PlayerState != null:
		skill_id = "wizard.fire_wall" if PlayerState.profession == "法师" else ""


func _ready() -> void:
	add_to_group("zone_content")
	_install_visual()
	queue_redraw()


func configure_runtime_resolution(caster: Node2D, tick_adapter: Callable) -> void:
	source_actor = caster
	runtime_tick_adapter = tick_adapter


func configure_runtime_source(caster: Node2D) -> void:
	source_actor = caster


func _install_visual() -> void:
	if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
		visual_rejection_reason = CasterSkillVisualRegistry.runtime_readiness_reason(skill_id)
		return
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	if str(profile.get("role", "")) != CasterSkillVisualRegistry.ROLE_GROUND_EFFECT:
		visual_rejection_reason = "non_ground_visual:%s" % str(
			profile.get("role", "missing")
		)
		return
	var candidate := AnimationPlayerScript.new()
	if not candidate.configure(skill_id, Vector2.DOWN, 0.0):
		visual_rejection_reason = "ground_animation_failed"
		candidate.queue_free()
		return
	_sprite = candidate
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if node is EnemyActor and not node.is_queued_for_deletion() and global_position.distance_to(node.global_position) <= radius:
				if runtime_tick_adapter.is_valid():
					runtime_tick_adapter.call(node, damage)
				else:
					node.take_damage(damage, source_actor)
	if duration <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if _sprite != null or not skill_id.is_empty():
		return
	var pulse := 0.78 + sin(Time.get_ticks_msec() * 0.01) * 0.12
	draw_circle(Vector2.ZERO, radius * pulse, Color(effect_color, 0.16))
	draw_circle(Vector2.ZERO, radius * pulse, Color(effect_color, 0.70), false, 4.0)
