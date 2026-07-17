class_name CasterSkillVisualEffect
extends Node2D

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
	var texture := CasterSkillVisualRegistry.texture(skill_id)
	if texture == null:
		return
	if visual_role == "line_effect" and skill_id == "wizard.hellfire":
		_install_repeated_line(texture)
	else:
		_install_single(texture)
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


func _install_single(texture: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	var width := maxf(1.0, float(texture.get_width()))
	var height := maxf(1.0, float(texture.get_height()))
	match visual_role:
		"line_effect":
			sprite.rotation = direction.angle() + PI / 2.0
			sprite.scale = Vector2(radius * 0.75 / width, radius * 2.0 / height)
			sprite.position = direction * radius
		"area_effect", "self_area", "ground_effect":
			sprite.scale = Vector2.ONE * (radius * 2.0 / maxf(width, height))
		"target_effect", "self_effect":
			var desired_height := 260.0 if skill_id == "wizard.lightning" else minf(120.0, radius * 1.7)
			sprite.scale = Vector2.ONE * (desired_height / height)
		_:
			sprite.scale = Vector2.ONE * (72.0 / maxf(width, height))
	add_child(sprite)
	_sprites.append(sprite)


func _install_repeated_line(texture: Texture2D) -> void:
	var maximum_dimension := maxf(1.0, float(maxi(texture.get_width(), texture.get_height())))
	var count := maxi(2, int(radius / 42.0))
	for step: int in range(1, count + 1):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.scale = Vector2.ONE * (54.0 / maximum_dimension)
		sprite.position = direction * (float(step) * radius / float(count))
		add_child(sprite)
		_sprites.append(sprite)
