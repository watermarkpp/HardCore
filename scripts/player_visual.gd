extends Node2D

const WARRIOR_SKILL_COLORS := {
	"攻杀剑术": Color(1.0, 0.82, 0.30, 0.95),
	"刺杀剑术": Color(0.70, 0.90, 1.0, 0.95),
	"半月弯刀": Color(0.95, 0.92, 0.62, 0.92),
	"野蛮冲撞": Color(0.75, 0.52, 0.24, 0.92),
	"烈火剑法": Color(1.0, 0.24, 0.05, 0.98),
	"烈火蓄力": Color(1.0, 0.34, 0.08, 0.92),
}
const CLIENT_EFFECTS := {
	"攻杀剑术": {"asset": "power_hit", "cell": Vector2i(224, 224), "origin": Vector2i(86, 130)},
	"刺杀剑术": {"asset": "long_hit", "cell": Vector2i(288, 224), "origin": Vector2i(119, 144)},
	"半月弯刀": {"asset": "wide_hit", "cell": Vector2i(240, 224), "origin": Vector2i(96, 143)},
	"烈火剑法": {
		"assets": [["fire_hit_d0_f0", "fire_hit_d0_f1"], ["fire_hit_d1_f0", "fire_hit_d1_f1"]],
		"cell": Vector2i(640, 480), "origin": Vector2i(296, 267),
		"directions_per_atlas": 4, "frames_per_atlas": 3,
	},
}
const CLIENT_EFFECT_ACTOR_OFFSET := Vector2(ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR - ArtSpec.WARRIOR_FOOT_ANCHOR)
const BLACK_IRON_HELMET_WORLD_ACTION_PATHS := {
	"idle": "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_idle.png",
	"walk": "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_walk.png",
	"attack": "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_attack.png",
	"hit": "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_hit.png",
	"death": "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_death.png",
}

var actor: PlayerCharacter
var sprite: Sprite2D
var worn_weapon_sprite: Sprite2D
var worn_helmet_sprite: Sprite2D
var hand_r: Marker2D
var hand_l: Marker2D
var head: Marker2D
var back: Marker2D
var feet: Marker2D
var weapon_accent: Line2D
var armor_accent: Polygon2D
var helmet_accent: Polygon2D
var skill_effect: Line2D
var skill_effect_sprite: Sprite2D
var weapon_audio: AudioStreamPlayer2D
var current_state := "idle"
var current_direction := 0
var current_frame := 0
var _elapsed := 0.0
var _action_remaining := 0.0
var _action_duration := 0.0
var _last_state := ""
var _action_name := "attack"
var _action_audio_played := false
var _dress_action_textures: Dictionary = {}
var _weapon_action_textures: Dictionary = {}
var _helmet_action_textures: Dictionary = {}
var _weapon_frame_size := ArtSpec.WARRIOR_FRAME
var _weapon_source_anchor := ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR
var _weapon_attack_source_frames: Array = []
var _weapon_mapping_known := false


func setup(owner_actor: PlayerCharacter) -> void:
	actor = owner_actor


func _ready() -> void:
	# 图集脚掌压入演员原点处的地面阴影，消除手机缩放后的悬空缝隙。
	position = Vector2(0, 4)
	sprite = Sprite2D.new()
	sprite.name = "BodySprite"
	sprite.texture = PresentationAssets.player_texture("idle")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, ArtSpec.CHARACTER_FRAME)
	sprite.centered = false
	sprite.position = -Vector2(ArtSpec.CHARACTER_FOOT_ANCHOR)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	worn_weapon_sprite = Sprite2D.new()
	worn_weapon_sprite.name = "ClientWeaponLayer"
	worn_weapon_sprite.region_enabled = true
	worn_weapon_sprite.centered = false
	worn_weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	worn_weapon_sprite.visible = false
	add_child(worn_weapon_sprite)
	worn_helmet_sprite = Sprite2D.new()
	worn_helmet_sprite.name = "ClientHelmetLayer"
	worn_helmet_sprite.region_enabled = true
	worn_helmet_sprite.centered = false
	worn_helmet_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	worn_helmet_sprite.visible = false
	worn_helmet_sprite.z_index = 2
	add_child(worn_helmet_sprite)
	hand_r = _marker("hand_r")
	hand_l = _marker("hand_l")
	head = _marker("head")
	back = _marker("back")
	feet = _marker("feet")
	weapon_accent = _line_layer("WeaponAccent", 3.0)
	armor_accent = _polygon_layer("ArmorAccent", PackedVector2Array([Vector2(-13, -53), Vector2(13, -53), Vector2(16, -29), Vector2(-16, -29)]))
	helmet_accent = _polygon_layer("HelmetAccent", PackedVector2Array([Vector2(-9, -72), Vector2(0, -78), Vector2(9, -72), Vector2(7, -65), Vector2(-7, -65)]))
	skill_effect = _line_layer("SkillEffect", 5.0)
	skill_effect_sprite = Sprite2D.new()
	skill_effect_sprite.name = "ClientSkillEffect"
	skill_effect_sprite.region_enabled = true
	skill_effect_sprite.centered = false
	skill_effect_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skill_effect_sprite.visible = false
	skill_effect_sprite.z_index = 1
	add_child(skill_effect_sprite)
	weapon_audio = AudioStreamPlayer2D.new()
	weapon_audio.name = "WeaponAudio"
	weapon_audio.max_distance = 700.0
	weapon_audio.volume_db = -4.0
	add_child(weapon_audio)
	if not PlayerState.equipment_changed.is_connected(_refresh_equipment_visuals):
		PlayerState.equipment_changed.connect(_refresh_equipment_visuals)
	_refresh_equipment_visuals()
	_update_visibility()


func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	_update_visibility()
	if not visible:
		return
	_action_remaining = maxf(0.0, _action_remaining - delta)
	current_state = "action" if _action_remaining > 0.0 else ("walk" if actor.velocity.length_squared() > 25.0 else "idle")
	# 移动时以实际速度为最高优先级，避免自动目标/战斗朝向覆盖行走动画方向。
	var visual_direction: Vector2 = actor.movement_facing if actor.movement_input_active and current_state == "walk" else actor.facing
	current_direction = _resolved_direction_row()
	if current_state != _last_state:
		_elapsed = 0.0
		_last_state = current_state
	_elapsed += delta
	var fps := 12.0 if current_state == "action" else (10.0 if current_state == "walk" else 6.0)
	var frame_count := _current_frame_count()
	if current_state == "action":
		match _action_name:
			"attack": frame_count = _warrior_or_default_frames(&"attack")
			"hit": frame_count = _warrior_or_default_frames(&"hit")
			"death": frame_count = _warrior_or_default_frames(&"death")
			_: frame_count = _warrior_or_default_frames(&"attack") if _is_warrior_attack_action(_action_name) else _warrior_or_default_frames(&"idle")
	if current_state == "action":
		var progress := clampf(_elapsed / maxf(_action_duration, 0.001), 0.0, 0.999)
		current_frame = mini(frame_count - 1, int(floor(progress * frame_count)))
	else:
		current_frame = int(floor(_elapsed * fps)) % frame_count
	var action_key := _visual_action_key()
	sprite.texture = _dress_action_textures.get(action_key, _default_body_texture(action_key))
	var frame_size := ArtSpec.CHARACTER_FRAME
	var foot_anchor := ArtSpec.CHARACTER_FOOT_ANCHOR
	if visible:
		frame_size = ArtSpec.WARRIOR_FRAME
		foot_anchor = ArtSpec.WARRIOR_FOOT_ANCHOR
	sprite.position = -Vector2(foot_anchor)
	sprite.region_rect = Rect2(current_frame * frame_size.x, current_direction * frame_size.y, frame_size.x, frame_size.y)
	var weapon_texture: Texture2D = _weapon_action_textures.get(action_key, null)
	worn_weapon_sprite.texture = weapon_texture
	worn_weapon_sprite.visible = weapon_texture != null
	# Weapon atlases may use a taller cell than Hum.wil. Keep the classic actor
	# origin shared instead of forcing the weapon through the body's crop box.
	worn_weapon_sprite.position = Vector2(
		ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR - ArtSpec.WARRIOR_FOOT_ANCHOR - _weapon_source_anchor
	)
	worn_weapon_sprite.region_rect = Rect2(
		current_frame * _weapon_frame_size.x,
		current_direction * _weapon_frame_size.y,
		_weapon_frame_size.x,
		_weapon_frame_size.y
	)
	var helmet_texture: Texture2D = _helmet_action_textures.get(action_key, null)
	worn_helmet_sprite.texture = helmet_texture
	worn_helmet_sprite.visible = helmet_texture != null
	worn_helmet_sprite.position = sprite.position
	worn_helmet_sprite.region_rect = sprite.region_rect
	_update_markers()
	_update_equipment_layers()
	_update_skill_effect()
	_update_action_audio()


func play_action(animation_name: String, duration: float) -> void:
	if _action_name == "death" and _action_remaining > 0.0 and animation_name != "death":
		return
	_action_name = animation_name
	if animation_name in ["hit", "death"]:
		_action_remaining = duration
		_action_duration = duration
	else:
		_action_remaining = maxf(_action_remaining, duration)
		_action_duration = maxf(_action_duration, duration)
	_elapsed = 0.0
	_action_audio_played = false


func _resolved_direction_row() -> int:
	# Walking must use real screen displacement. Actions use the combat-facing
	# vector captured from the selected target at action start.
	var direction := actor.actual_motion_facing if current_state == "walk" else actor.facing
	return ArtSpec.mir2_client_direction_row(direction)


func current_animation_name() -> String:
	return _action_name if current_state == "action" else current_state


func play_hit(duration := 0.24) -> void:
	play_action("hit", duration)


func play_death(duration := 0.8) -> void:
	play_action("death", duration)


func uses_final_art() -> bool:
	return visible and sprite != null and sprite.texture != null


func health_bar_anchor() -> Vector2:
	# Compatibility accessor for diagnostics. The actual health bar is now an
	# independent PlayerCharacter child and never follows an animation frame's
	# opaque bounds.
	return ArtSpec.PLAYER_HEALTH_BAR_OFFSET


func refresh_profession() -> void:
	_update_visibility()
	_refresh_equipment_visuals()


func _update_visibility() -> void:
	visible = PlayerState.profession == "战士"


func _marker(marker_name: String) -> Marker2D:
	var marker := Marker2D.new()
	marker.name = marker_name
	add_child(marker)
	return marker


func _line_layer(layer_name: String, width: float) -> Line2D:
	var line := Line2D.new()
	line.name = layer_name
	line.width = width
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.visible = false
	add_child(line)
	return line


func _polygon_layer(layer_name: String, points: PackedVector2Array) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.name = layer_name
	polygon.polygon = points
	polygon.visible = false
	add_child(polygon)
	return polygon


func _update_markers() -> void:
	var horizontal: int = [0, -1, -1, -1, 0, 1, 1, 1][current_direction]
	hand_r.position = Vector2(13 * horizontal, -38)
	hand_l.position = Vector2(-11 * horizontal, -36)
	# The helmet texture includes its own lower face guard, so its centre must
	# align with the source head's top rather than the head bounding-box centre.
	head.position = Vector2(-5, -71)
	back.position = Vector2(-8 * horizontal, -45)
	feet.position = Vector2.ZERO


func _is_warrior_attack_action(animation_name: String) -> bool:
	return animation_name == "attack" or WARRIOR_SKILL_COLORS.has(animation_name)


func _visual_action_key() -> String:
	if current_state == "walk":
		return "walk"
	if current_state == "action" and _action_name == "hit":
		return "hit"
	if current_state == "action" and _action_name == "death":
		return "death"
	if current_state == "action" and _is_warrior_attack_action(_action_name):
		return "attack"
	return "idle"


func _default_body_texture(action_key: String) -> Texture2D:
	match action_key:
		"walk": return PresentationAssets.player_texture("walk")
		"attack": return PresentationAssets.player_texture("attack")
		"hit": return PresentationAssets.player_texture("hit")
		"death": return PresentationAssets.player_texture("death")
		_: return PresentationAssets.player_texture("idle")


func _current_frame_count() -> int:
	if current_state == "walk":
		return _warrior_or_default_frames(&"walk")
	return _warrior_or_default_frames(&"idle")


func _warrior_or_default_frames(state: StringName) -> int:
	if visible:
		return int(ArtSpec.WARRIOR_ANIMATION_FRAMES.get(state, ArtSpec.ANIMATION_FRAMES.get(state, 1)))
	return int(ArtSpec.ANIMATION_FRAMES.get(state, 1))


func _equipped_record(slot: String) -> Dictionary:
	var value: Variant = PlayerState.equipment.get(slot, {})
	return value if value is Dictionary else {}


func _equipment_color(record: Dictionary) -> Color:
	var item := GameData.get_item(str(record.get("name", "")))
	var required_level := 0
	if not item.is_empty():
		var raw_level: Variant = item.get("reqLevel", 0)
		if raw_level is int or raw_level is float:
			required_level = int(raw_level)
		elif str(raw_level).is_valid_int():
			required_level = str(raw_level).to_int()
	if required_level >= 35:
		return Color(1.0, 0.32, 0.10, 0.90)
	if required_level >= 22:
		return Color(0.72, 0.42, 1.0, 0.86)
	if required_level >= 12:
		return Color(0.30, 0.72, 1.0, 0.82)
	return Color(0.82, 0.78, 0.62, 0.76)


func _record_is_equipped(record: Dictionary) -> bool:
	# Durability zero disables attributes, not the physical worn appearance.
	return not record.is_empty()


func _load_appearance_actions(source: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not source is Dictionary or not bool(source.get("visible", true)):
		return result
	var actions: Variant = source.get("actions", {})
	if not actions is Dictionary:
		return result
	for action_name: String in actions.keys():
		var action: Variant = actions[action_name]
		var path := str(action.get("path", "")) if action is Dictionary else str(action)
		if not path.is_empty() and ResourceLoader.exists(path):
			result[action_name] = load(path) as Texture2D
	return result


func _appearance_layout(source: Variant) -> Dictionary:
	var fallback := {
		"cell": ArtSpec.WARRIOR_FRAME,
		"foot_anchor": ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR,
	}
	if not source is Dictionary:
		return fallback
	var actions: Variant = source.get("actions", {})
	if not actions is Dictionary:
		return fallback
	for action_name: String in actions.keys():
		var action: Variant = actions[action_name]
		if not action is Dictionary:
			continue
		var cell_value: Variant = action.get("cell", [])
		var anchor_value: Variant = action.get("footAnchor", [])
		if cell_value is Array and cell_value.size() == 2 and anchor_value is Array and anchor_value.size() == 2:
			return {
				"cell": Vector2i(int(cell_value[0]), int(cell_value[1])),
				"foot_anchor": Vector2i(int(anchor_value[0]), int(anchor_value[1])),
			}
	return fallback


func _refresh_equipment_visuals() -> void:
	if weapon_accent == null:
		return
	var weapon := _equipped_record("武器")
	var armor := _equipped_record("衣服")
	var helmet := _equipped_record("头盔")
	var weapon_item := GameData.get_item(str(weapon.get("name", "")))
	var armor_item := GameData.get_item(str(armor.get("name", "")))
	var helmet_item := GameData.get_item(str(helmet.get("name", "")))
	var weapon_art: Dictionary = weapon_item.get("art", {}) if weapon_item is Dictionary else {}
	var armor_art: Dictionary = armor_item.get("art", {}) if armor_item is Dictionary else {}
	var helmet_art: Dictionary = helmet_item.get("art", {}) if helmet_item is Dictionary else {}
	_weapon_mapping_known = weapon_art.has("weaponAppearance")
	var weapon_appearance: Variant = weapon_art.get("weaponAppearance", {})
	_weapon_action_textures = _load_appearance_actions(weapon_appearance)
	var weapon_layout := _appearance_layout(weapon_appearance)
	_weapon_frame_size = weapon_layout.get("cell", ArtSpec.WARRIOR_FRAME)
	_weapon_source_anchor = weapon_layout.get("foot_anchor", ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR)
	_weapon_attack_source_frames = []
	if weapon_appearance is Dictionary:
		var attack_action: Variant = weapon_appearance.get("actions", {}).get("attack", {})
		if attack_action is Dictionary:
			_weapon_attack_source_frames = attack_action.get("sourceFrames", [])
	_dress_action_textures = _load_appearance_actions(armor_art.get("dressAppearance", {}))
	# Never draw the old geometric weapon placeholder.  Together with the body
	# attack frame it formed the unwanted V-shaped default attack artifact.
	weapon_accent.visible = false
	armor_accent.visible = _record_is_equipped(armor) and _dress_action_textures.is_empty()
	# The old translucent polygon was prototype feedback and appeared as a
	# floating blob beside the head/health bar. Use decoded client helmet art.
	helmet_accent.visible = false
	_helmet_action_textures = _load_world_helmet_actions(helmet, helmet_art)
	worn_helmet_sprite.texture = _helmet_action_textures.get("idle", null)
	worn_helmet_sprite.visible = _record_is_equipped(helmet) and worn_helmet_sprite.texture != null
	if weapon_accent.visible:
		weapon_accent.default_color = _equipment_color(weapon)
	if armor_accent.visible:
		var armor_color := _equipment_color(armor)
		armor_color.a = 0.22
		armor_accent.color = armor_color
	if worn_helmet_sprite.visible:
		worn_helmet_sprite.position = head.position


func _update_equipment_layers() -> void:
	if weapon_accent == null:
		return
	var direction := actor.facing.normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.DOWN
	weapon_accent.points = PackedVector2Array([hand_r.position, hand_r.position + direction * 42.0])
	weapon_accent.visible = false
	if worn_weapon_sprite != null:
		# MIR2 rows are N, NE, E, SE, S, SW, W, NW. The weapon is behind the
		# body only while facing away from the camera, including NW (row 7).
		worn_weapon_sprite.z_index = -1 if weapon_draws_behind(current_direction) else 1
	# Helmet and body use the same 192x160 directional atlas grid.  Its region
	# is updated with the body each frame, so it stays on the actual head rather
	# than becoming an independent icon beside the health bar.


func weapon_draws_behind(direction_row: int) -> bool:
	return direction_row in [7, 0, 1]


func _load_world_helmet_actions(record: Dictionary, art: Dictionary) -> Dictionary:
	# Prefer data-driven mappings when more helmet sets are added. StateItem is
	# deliberately excluded because it is equipment-window artwork, not world
	# actor animation data.
	var mapped := _load_appearance_actions(art.get("helmetAppearance", {}))
	if not mapped.is_empty():
		return mapped
	if str(record.get("name", "")) != "黑铁头盔":
		return {}
	var actions: Dictionary = {}
	for action_name: String in BLACK_IRON_HELMET_WORLD_ACTION_PATHS:
		var path := str(BLACK_IRON_HELMET_WORLD_ACTION_PATHS[action_name])
		if not ResourceLoader.exists(path):
			return {}
		actions[action_name] = load(path) as Texture2D
	return actions


func _update_skill_effect() -> void:
	if skill_effect == null or skill_effect_sprite == null:
		return
	var active := current_state == "action" and WARRIOR_SKILL_COLORS.has(_action_name)
	var uses_client_effect := active and CLIENT_EFFECTS.has(_action_name)
	skill_effect_sprite.visible = uses_client_effect
	# The former three-point Line2D fallback was the V-shaped prototype effect.
	# It must not be presented as a finished attack/skill animation.
	skill_effect.visible = false
	if not active:
		return
	if uses_client_effect:
		var effect: Dictionary = CLIENT_EFFECTS[_action_name]
		var cell: Vector2i = effect.cell
		var assets: Variant = effect.get("assets", [])
		if assets is Array and not assets.is_empty():
			var directions_per_atlas := int(effect.get("directions_per_atlas", 4))
			var frames_per_atlas := int(effect.get("frames_per_atlas", 3))
			var direction_group := current_direction / directions_per_atlas
			var frame_group := current_frame / frames_per_atlas
			skill_effect_sprite.texture = PresentationAssets.effect_texture(str(assets[direction_group][frame_group]))
			skill_effect_sprite.region_rect = Rect2(
				Vector2((current_frame % frames_per_atlas) * cell.x, (current_direction % directions_per_atlas) * cell.y),
				Vector2(cell)
			)
		else:
			skill_effect_sprite.texture = PresentationAssets.effect_texture(str(effect.get("asset", "")))
			skill_effect_sprite.region_rect = Rect2(Vector2(current_frame * cell.x, current_direction * cell.y), Vector2(cell))
		# Hum/Weapon pixels were packed around the classic (64,80) actor
		# anchor. Runtime uses (96,108) for ground placement, so Magic.wil must
		# follow the same migration to preserve its source-relative position.
		skill_effect_sprite.position = -Vector2(effect.origin) + CLIENT_EFFECT_ACTOR_OFFSET
		if _action_name == "烈火剑法":
			skill_effect_sprite.position += _fire_weapon_head_alignment()
		skill_effect_sprite.modulate = Color.WHITE
		return


func _fire_weapon_head_alignment() -> Vector2:
	var source_index := current_direction * 6 + current_frame
	if source_index < 0 or source_index >= _weapon_attack_source_frames.size():
		return Vector2.ZERO
	var weapon_frame: Variant = _weapon_attack_source_frames[source_index]
	var fire_frames: Variant = GameData.warrior_client_art.get("effects", {}).get("烈火剑法", {}).get("sourceFrames", [])
	if not weapon_frame is Dictionary or not fire_frames is Array or source_index >= fire_frames.size():
		return Vector2.ZERO
	var fire_frame: Variant = fire_frames[source_index]
	if not fire_frame is Dictionary:
		return Vector2.ZERO
	var tip: Variant = weapon_frame.get("weaponTipOffset", [])
	var ignition: Variant = fire_frame.get("ignitionOffset", [])
	if not tip is Array or tip.size() != 2 or not ignition is Array or ignition.size() != 2:
		return Vector2.ZERO
	return Vector2(float(tip[0]) - float(ignition[0]), float(tip[1]) - float(ignition[1]))


func _update_action_audio() -> void:
	if weapon_audio == null or _action_audio_played or current_state != "action" or current_frame < WarriorCombatMath.CLIENT_EFFECT_FRAME:
		return
	if not _is_warrior_attack_action(_action_name) or _action_name == "烈火蓄力":
		return
	_action_audio_played = true
	weapon_audio.stream = _weapon_swing_stream()
	weapon_audio.play()


func _weapon_swing_stream() -> AudioStream:
	var weapon := _equipped_record("武器")
	if weapon.is_empty():
		return PresentationAssets.audio("fist")
	if "木剑" in str(weapon.get("name", "")):
		return PresentationAssets.audio("wood")
	return PresentationAssets.audio("sword")
