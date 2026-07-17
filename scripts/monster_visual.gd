class_name MonsterVisual
extends Node2D

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const BOSS_ART_PATH := "res://assets/data/classic_boss_client_art_sources.json"
const COMPLETE_ART_PATH := "res://assets/data/complete_monster_client_art_sources.json"
# WIL px/py values are relative to the classic DrawChr origin, not to the
# actor's ground point. The player client-art path already migrates this same
# origin by (+32,+28); monsters must use the identical coordinate conversion.
const CLIENT_ACTOR_GROUND_OFFSET := Vector2i(32, 28)

static var _boss_art: Dictionary = {}
static var _complete_art: Dictionary = {}

var actor: EnemyActor
var sprite: Sprite2D
var active_resources: Dictionary = {}
var current_state := "idle"
var current_direction := 0
var current_frame := 0
var frame_size := ArtSpec.MONSTER_FRAME
var foot_anchor := ArtSpec.MONSTER_FOOT_ANCHOR
var actor_ground_offset := Vector2i.ZERO
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
	active_resources = _resources_for(actor.monster_data)
	visible = not active_resources.is_empty()
	if visible:
		var resources: Dictionary = active_resources
		frame_size = resources.get("frame_size", ArtSpec.MONSTER_FRAME)
		foot_anchor = resources.get("foot_anchor", ArtSpec.MONSTER_FOOT_ANCHOR)
		actor_ground_offset = resources.get("actor_ground_offset", Vector2i.ZERO)
	sprite = Sprite2D.new()
	sprite.name = "BodySprite"
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.centered = false
	sprite.position = -Vector2(foot_anchor + actor_ground_offset)
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


func _resources_for(monster_data: Dictionary) -> Dictionary:
	var monster_name := str(monster_data.get("name", actor.display_name if is_instance_valid(actor) else ""))
	var stable_lookup := MonsterIdentityScript.animation_lookup_name(monster_data)
	var lookup_names := [stable_lookup] if not stable_lookup.is_empty() else []
	if not monster_name.is_empty() and not lookup_names.has(monster_name):
		lookup_names.append(monster_name)
	if monster_name.ends_with("0"):
		lookup_names.append(monster_name.trim_suffix("0"))
	var monster_key := MonsterIdentityScript.stable_key(monster_data)
	var complete_manifest := _complete_art_manifest()
	if not monster_key.is_empty():
		var complete_mapping: Variant = complete_manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key, {})
		if complete_mapping is Dictionary and not complete_mapping.is_empty():
			return _client_resources(complete_mapping)
	var boss_manifest := _boss_art_manifest()
	if not monster_key.is_empty():
		var boss_mapping: Variant = boss_manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key, {})
		if boss_mapping is Dictionary and not boss_mapping.is_empty():
			return _client_resources(boss_mapping)
	for lookup_name: String in lookup_names:
		var legacy_boss_mapping: Variant = boss_manifest.get("runtimeMappings", {}).get(lookup_name, {})
		if legacy_boss_mapping is Dictionary and not legacy_boss_mapping.is_empty():
			return _client_resources(legacy_boss_mapping)
	for manifest: Dictionary in [GameData.bich_common_art, GameData.bich_undead_art]:
		if not monster_key.is_empty():
			var id_mapping: Variant = manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key, {})
			if id_mapping is String:
				id_mapping = manifest.get("runtimeMappings", {}).get(id_mapping, {})
			if id_mapping is Dictionary and not id_mapping.is_empty():
				return _client_resources(id_mapping)
		for lookup_name:String in lookup_names:
			var canonical_name := str(manifest.get("legacyAliases", {}).get(lookup_name, lookup_name))
			var client_mapping: Variant = manifest.get("runtimeMappings", {}).get(canonical_name, {})
			if client_mapping is Dictionary and not client_mapping.is_empty():
				return _client_resources(client_mapping)
	for lookup_name:String in lookup_names:
		var resources:=PresentationAssets.monster_resources(lookup_name)
		if not resources.is_empty():return resources
	return {}


func _boss_art_manifest() -> Dictionary:
	if _boss_art.is_empty() and FileAccess.file_exists(BOSS_ART_PATH):
		var file := FileAccess.open(BOSS_ART_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_boss_art = parsed if parsed is Dictionary else {}
	return _boss_art


func _complete_art_manifest() -> Dictionary:
	if _complete_art.is_empty() and FileAccess.file_exists(COMPLETE_ART_PATH):
		var file := FileAccess.open(COMPLETE_ART_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_complete_art = parsed if parsed is Dictionary else {}
	return _complete_art


func ground_contact_offset() -> Vector2:
	return Vector2.ZERO


func ground_contact_position(fallback: Vector2) -> Vector2:
	return position if uses_final_art() else fallback


func _direction_row(direction: Vector2) -> int:
	if str(active_resources.get("direction_policy", "mir2_directional")) == "fixed_source_direction":
		return 0
	# Raw Mon*.wil atlases are north-first. Project-authored turnaround atlases
	# are south-first. Every resource declares its convention here instead of
	# forcing one global mapping and breaking half the monster roster.
	return MonsterAnimationPolicy.direction_row(direction, StringName(str(active_resources.get("direction_mode", "logical_south_first"))))


func _client_resources(client_mapping: Dictionary) -> Dictionary:
	var actions: Variant = client_mapping.get("actions", {})
	var result := {
		"frame_size": Vector2i(int(client_mapping.get("frameSize", [160, 160])[0]), int(client_mapping.get("frameSize", [160, 160])[1])),
		"foot_anchor": Vector2i(int(client_mapping.get("footAnchor", [80, 138])[0]), int(client_mapping.get("footAnchor", [80, 138])[1])),
		"actor_ground_offset": CLIENT_ACTOR_GROUND_OFFSET,
		"frame_counts": {},
		"direction_mode": "mir2_north_first",
		"direction_policy": str(client_mapping.get("directionPolicy", "mir2_directional")),
		"animation_source": "classic_client_wil",
	}
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Variant = actions.get(action_name, {}) if actions is Dictionary else {}
		var path := str(action.get("path", "")) if action is Dictionary else ""
		if path.is_empty():
			return {}
		var frame_count := int(action.get("framesPerDirection", 1))
		var texture := _load_client_texture(path, Vector2i(result.frame_size.x * frame_count, result.frame_size.y * 8))
		if texture == null:
			return {}
		result[action_name] = texture
		result["frame_counts"][action_name] = frame_count
	return result if MonsterAnimationPolicy.validate(result).is_empty() else {}


func _load_client_texture(path: String, expected_size: Vector2i) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null and Vector2i(imported.get_size()) == expected_size:
			return imported
	# Headless test runs can see a freshly generated PNG before Godot has made
	# its import cache. Loading the source image keeps the data-driven manifest
	# testable without sharing .godot between worktrees.
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


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
