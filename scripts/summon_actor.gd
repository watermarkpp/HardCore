class_name SummonActor
extends CharacterBody2D

var owner_player: PlayerCharacter
var summon_name := "骷髅"
var max_hp := 80
var current_hp := 80
var attack_min := 3
var attack_max := 6
var move_speed := 135.0
var attack_range := 48.0
var aggro_radius := 330.0
var collision_radius := 15.0
var _attack_timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(player: PlayerCharacter, display_name: String, power: int) -> void:
	owner_player = player
	summon_name = display_name
	max_hp = 60 + power * 12
	current_hp = max_hp
	attack_min = maxi(1, int(power / 2))
	attack_max = maxi(attack_min, power)
	move_speed = 155.0 if summon_name == "神兽" else 135.0


func _ready() -> void:
	add_to_group("summons")
	add_to_group("combat_targets")
	add_to_group("zone_content")
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	_rng.randomize()
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	collision_radius = 15.0 if summon_name == "骷髅" else 21.0
	shape.radius = collision_radius
	collision.shape = shape
	add_child(collision)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if not is_instance_valid(owner_player):
		queue_free()
		return
	var enemy := _nearest_enemy()
	if enemy != null:
		var offset := enemy.global_position - global_position
		if offset.length() <= attack_range:
			velocity = Vector2.ZERO
			if _attack_timer <= 0.0:
				_attack_timer = 1.0 if summon_name == "神兽" else 1.25
				enemy.take_damage(_rng.randi_range(attack_min, attack_max), self)
		else:
			velocity = offset.normalized() * move_speed
	else:
		var owner_offset := owner_player.global_position - global_position
		velocity = owner_offset.normalized() * move_speed if owner_offset.length() > 75.0 else Vector2.ZERO
	move_and_slide()
	queue_redraw()


func _nearest_enemy() -> EnemyActor:
	var nearest: EnemyActor
	var nearest_distance := aggro_radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		var distance := global_position.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest


func take_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - maxi(1, amount))
	if current_hp == 0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var color := Color(0.88, 0.72, 0.35) if summon_name == "神兽" else Color(0.72, 0.74, 0.70)
	var radius := 21.0 if summon_name == "神兽" else 15.0
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.28))
	draw_circle(Vector2(0, -1), radius * 0.56, Color(0, 0, 0, 0.56))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(0, -4), radius, color)
	draw_circle(Vector2(-6, -7), 2.5, Color(0.15, 0.75, 0.35))
	draw_circle(Vector2(6, -7), 2.5, Color(0.15, 0.75, 0.35))
	draw_rect(Rect2(-22, -35, 44, 4), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(-22, -35, 44.0 * float(current_hp) / float(max_hp), 4), Color(0.22, 0.72, 0.25))
