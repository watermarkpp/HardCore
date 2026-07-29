class_name SummonActor
extends CharacterBody2D

signal summon_state_changed(previous_state: int, current_state: int)

const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")
const CasterAnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")

enum SummonState {
	FOLLOW_OWNER,
	ACQUIRE_TARGET,
	CHASE_TARGET,
	ATTACK_TARGET,
	RETURN_TO_OWNER,
	EXPIRED,
	DEAD,
}

const VISUAL_PATHS := {
	"taoist.summon_skeleton": "res://assets/art/characters/taoist/effects/summon_skeleton.png",
	"taoist.summon_divine_beast": "res://assets/art/characters/taoist/effects/summon_divine_beast.png",
}

var owner_player: PlayerCharacter
var summon_name := "骷髅"
var summon_id := "skeleton"
var skill_id := "taoist.summon_skeleton"
var skill_level := 0
var summon_level := 0
var summon_exp_level := 0
var summon_count := 1
var attack_type := "physical"
var max_hp := 80
var current_hp := 80
var attack_min := 3
var attack_max := 6
var move_speed := 135.0
var attack_range := 48.0
var aggro_radius := 330.0
var collision_radius := 15.0
var attack_interval := 1.25
var lifetime_seconds := 864000.0
var remaining_lifetime := 864000.0
var leash_range := 560.0
var teleport_range := 900.0
var follow_distance := 75.0
var owner_death_rule := "expire"
var reject_when_owner_has_slave := true
var recall_existing_on_create_failure := false
var state := SummonState.FOLLOW_OWNER
var last_attack_type := ""
var _attack_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _sprite: Sprite2D
var _current_target: EnemyActor
var _animation_resources: Dictionary = {}
var _visual_state := "idle"
var _visual_direction := 0
var _visual_frame := 0
var _visual_elapsed := 0.0
var _visual_facing := Vector2.DOWN
var _attack_visual_remaining := 0.0
var _hit_visual_remaining := 0.0
var _death_visual_remaining := 0.0
var _visual_activation_retry := 0.0


func setup(player: PlayerCharacter, display_name: String, power: int, learned_level := -1, source_skill_id := "", owner_level_value := -1) -> void:
	owner_player = player
	var inferred_skill_id := source_skill_id
	if inferred_skill_id.is_empty():
		inferred_skill_id = "taoist.summon_divine_beast" if display_name == "神兽" else "taoist.summon_skeleton"
	var inferred_level := learned_level
	if inferred_level < 0 and PlayerState != null:
		inferred_level = PlayerState.effective_skill_level(ProfessionRules.skill_display_name(inferred_skill_id))
	var inferred_owner_level := owner_level_value
	if inferred_owner_level < 1 and PlayerState != null:
		inferred_owner_level = PlayerState.level
	var profile := TaoistCombatMath.summon_profile(inferred_skill_id, maxi(0, inferred_level), maxi(1, inferred_owner_level), maxi(1, power))
	skill_id = inferred_skill_id
	skill_level = int(profile.get("skill_level", 0))
	summon_level = int(profile.get("summon_level", skill_level))
	summon_exp_level = int(profile.get("summon_exp_level", skill_level))
	summon_count = int(profile.get("summon_count", 1))
	summon_id = str(profile.get("summon_id", "skeleton"))
	summon_name = str(profile.get("display_name", display_name))
	attack_type = str(profile.get("attack_type", "physical"))
	max_hp = int(profile.get("max_hp", 60 + power * 12))
	current_hp = max_hp
	attack_min = int(profile.get("attack_min", maxi(1, int(power / 2))))
	attack_max = int(profile.get("attack_max", maxi(attack_min, power)))
	move_speed = float(profile.get("move_speed", 155.0 if summon_name == "神兽" else 135.0))
	attack_range = float(profile.get("attack_range", 48.0))
	attack_interval = float(profile.get("attack_interval", 1.25))
	aggro_radius = float(profile.get("aggro_radius", 330.0))
	lifetime_seconds = float(profile.get("lifetime_seconds", 864000.0))
	remaining_lifetime = lifetime_seconds
	leash_range = float(profile.get("leash_range", 560.0))
	teleport_range = float(profile.get("teleport_range", 900.0))
	owner_death_rule = str(profile.get("owner_death_rule", "expire"))
	reject_when_owner_has_slave = bool(profile.get("reject_when_owner_has_slave", true))
	recall_existing_on_create_failure = bool(profile.get("recall_existing_on_create_failure", false))
	state = SummonState.FOLLOW_OWNER


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
	_install_visual()
	queue_redraw()


func _process(delta: float) -> void:
	if summon_id != "divine_beast":
		return
	_attack_visual_remaining = maxf(0.0, _attack_visual_remaining - delta)
	_hit_visual_remaining = maxf(0.0, _hit_visual_remaining - delta)
	if state == SummonState.DEAD:
		_death_visual_remaining = maxf(0.0, _death_visual_remaining - delta)
		if _death_visual_remaining <= 0.0:
			queue_free()
			return
	if _animation_resources.is_empty():
		_visual_activation_retry = maxf(0.0, _visual_activation_retry - delta)
		if _visual_activation_retry <= 0.0:
			_visual_activation_retry = 0.25
			activate_visual_resources()
		return
	var next_visual_state := "idle"
	if state == SummonState.DEAD:
		next_visual_state = "death"
	elif _hit_visual_remaining > 0.0:
		next_visual_state = "hit"
	elif _attack_visual_remaining > 0.0:
		next_visual_state = "attack"
	elif velocity.length_squared() > 25.0:
		next_visual_state = "walk"
	if next_visual_state != _visual_state:
		_visual_state = next_visual_state
		_visual_elapsed = 0.0
	else:
		_visual_elapsed += delta
	if velocity.length_squared() > 25.0:
		_visual_facing = velocity.normalized()
	elif is_instance_valid(_current_target):
		var target_offset := _current_target.global_position - global_position
		if target_offset.length_squared() > 0.001:
			_visual_facing = target_offset.normalized()
	elif is_instance_valid(owner_player) and owner_player.facing.length_squared() > 0.001:
		_visual_facing = owner_player.facing.normalized()
	_visual_direction = ArtSpec.mir2_client_direction_row(_visual_facing)
	var frame_count := int(_animation_resources.get("frame_counts", {}).get(_visual_state, 1))
	var frame_ms := int(_animation_resources.get("frame_ms", {}).get(_visual_state, 100))
	if _visual_state in ["attack", "hit", "death"]:
		_visual_frame = mini(frame_count - 1, int(floor(_visual_elapsed * 1000.0 / float(maxi(1, frame_ms)))))
	else:
		_visual_frame = int(floor(_visual_elapsed * 1000.0 / float(maxi(1, frame_ms)))) % frame_count
	_apply_visual_frame()


func _physics_process(delta: float) -> void:
	if state == SummonState.DEAD:
		velocity = Vector2.ZERO
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	remaining_lifetime = maxf(0.0, remaining_lifetime - delta)
	if remaining_lifetime <= 0.0:
		_expire()
		return
	if not is_instance_valid(owner_player) or owner_player.current_hp <= 0:
		_expire()
		return
	var owner_distance := global_position.distance_to(owner_player.global_position)
	if owner_distance >= teleport_range:
		_set_state(SummonState.RETURN_TO_OWNER)
		global_position = owner_player.global_position + owner_player.facing.orthogonal() * 42.0
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if not is_instance_valid(_current_target) or _current_target.is_queued_for_deletion():
		if state not in [SummonState.FOLLOW_OWNER, SummonState.RETURN_TO_OWNER]:
			_set_state(SummonState.ACQUIRE_TARGET)
		_current_target = _nearest_enemy()
	var enemy := _current_target
	if enemy != null and enemy.global_position.distance_to(owner_player.global_position) > leash_range:
		_current_target = null
		enemy = null
	if enemy != null:
		var offset := enemy.global_position - global_position
		if offset.length() <= attack_range:
			_set_state(SummonState.ATTACK_TARGET)
			velocity = Vector2.ZERO
			if _attack_timer <= 0.0:
				_attack_timer = attack_interval
				last_attack_type = attack_type
				_attack_visual_remaining = _visual_action_duration("attack")
				enemy.take_damage(_rng.randi_range(attack_min, attack_max), self)
		else:
			_set_state(SummonState.CHASE_TARGET)
			velocity = offset.normalized() * move_speed
	else:
		var owner_offset := owner_player.global_position - global_position
		if owner_offset.length() > follow_distance:
			_set_state(SummonState.RETURN_TO_OWNER)
			velocity = owner_offset.normalized() * move_speed
		else:
			_set_state(SummonState.FOLLOW_OWNER)
			velocity = Vector2.ZERO
	move_and_slide()
	queue_redraw()


func _expire() -> void:
	if state == SummonState.EXPIRED or state == SummonState.DEAD:
		return
	_set_state(SummonState.EXPIRED)
	velocity = Vector2.ZERO
	queue_free()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	var previous_state := state
	state = next_state
	summon_state_changed.emit(previous_state, state)


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
		_set_state(SummonState.DEAD)
		velocity = Vector2.ZERO
		_hit_visual_remaining = 0.0
		_attack_visual_remaining = 0.0
		_death_visual_remaining = _visual_action_duration("death")
		_visual_state = "death"
		_visual_elapsed = 0.0
	elif summon_id == "divine_beast":
		_hit_visual_remaining = _visual_action_duration("hit")
		_visual_state = "hit"
		_visual_elapsed = 0.0
	queue_redraw()


func state_name() -> String:
	return SummonState.keys()[state]


func _install_visual() -> void:
	if summon_id == "divine_beast":
		_sprite = Sprite2D.new()
		_sprite.name = "DivineBeastAnimatedBody"
		_sprite.centered = false
		_sprite.region_enabled = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
		activate_visual_resources()
		return
	if skill_id == "taoist.summon_skeleton":
		var skeleton_animation := CasterAnimationPlayerScript.new()
		if not skeleton_animation.configure(skill_id, Vector2.DOWN, 0.0):
			skeleton_animation.queue_free()
			return
		skeleton_animation.name = "SkeletonPrimaryStandAnimation"
		_sprite = skeleton_animation
		add_child(_sprite)
		return
	var texture := CasterSkillVisualRegistry.texture(skill_id)
	if texture == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	var maximum_dimension := maxf(float(texture.get_width()), float(texture.get_height()))
	var desired_size := 64.0 if summon_id == "divine_beast" else 50.0
	_sprite.scale = Vector2.ONE * desired_size / maxf(1.0, maximum_dimension)
	_sprite.position = Vector2(0, -12)
	add_child(_sprite)


func activate_visual_resources() -> bool:
	if summon_id != "divine_beast":
		return _sprite != null
	var profile := SummonVisualRegistryScript.profile(summon_id)
	if profile.is_empty():
		return false
	_animation_resources = profile
	var frame_size: Vector2i = profile.get("frame_size", Vector2i.ZERO)
	var foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var actor_ground_offset: Vector2i = profile.get("actor_ground_offset", Vector2i.ZERO)
	_sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	_sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	refresh_visual_after_activation()
	return true


func refresh_visual_after_activation() -> void:
	if _animation_resources.is_empty() or _sprite == null:
		return
	_visual_state = "death" if state == SummonState.DEAD else "idle"
	_visual_direction = ArtSpec.mir2_client_direction_row(_visual_facing)
	_visual_frame = 0
	_visual_elapsed = 0.0
	_apply_visual_frame()


func _apply_visual_frame() -> void:
	if _animation_resources.is_empty() or _sprite == null:
		return
	var frame_size: Vector2i = _animation_resources.get("frame_size", Vector2i.ZERO)
	_sprite.texture = _animation_resources.get(_visual_state, null)
	_sprite.region_rect = Rect2(
		_visual_frame * frame_size.x,
		_visual_direction * frame_size.y,
		frame_size.x,
		frame_size.y
	)


func _visual_action_duration(action_name: String) -> float:
	if _animation_resources.is_empty():
		return 1.2 if action_name == "death" else 0.2
	var frame_count := int(_animation_resources.get("frame_counts", {}).get(action_name, 1))
	var frame_ms := int(_animation_resources.get("frame_ms", {}).get(action_name, 100))
	return float(frame_count * frame_ms) / 1000.0


func _draw() -> void:
	var color := Color(0.88, 0.72, 0.35) if summon_name == "神兽" else Color(0.72, 0.74, 0.70)
	var radius := 21.0 if summon_name == "神兽" else 15.0
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.28))
	draw_circle(Vector2(0, -1), radius * 0.56, Color(0, 0, 0, 0.56))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sprite == null and summon_id != "divine_beast":
		draw_circle(Vector2(0, -4), radius, color)
		draw_circle(Vector2(-6, -7), 2.5, Color(0.15, 0.75, 0.35))
		draw_circle(Vector2(6, -7), 2.5, Color(0.15, 0.75, 0.35))
	draw_rect(Rect2(-22, -35, 44, 4), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(Rect2(-22, -35, 44.0 * float(current_hp) / float(max_hp), 4), Color(0.22, 0.72, 0.25))
