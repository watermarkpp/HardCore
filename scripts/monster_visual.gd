class_name MonsterVisual
extends Node2D

var actor: EnemyActor
var sprite: Sprite2D
var active_resources: Dictionary = {}
var current_state := "idle"
var current_direction := 0
var current_frame := 0
var frame_size := ArtSpec.MONSTER_FRAME
var foot_anchor := ArtSpec.MONSTER_FOOT_ANCHOR
var _elapsed := 0.0
var _last_state := ""
var _attack_remaining := 0.0
var _hit_remaining := 0.0
var _death_remaining := 0.0
var _action_duration := 0.0


func setup(owner_actor: EnemyActor) -> void:
	actor = owner_actor


func _ready() -> void:
	# 普通怪下沉4px，Boss下沉6px，使脚底与阴影中心实际重叠。
	position = Vector2(0, 6 if actor.is_boss else 4)
	active_resources = _resources_for(actor.display_name)
	visible = not active_resources.is_empty()
	if visible:
		var resources: Dictionary = active_resources
		frame_size = resources.get("frame_size", ArtSpec.MONSTER_FRAME)
		foot_anchor = resources.get("foot_anchor", ArtSpec.MONSTER_FOOT_ANCHOR)
	sprite = Sprite2D.new()
	sprite.name = "BodySprite"
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.centered = false
	sprite.position = -Vector2(foot_anchor)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	if visible:
		sprite.texture = active_resources["idle"]


func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	_hit_remaining = maxf(0.0, _hit_remaining - delta)
	_death_remaining = maxf(0.0, _death_remaining - delta)
	if not visible:
		return
	if _death_remaining > 0.0:
		current_state = "death"
	elif _attack_remaining > 0.0:
		current_state = "attack"
	elif _hit_remaining > 0.0:
		current_state = "hit"
	elif actor.velocity.length_squared() > 25.0:
		current_state = "walk"
	else:
		current_state = "idle"
	var visual_facing: Vector2 = actor.movement_facing if current_state == "walk" else actor.facing
	current_direction = _direction_row(visual_facing)
	if current_state != _last_state:
		_elapsed = 0.0
		_last_state = current_state
	_elapsed += delta
	var frame_count := MonsterAnimationPolicy.frame_count(active_resources, StringName(current_state))
	if current_state in ["attack", "hit", "death"]:
		var progress := clampf(_elapsed / maxf(_action_duration, 0.001), 0.0, 0.999)
		current_frame = mini(frame_count - 1, int(floor(progress * frame_count)))
	else:
		var fps := MonsterAnimationPolicy.loop_fps(StringName(current_state))
		current_frame = int(floor(_elapsed * fps)) % frame_count
	sprite.texture = active_resources[current_state]
	sprite.region_rect = Rect2(current_frame * frame_size.x, current_direction * frame_size.y, frame_size.x, frame_size.y)


func _resources_for(monster_name: String) -> Dictionary:
	var lookup_names := [monster_name]
	if monster_name.ends_with("0"):
		lookup_names.append(monster_name.trim_suffix("0"))
	for manifest: Dictionary in [GameData.bich_common_art, GameData.bich_undead_art]:
		for lookup_name:String in lookup_names:
			var client_mapping: Variant = manifest.get("runtimeMappings", {}).get(lookup_name, {})
			if client_mapping is Dictionary and not client_mapping.is_empty():
				return _client_resources(client_mapping)
	for lookup_name:String in lookup_names:
		var resources:=PresentationAssets.monster_resources(lookup_name)
		if not resources.is_empty():return resources
	return {}


func _direction_row(direction: Vector2) -> int:
	# Raw Mon*.wil atlases are north-first. Project-authored turnaround atlases
	# are south-first. Every resource declares its convention here instead of
	# forcing one global mapping and breaking half the monster roster.
	return MonsterAnimationPolicy.direction_row(direction, StringName(str(active_resources.get("direction_mode", "logical_south_first"))))


func _client_resources(client_mapping: Dictionary) -> Dictionary:
	var actions: Variant = client_mapping.get("actions", {})
	var result := {
		"frame_size": Vector2i(int(client_mapping.get("frameSize", [160, 160])[0]), int(client_mapping.get("frameSize", [160, 160])[1])),
		"foot_anchor": Vector2i(int(client_mapping.get("footAnchor", [80, 138])[0]), int(client_mapping.get("footAnchor", [80, 138])[1])),
		"frame_counts": {},
		"direction_mode": "mir2_north_first",
		"animation_source": "classic_client_wil",
	}
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Variant = actions.get(action_name, {}) if actions is Dictionary else {}
		var path := str(action.get("path", "")) if action is Dictionary else ""
		if path.is_empty() or not ResourceLoader.exists(path):
			return {}
		result[action_name] = load(path) as Texture2D
		result["frame_counts"][action_name] = int(action.get("framesPerDirection", 1))
	return result if MonsterAnimationPolicy.validate(result).is_empty() else {}


func play_attack(duration := 0.46) -> void:
	if _death_remaining > 0.0:
		return
	_attack_remaining = duration
	_action_duration = duration
	_elapsed = 0.0


func play_hit(duration := 0.22) -> void:
	if _death_remaining > 0.0:
		return
	_hit_remaining = duration
	_action_duration = duration
	_elapsed = 0.0


func play_death(duration := 0.62) -> void:
	_death_remaining = duration
	_hit_remaining = 0.0
	_attack_remaining = 0.0
	_action_duration = duration
	_elapsed = 0.0


func uses_final_art() -> bool:
	return visible and sprite != null and sprite.texture != null


func is_fallback_attacking() -> bool:
	return not uses_final_art() and _attack_remaining > 0.0


func fallback_attack_progress() -> float:
	if not is_fallback_attacking() or _action_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _attack_remaining / _action_duration, 0.0, 1.0)


func fallback_lunge_offset(direction: Vector2) -> Vector2:
	return direction.normalized() * sin(fallback_attack_progress() * PI) * 12.0 if is_fallback_attacking() else Vector2.ZERO


func fallback_attack_scale() -> Vector2:
	if not is_fallback_attacking():return Vector2.ONE
	var pulse:=sin(fallback_attack_progress()*PI)
	return Vector2(1.0+0.18*pulse,1.0-0.12*pulse)


func fallback_attack_angle(direction:Vector2)->float:
	if not is_fallback_attacking():return 0.0
	var side:=signf(direction.x) if absf(direction.x)>0.05 else 1.0
	return side*sin(fallback_attack_progress()*TAU)*0.12
