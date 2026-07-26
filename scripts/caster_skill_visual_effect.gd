class_name CasterSkillVisualEffect
extends Node2D

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")

var skill_id := ""
var visual_role := ""
var radius := 72.0
var lifetime := 0.8
var direction := Vector2.DOWN
var target_node: Node2D
var visual_loaded := false
var _elapsed := 0.0
var _sprites: Array[Sprite2D] = []


func setup(position_value: Vector2, source_skill_id: String, radius_value := 72.0, lifetime_value := 0.8, direction_value := Vector2.DOWN, target: Node2D = null) -> void:
	global_position = position_value
	skill_id = ProfessionRules.skill_id(source_skill_id)
	radius = maxf(20.0, radius_value)
	lifetime = maxf(0.1, lifetime_value)
	direction = direction_value.normalized() if direction_value.length_squared() > 0.0 else Vector2.DOWN
	target_node = target


func _ready() -> void:
	add_to_group("zone_content")
	var entry := CasterSkillVisualRegistry.profile(skill_id)
	visual_role = str(entry.get("role", ""))
	if entry.get("animation", {}).get("contract", "") != "caster_skill_animation.v1":
		return
	if visual_role == "line_effect" and skill_id == "wizard.hellfire":
		_install_repeated_line()
	else:
		_install_single()
	visual_loaded = not _sprites.is_empty()


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(target_node):
		global_position = target_node.global_position
	var alpha := clampf((lifetime - _elapsed) / minf(0.25, lifetime), 0.0, 1.0)
	for sprite: Sprite2D in _sprites:
		sprite.modulate.a = alpha
	if _elapsed >= lifetime:
		queue_free()


func _install_single() -> void:
	var sprite := AnimationPlayerScript.new()
	var desired_extent := 72.0
	match visual_role:
		"line_effect":
			desired_extent = radius * 2.0
		"area_effect", "self_area", "ground_effect":
			desired_extent = radius * 2.0
		"target_effect", "self_effect":
			desired_extent = 260.0 if skill_id == "wizard.lightning" else minf(120.0, radius * 1.7)
	if not sprite.configure(skill_id, direction, desired_extent):
		sprite.queue_free()
		return
	add_child(sprite)
	_sprites.append(sprite)


func _install_repeated_line() -> void:
	var count := maxi(2, int(radius / 42.0))
	for step: int in range(1, count + 1):
		var sprite := AnimationPlayerScript.new()
		if not sprite.configure(skill_id, direction, 54.0):
			sprite.queue_free()
			continue
		sprite.position = direction * (float(step) * radius / float(count))
		add_child(sprite)
		_sprites.append(sprite)
