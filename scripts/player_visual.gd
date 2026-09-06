extends Node2D

const ACTOR_COMPOSITE_SORT_CONTRACT := EquipmentRules.ACTOR_VISUAL_SORT_CONTRACT_ID
const HelmetVisualV2 := preload("res://scripts/helmet_visual_v2.gd")

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
const SUPPORTED_PROFESSIONS := ["战士", "法师", "道士"]
## Keep the legacy local player silent: audited cues are dispatched to the
## shared AudioRuntimeService pool so simultaneous actors do not restart one
## another and source identity remains event-ID based.
const SKILL_AUDIO_ENABLED := false

var actor: PlayerCharacter
var sprite: Sprite2D
var worn_hair_sprite: Sprite2D
var worn_weapon_sprite: Sprite2D
var worn_helmet_back_sprite: Sprite2D
var worn_helmet_sprite: Sprite2D
var head_occlusion_mask_sprite: Sprite2D
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
var passive_proc_effect_sprite: Sprite2D
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
var _passive_proc_effect_name := ""
var _passive_proc_effect_remaining := 0.0
var _passive_proc_effect_duration := 0.0
var _base_action_textures: Dictionary = {}
var _dress_action_textures: Dictionary = {}
var _hair_action_textures: Dictionary = {}
var _weapon_action_textures: Dictionary = {}
var _helmet_action_textures: Dictionary = {}
var _appearance_texture_cache: Dictionary = {}
var _v2_layer_texture_cache: Dictionary = {}
var _body_action_frame_counts: Dictionary = {}
var _weapon_action_frame_counts: Dictionary = {}
var _helmet_action_frame_counts: Dictionary = {}
var _body_frame_size := ArtSpec.WARRIOR_FRAME
var _body_source_anchor := ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR
var _weapon_frame_size := ArtSpec.WARRIOR_FRAME
var _weapon_source_anchor := ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR
var _weapon_attack_source_frames: Array = []
var _equipment_layer_direction := -1
var _formal_base_loaded := false
var _helmet_item_id := -1
var _helmet_player_visual_id := "player.male.cloth_002"


func setup(owner_actor: PlayerCharacter) -> void:
	actor = owner_actor


func approved_ground_footpoint_in_actor_px() -> Vector2:
	# This is the exact user-approved result from the original 2026-07-30
	# alignment draft. The visual composite was moved to (7.5, 12.5), then the
	# manually picked shoe point received (-7.5, -12.5), resolving to (0, 0).
	# Use the stable formal values instead of a transient sprite frame transform.
	return position + ArtSpec.PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT


func _ready() -> void:
	z_index = 0
	z_as_relative = true
	y_sort_enabled = false
	show_behind_parent = false
	set_as_top_level(false)
	set_meta("actor_render_domain", "actor_y_sort")
	set_meta("actor_composite_sort_contract", ACTOR_COMPOSITE_SORT_CONTRACT)
	# The whole formal visual composite uses the user-approved ground alignment.
	# Physics, map position and the CharacterBody2D origin remain untouched.
	position = ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION
	sprite = Sprite2D.new()
	sprite.name = "BodySprite"
	sprite.texture = PresentationAssets.player_texture("idle")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, ArtSpec.CHARACTER_FRAME)
	sprite.centered = false
	sprite.position = -Vector2(ArtSpec.CHARACTER_FOOT_ANCHOR)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 0
	add_child(sprite)
	worn_hair_sprite = _helmet_sprite_layer("ClientHairLayer")
	worn_weapon_sprite = Sprite2D.new()
	worn_weapon_sprite.name = "ClientWeaponLayer"
	worn_weapon_sprite.region_enabled = true
	worn_weapon_sprite.centered = false
	worn_weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	worn_weapon_sprite.visible = false
	worn_weapon_sprite.z_index = 0
	add_child(worn_weapon_sprite)
	worn_helmet_back_sprite = _helmet_sprite_layer("ClientHelmetBackLayer")
	worn_helmet_sprite = Sprite2D.new()
	worn_helmet_sprite.name = "ClientHelmetLayer"
	worn_helmet_sprite.region_enabled = true
	worn_helmet_sprite.centered = false
	worn_helmet_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	worn_helmet_sprite.visible = false
	worn_helmet_sprite.z_index = 0
	add_child(worn_helmet_sprite)
	head_occlusion_mask_sprite = _helmet_sprite_layer("HeadOcclusionMaskLayer")
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
	skill_effect_sprite.z_index = 0
	add_child(skill_effect_sprite)
	passive_proc_effect_sprite = Sprite2D.new()
	passive_proc_effect_sprite.name = "PassiveProcSkillEffect"
	passive_proc_effect_sprite.region_enabled = true
	passive_proc_effect_sprite.centered = false
	passive_proc_effect_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	passive_proc_effect_sprite.visible = false
	## FREEZE-G0.2-A (FREEZE-B030): keep the passive proc effect on the formal
	## actor composite plane (z=0). Wall fronts and actors only Y-sort when
	## their final z_index matches; any child with z > 0 escapes wall/roof
	## occlusion (equipment_actor_visual_sort_unit_v3).
	passive_proc_effect_sprite.z_index = 0
	add_child(passive_proc_effect_sprite)
	weapon_audio = AudioStreamPlayer2D.new()
	weapon_audio.name = "WeaponAudio"
	weapon_audio.max_distance = 700.0
	weapon_audio.volume_db = -4.0
	add_child(weapon_audio)
	if not PlayerState.equipment_changed.is_connected(_refresh_equipment_visuals):
		PlayerState.equipment_changed.connect(_refresh_equipment_visuals)
	if not GameData.database_reloaded.is_connected(_on_database_reloaded):
		GameData.database_reloaded.connect(_on_database_reloaded)
	_refresh_equipment_visuals()
	_update_visibility()


func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	_update_visibility()
	if not visible:
		return
	_action_remaining = maxf(0.0, _action_remaining - delta)
	var moving := actor.velocity.length_squared() > 0.01
	var locomotion := str(actor.get("locomotion_state"))
	if locomotion != "walk" and locomotion != "run":
		locomotion = "run" if actor.velocity.length_squared() > 25.0 else "walk"
	# Preserve direct presentation-test/manual pose injection, where velocity is
	# assigned without the gameplay movement flag. Runtime movement always uses
	# the authoritative locomotion state above.
	if not bool(actor.get("movement_input_active")) and actor.velocity.length_squared() > 25.0:
		locomotion = "run"
	current_state = "action" if _action_remaining > 0.0 else (locomotion if moving else "idle")
	# 当前移动速度就是跑步速度；移动时以实际速度为最高优先级，避免
	# 自动目标/战斗朝向覆盖跑步动画方向。
	current_direction = _resolved_direction_row()
	if current_state != _last_state:
		_elapsed = 0.0
		_last_state = current_state
	_elapsed += delta
	var fps := 12.0 if current_state == "action" else (10.0 if current_state == "run" else 6.0)
	var action_key := _visual_action_key()
	var frame_count := _frame_count_for_action(action_key)
	if current_state == "action":
		var progress := clampf(_elapsed / maxf(_action_duration, 0.001), 0.0, 0.999)
		current_frame = mini(frame_count - 1, int(floor(progress * frame_count)))
	else:
		current_frame = int(floor(_elapsed * fps)) % frame_count
	sprite.texture = _dress_action_textures.get(action_key, _default_body_texture(action_key))
	sprite.position = Vector2(
		ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR - ArtSpec.WARRIOR_FOOT_ANCHOR - _body_source_anchor
	)
	sprite.region_rect = Rect2(
		current_frame * _body_frame_size.x,
		current_direction * _body_frame_size.y,
		_body_frame_size.x,
		_body_frame_size.y
	)
	var hair_texture: Texture2D = _hair_action_textures.get(
		action_key, null
	)
	worn_hair_sprite.texture = hair_texture
	worn_hair_sprite.visible = (
		PlayerState.gender == "男" and hair_texture != null
	)
	worn_hair_sprite.position = sprite.position
	worn_hair_sprite.region_rect = sprite.region_rect
	worn_hair_sprite.scale = Vector2.ONE
	worn_hair_sprite.flip_h = false
	var weapon_texture: Texture2D = _weapon_action_textures.get(action_key, null)
	worn_weapon_sprite.texture = weapon_texture
	worn_weapon_sprite.visible = weapon_texture != null
	# Weapon atlases may use a taller cell than Hum.wil. Keep the classic actor
	# origin shared instead of forcing the weapon through the body's crop box.
	worn_weapon_sprite.position = Vector2(
		ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR - ArtSpec.WARRIOR_FOOT_ANCHOR - _weapon_source_anchor
	)
	worn_weapon_sprite.region_rect = Rect2(
		_layer_frame(action_key, _weapon_action_frame_counts) * _weapon_frame_size.x,
		current_direction * _weapon_frame_size.y,
		_weapon_frame_size.x,
		_weapon_frame_size.y
	)
	var helmet_source_row := HelmetVisualV2.source_direction_row(_helmet_item_id, current_direction)
	var helmet_frame := _layer_frame(action_key, _helmet_action_frame_counts)
	var v2_front_texture := _v2_layer_texture(
		_helmet_item_id, action_key, current_direction, "helmet_front"
	)
	var helmet_texture: Texture2D = (
		v2_front_texture
		if v2_front_texture != null
		else _helmet_action_textures.get(action_key, null)
	)
	worn_helmet_sprite.texture = helmet_texture
	worn_helmet_sprite.visible = (
		EquipmentRules.world_helmet_is_visible()
		and helmet_texture != null
	)
	var helmet_delta := HelmetVisualV2.final_position_delta(
		_helmet_item_id,
		_helmet_player_visual_id,
		action_key,
		current_direction,
		helmet_frame
	)
	worn_helmet_sprite.position = sprite.position + Vector2(helmet_delta)
	worn_helmet_sprite.scale = Vector2.ONE
	worn_helmet_sprite.flip_h = false
	worn_helmet_sprite.region_rect = Rect2(
		helmet_frame * _body_frame_size.x,
		helmet_source_row * _body_frame_size.y,
		_body_frame_size.x,
		_body_frame_size.y
	)
	var back_texture := _v2_layer_texture(
		_helmet_item_id, action_key, current_direction, "helmet_back"
	)
	var mask_texture := _v2_layer_texture(
		_helmet_item_id, action_key, current_direction, "head_occlusion_mask"
	)
	_update_optional_helmet_layer(
		worn_helmet_back_sprite,
		back_texture,
		worn_helmet_sprite
	)
	_update_optional_helmet_layer(
		head_occlusion_mask_sprite,
		mask_texture,
		worn_helmet_sprite,
		false
	)
	if (
		EquipmentRules.world_helmet_head_mask_enabled()
		and worn_helmet_sprite.visible
		and mask_texture != null
	):
		_apply_current_head_occlusion_mask(
			mask_texture, helmet_source_row, helmet_frame, helmet_delta
		)
	_update_markers()
	_update_equipment_layers()
	_update_skill_effect()
	_update_passive_proc_effect(delta)
	_update_action_audio()


func play_action(animation_name: String, duration: float) -> void:
	var starts_reaction_action := (
		animation_name in ["hit", "death"]
		and not (_action_name == animation_name and _action_remaining > 0.0)
	)
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
	if starts_reaction_action:
		_dispatch_player_reaction_action_start_audio(animation_name)


func play_passive_proc_effect(effect_name: String, duration := 0.24) -> void:
	if not CLIENT_EFFECTS.has(effect_name):
		return
	_passive_proc_effect_name = effect_name
	_passive_proc_effect_duration = maxf(0.01, duration)
	_passive_proc_effect_remaining = _passive_proc_effect_duration


func _resolved_direction_row() -> int:
	# Locomotion must use real screen displacement. Actions use the combat-facing
	# vector captured from the selected target at action start.
	var direction := actor.actual_motion_facing if current_state in ["walk", "run"] else actor.facing
	return ArtSpec.mir2_client_direction_row(direction)


func current_animation_name() -> String:
	return _action_name if current_state == "action" else current_state


func play_hit(duration := 0.24) -> void:
	play_action("hit", duration)


func play_death(duration := 0.8) -> void:
	play_action("death", duration)


func uses_final_art() -> bool:
	return visible and _formal_base_loaded and sprite != null and sprite.texture != null


func health_bar_anchor() -> Vector2:
	# Compatibility accessor for diagnostics. The actual health bar is now an
	# independent PlayerCharacter child and never follows an animation frame's
	# opaque bounds.
	return ArtSpec.PLAYER_HEALTH_BAR_OFFSET


func refresh_profession() -> void:
	_update_visibility()
	_refresh_equipment_visuals()


func _update_visibility() -> void:
	visible = PlayerState.profession in SUPPORTED_PROFESSIONS and _formal_base_loaded


func _marker(marker_name: String) -> Marker2D:
	var marker := Marker2D.new()
	marker.name = marker_name
	add_child(marker)
	return marker


func _helmet_sprite_layer(layer_name: String) -> Sprite2D:
	var layer := Sprite2D.new()
	layer.name = layer_name
	layer.region_enabled = true
	layer.centered = false
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.visible = false
	layer.z_index = 0
	layer.scale = Vector2.ONE
	layer.flip_h = false
	add_child(layer)
	return layer


func _update_optional_helmet_layer(
	layer: Sprite2D,
	texture: Texture2D,
	front_layer: Sprite2D,
	draw_as_sprite: bool = true
) -> void:
	layer.texture = texture
	# A head-occlusion mask is executable alpha data, never a visible colored
	# sprite. The layer node remains available for calibration/debug inspection.
	layer.visible = draw_as_sprite and texture != null and front_layer.visible
	layer.position = front_layer.position
	layer.region_rect = front_layer.region_rect
	layer.scale = Vector2.ONE
	layer.flip_h = false


func _apply_current_head_occlusion_mask(
	mask_texture: Texture2D,
	source_row: int,
	frame_index: int,
	helmet_delta: Vector2i
) -> void:
	if sprite.texture == null:
		return
	var body_rect := Rect2i(sprite.region_rect)
	var body_cell := sprite.texture.get_image().get_region(body_rect)
	var mask_cell := mask_texture.get_image().get_region(Rect2i(
		frame_index * _body_frame_size.x,
		source_row * _body_frame_size.y,
		_body_frame_size.x,
		_body_frame_size.y
	))
	var masked := HelmetVisualV2.apply_alpha_mask(body_cell, mask_cell, helmet_delta)
	sprite.texture = ImageTexture.create_from_image(masked)
	sprite.region_rect = Rect2(Vector2.ZERO, _body_frame_size)


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
	if current_state == "run":
		return "run"
	if current_state == "walk":
		return "walk"
	if current_state == "action" and _action_name == "hit":
		return "hit"
	if current_state == "action" and _action_name == "death":
		return "death"
	if current_state == "action" and _action_name == "cast":
		return "cast"
	if current_state == "action" and _is_warrior_attack_action(_action_name):
		return "attack"
	return "idle"


func _default_body_texture(action_key: String) -> Texture2D:
	var formal: Texture2D = _base_action_textures.get(action_key, null)
	if formal != null:
		return formal
	match action_key:
		# There is no legacy placeholder for running. If the formal male run
		# atlas is missing, fail closed instead of silently reusing another action.
		"run": return null
		"walk": return PresentationAssets.player_texture("walk")
		"attack": return PresentationAssets.player_texture("attack")
		"cast": return PresentationAssets.player_texture("idle")
		"hit": return PresentationAssets.player_texture("hit")
		"death": return PresentationAssets.player_texture("death")
		_: return PresentationAssets.player_texture("idle")


func _current_frame_count() -> int:
	return _frame_count_for_action(
		"run" if current_state == "run" else ("walk" if current_state == "walk" else "idle")
	)


func _frame_count_for_action(action_key: String) -> int:
	return maxi(1, int(_body_action_frame_counts.get(action_key, _warrior_or_default_frames(StringName(action_key)))))


func _layer_frame(action_key: String, frame_counts: Dictionary) -> int:
	return mini(current_frame, maxi(1, int(frame_counts.get(action_key, 1))) - 1)


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
		if path.is_empty():
			continue
		if not _appearance_texture_cache.has(path):
			if ResourceLoader.exists(path):
				_appearance_texture_cache[path] = load(path) as Texture2D
			elif FileAccess.file_exists(path) and path.get_extension().to_lower() == "png":
				var raw_image := Image.load_from_file(path)
				if not raw_image.is_empty():
					_appearance_texture_cache[path] = ImageTexture.create_from_image(
						raw_image
					)
		var texture: Texture2D = _appearance_texture_cache.get(path, null)
		if texture != null:
			result[action_name] = texture
	var fallbacks: Variant = source.get("actionFallbacks", {})
	if fallbacks is Dictionary:
		for action_name: String in fallbacks:
			var fallback_name := str(fallbacks[action_name])
			if not result.has(action_name) and result.has(fallback_name):
				result[action_name] = result[fallback_name]
	return result


func _appearance_frame_counts(source: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not source is Dictionary:
		return result
	var actions: Variant = source.get("actions", {})
	if actions is Dictionary:
		for action_name: String in actions:
			var action: Variant = actions[action_name]
			if action is Dictionary:
				result[action_name] = maxi(1, int(action.get("framesPerDirection", 1)))
	var fallbacks: Variant = source.get("actionFallbacks", {})
	if fallbacks is Dictionary:
		for action_name: String in fallbacks:
			var fallback_name := str(fallbacks[action_name])
			if not result.has(action_name) and result.has(fallback_name):
				result[action_name] = result[fallback_name]
	return result


func _v2_layer_texture(
	item_id: int,
	action_name: String,
	direction_row: int,
	layer_name: String
) -> Texture2D:
	if item_id < 0:
		return null
	var path := HelmetVisualV2.action_texture_path(
		item_id, action_name, direction_row, layer_name
	)
	if path.is_empty():
		return null
	if not _v2_layer_texture_cache.has(path):
		if ResourceLoader.exists(path):
			_v2_layer_texture_cache[path] = load(path) as Texture2D
		elif FileAccess.file_exists(path) and path.get_extension().to_lower() == "png":
			var raw_image := Image.load_from_file(path)
			if not raw_image.is_empty():
				_v2_layer_texture_cache[path] = ImageTexture.create_from_image(
					raw_image
				)
	return _v2_layer_texture_cache.get(path, null)


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


func _stable_item_id_for_equipped(record: Dictionary, item: Dictionary) -> int:
	# Current saves use item_id while older equipment instances may use itemId.
	# Prefer either stable ID over all display-name fields.
	for field_name: String in ["item_id", "itemId"]:
		var raw_id: Variant = record.get(field_name, null)
		if raw_id is int or raw_id is float:
			var numeric_id := int(raw_id)
			if numeric_id >= 0:
				return numeric_id
		var text_id := str(raw_id)
		if text_id.is_valid_int() and text_id.to_int() >= 0:
			return text_id.to_int()
	if not item.is_empty():
		var item_id := int(item.get("itemId", -1))
		if item_id >= 0:
			return item_id
	# Name-only archives are resolved by an exact formal-catalog itemName match.
	# Never guess from aliases or consult a lower-priority source.
	var formal_items: Variant = GameData.equipment_visual_catalog.get("itemsById", {})
	if not formal_items is Dictionary:
		return -1
	for field_name: String in ["name", "itemName"]:
		var exact_name := str(record.get(field_name, ""))
		if exact_name.is_empty():
			continue
		for item_key: Variant in formal_items:
			var formal_item: Variant = formal_items[item_key]
			if formal_item is Dictionary and str(formal_item.get("itemName", "")) == exact_name:
				var item_key_text := str(item_key)
				if item_key_text.is_valid_int():
					return item_key_text.to_int()
	return -1


func _item_record_for_equipped(record: Dictionary) -> Dictionary:
	for field_name: String in ["name", "itemName"]:
		var exact_name := str(record.get(field_name, ""))
		if exact_name.is_empty():
			continue
		var item := GameData.get_item(exact_name)
		if not item.is_empty():
			return item
	return {}


func _resolved_item_appearance(
	record: Dictionary,
	item: Dictionary,
	appearance_type: String,
	legacy_art: Dictionary
) -> Dictionary:
	var stable_item_id := _stable_item_id_for_equipped(record, item)
	if stable_item_id >= 0:
		var resolved := GameData.item_world_appearance(stable_item_id, PlayerState.gender)
		if not resolved.is_empty():
			if str(resolved.get("appearanceType", "")) == appearance_type:
				var appearance: Variant = resolved.get("appearance", {})
				return appearance if appearance is Dictionary else {}
			return {}
	var legacy: Variant = legacy_art.get(appearance_type, {})
	return legacy if legacy is Dictionary else {}


func _refresh_equipment_visuals() -> void:
	if weapon_accent == null:
		return
	var base_appearance := GameData.player_base_appearance(PlayerState.profession, PlayerState.gender)
	_base_action_textures = _load_appearance_actions(base_appearance)
	_formal_base_loaded = not _base_action_textures.is_empty()
	var weapon := _equipped_record("武器")
	var armor := _equipped_record("衣服")
	var helmet := _equipped_record("头盔")
	var weapon_item := _item_record_for_equipped(weapon)
	var armor_item := _item_record_for_equipped(armor)
	var helmet_item := _item_record_for_equipped(helmet)
	var armor_item_id := _stable_item_id_for_equipped(armor, armor_item)
	_helmet_item_id = _stable_item_id_for_equipped(helmet, helmet_item)
	# V2's first calibrated player visual is explicitly male Cloth. Other body
	# visuals retain the established full-cell behavior until they receive their
	# own action/direction/frame socket database.
	if armor_item_id != 116 or PlayerState.gender != "男":
		_helmet_item_id = -1
	var weapon_art: Dictionary = weapon_item.get("art", {}) if weapon_item is Dictionary else {}
	var armor_art: Dictionary = armor_item.get("art", {}) if armor_item is Dictionary else {}
	var helmet_art: Dictionary = helmet_item.get("art", {}) if helmet_item is Dictionary else {}
	var weapon_appearance := _resolved_item_appearance(weapon, weapon_item, "weaponAppearance", weapon_art)
	_weapon_action_textures = _load_appearance_actions(weapon_appearance)
	_weapon_action_frame_counts = _appearance_frame_counts(weapon_appearance)
	var weapon_layout := _appearance_layout(weapon_appearance)
	_weapon_frame_size = weapon_layout.get("cell", ArtSpec.WARRIOR_FRAME)
	_weapon_source_anchor = weapon_layout.get("foot_anchor", ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR)
	_weapon_attack_source_frames = []
	if weapon_appearance is Dictionary:
		var attack_action: Variant = weapon_appearance.get("actions", {}).get("attack", {})
		if attack_action is Dictionary:
			_weapon_attack_source_frames = attack_action.get("sourceFrames", [])
	var dress_appearance := _resolved_item_appearance(armor, armor_item, "dressAppearance", armor_art)
	_dress_action_textures = _load_appearance_actions(dress_appearance)
	var body_appearance: Dictionary = dress_appearance if not _dress_action_textures.is_empty() else base_appearance
	_body_action_frame_counts = _appearance_frame_counts(body_appearance)
	var body_layout := _appearance_layout(body_appearance)
	_body_frame_size = body_layout.get("cell", ArtSpec.WARRIOR_FRAME)
	_body_source_anchor = body_layout.get("foot_anchor", ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR)
	_hair_action_textures = _load_appearance_actions(
		EquipmentRules.world_hair_appearance()
	)
	# Never draw the old geometric weapon placeholder.  Together with the body
	# attack frame it formed the unwanted V-shaped default attack artifact.
	weapon_accent.visible = false
	# Missing client world layers keep the exact formal body; they never fall
	# back to geometric armor placeholders.
	armor_accent.visible = false
	# The old translucent polygon was prototype feedback and appeared as a
	# floating blob beside the head/health bar. Use decoded client helmet art.
	helmet_accent.visible = false
	var helmet_appearance := _resolved_item_appearance(helmet, helmet_item, "helmetAppearance", helmet_art)
	_helmet_action_textures = _load_appearance_actions(helmet_appearance)
	_helmet_action_frame_counts = _appearance_frame_counts(helmet_appearance)
	_v2_layer_texture_cache.clear()
	worn_helmet_sprite.texture = _helmet_action_textures.get("idle", null)
	worn_helmet_sprite.visible = (
		EquipmentRules.world_helmet_is_visible()
		and _record_is_equipped(helmet)
		and worn_helmet_sprite.texture != null
	)
	worn_helmet_back_sprite.visible = false
	head_occlusion_mask_sprite.visible = false
	worn_hair_sprite.texture = _hair_action_textures.get("idle", null)
	worn_hair_sprite.visible = (
		PlayerState.gender == "男" and worn_hair_sprite.texture != null
	)
	if weapon_accent.visible:
		weapon_accent.default_color = _equipment_color(weapon)
	if armor_accent.visible:
		var armor_color := _equipment_color(armor)
		armor_color.a = 0.22
		armor_accent.color = armor_color
	if worn_helmet_sprite.visible:
		worn_helmet_sprite.position = head.position
	_update_visibility()


func _update_equipment_layers() -> void:
	if weapon_accent == null:
		return
	var direction := actor.facing.normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.DOWN
	weapon_accent.points = PackedVector2Array([hand_r.position, hand_r.position + direction * 42.0])
	weapon_accent.visible = false
	if (
		sprite != null
		and worn_hair_sprite != null
		and worn_weapon_sprite != null
		and worn_helmet_back_sprite != null
		and worn_helmet_sprite != null
		and head_occlusion_mask_sprite != null
		and _equipment_layer_direction != current_direction
	):
		# All appearance children must remain on the actor/wall Z=0 plane. Classic
		# front/back overlap is expressed only by sibling order, otherwise a positive
		# equipment Z escapes the wall-front Y-sort domain and appears through walls.
		var layers := {
			&"helmet_back": worn_helmet_back_sprite,
			EquipmentRules.ACTOR_VISUAL_BODY_LAYER: sprite,
			EquipmentRules.ACTOR_VISUAL_HAIR_LAYER: worn_hair_sprite,
			EquipmentRules.ACTOR_VISUAL_WEAPON_LAYER: worn_weapon_sprite,
			EquipmentRules.ACTOR_VISUAL_HELMET_LAYER: worn_helmet_sprite,
			&"head_occlusion_mask": head_occlusion_mask_sprite,
		}
		var layer_order: Array[StringName]
		if EquipmentRules.weapon_draws_behind_actor(current_direction):
			layer_order = [
				EquipmentRules.ACTOR_VISUAL_WEAPON_LAYER,
				&"helmet_back",
				EquipmentRules.ACTOR_VISUAL_BODY_LAYER,
				EquipmentRules.ACTOR_VISUAL_HAIR_LAYER,
				EquipmentRules.ACTOR_VISUAL_HELMET_LAYER,
				&"head_occlusion_mask",
			]
		else:
			layer_order = [
				&"helmet_back",
				EquipmentRules.ACTOR_VISUAL_BODY_LAYER,
				EquipmentRules.ACTOR_VISUAL_HAIR_LAYER,
				EquipmentRules.ACTOR_VISUAL_WEAPON_LAYER,
				EquipmentRules.ACTOR_VISUAL_HELMET_LAYER,
				&"head_occlusion_mask",
			]
		for layer_index: int in range(layer_order.size()):
			move_child(layers[layer_order[layer_index]], layer_index)
		_equipment_layer_direction = current_direction
	# Helmet and body use the same 192x160 directional atlas grid.  Its region
	# is updated with the body each frame, so it stays on the actual head rather
	# than becoming an independent icon beside the health bar.


func weapon_draws_behind(direction_row: int) -> bool:
	return EquipmentRules.weapon_draws_behind_actor(direction_row)


func _on_database_reloaded() -> void:
	_refresh_equipment_visuals()


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


func _update_passive_proc_effect(delta: float) -> void:
	if passive_proc_effect_sprite == null:
		return
	_passive_proc_effect_remaining = maxf(
		0.0,
		_passive_proc_effect_remaining - delta
	)
	var active := (
		_passive_proc_effect_remaining > 0.0
		and CLIENT_EFFECTS.has(_passive_proc_effect_name)
	)
	passive_proc_effect_sprite.visible = active
	if not active:
		_passive_proc_effect_name = ""
		return
	var effect: Dictionary = CLIENT_EFFECTS[_passive_proc_effect_name]
	var cell: Vector2i = effect.get("cell", Vector2i.ZERO)
	if cell == Vector2i.ZERO or effect.get("assets", []).size() > 0:
		passive_proc_effect_sprite.visible = false
		return
	var progress := clampf(
		1.0 - _passive_proc_effect_remaining / _passive_proc_effect_duration,
		0.0,
		0.999
	)
	var frame_count := 6
	var effect_frame := mini(frame_count - 1, int(floor(progress * frame_count)))
	passive_proc_effect_sprite.texture = PresentationAssets.effect_texture(
		str(effect.get("asset", ""))
	)
	passive_proc_effect_sprite.region_rect = Rect2(
		Vector2(effect_frame * cell.x, current_direction * cell.y),
		Vector2(cell)
	)
	passive_proc_effect_sprite.position = (
		-Vector2(effect.get("origin", Vector2i.ZERO))
		+ CLIENT_EFFECT_ACTOR_OFFSET
	)
	passive_proc_effect_sprite.modulate = Color.WHITE


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
	_dispatch_audited_action_audio()
	if SKILL_AUDIO_ENABLED:
		weapon_audio.play()
	else:
		# Keep the selected stream observable for existing visual contracts, but
		# never start playback until the temporary gate is explicitly reopened.
		weapon_audio.stop()


func _dispatch_player_reaction_action_start_audio(animation_name: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var service := tree.get_first_node_in_group("audio_runtime_service")
	if service == null or not service.has_method("play_event"):
		return
	var context := {
		"gender": PlayerState.gender,
		"action_name": animation_name,
		"source": "player_visual.reaction_action_start",
	}
	match animation_name:
		"hit":
			# Current PvE has non-human attackers. Primary Actor.pas keeps its
			# initialized body-longstick contact and then plays the sex voice.
			service.call("play_event", "player.hurt.pve.body", context)
			service.call("play_event", "player.hurt.voice", context)
		"death":
			# Do not start source game-over music: the user-authorized town BGM
			# survives map/death transitions and has precedence in HardCore.
			service.call("play_event", "player.death.voice", context)


func _dispatch_audited_action_audio() -> void:
	# MirClient's rush action has no dedicated weapon/skill PlaySound call.
	# Do not borrow the adjacent attack samples merely because this visual uses
	# the shared attack atlas.
	if _action_name in ["野蛮冲撞", "烈火蓄力"]:
		return
	var tree := get_tree()
	if tree == null:
		return
	var service := tree.get_first_node_in_group("audio_runtime_service")
	if service == null or not service.has_method("play_event"):
		return
	var context := {
		"gender": PlayerState.gender,
		"action_name": _action_name,
		"source": "player_visual.client_effect_frame",
	}
	var weapon_event_id := _weapon_audio_event_id()
	if not weapon_event_id.is_empty():
		service.call("play_event", weapon_event_id, context)
	var skill_event_id := str({
		"攻杀剑术": "player.skill.slaying",
		"刺杀剑术": "player.skill.thrusting",
		"半月弯刀": "player.skill.half_moon",
		"烈火剑法": "player.skill.fire_sword",
	}.get(_action_name, ""))
	if not skill_event_id.is_empty():
		service.call("play_event", skill_event_id, context)


func audio_classic_weapon_shape() -> int:
	var weapon := _equipped_record("武器")
	if weapon.is_empty():
		return 0
	return _audio_classic_weapon_shape_for_record(weapon)


func _audio_classic_weapon_shape_for_record(weapon: Dictionary) -> int:
	var stable_item_id := _audio_stable_equipped_item_id(weapon)
	if stable_item_id < 0:
		return -1
	var formal_items: Variant = GameData.equipment_visual_catalog.get("itemsById", {})
	if not formal_items is Dictionary:
		return -1
	var formal_item: Variant = formal_items.get(str(stable_item_id), {})
	if not formal_item is Dictionary:
		return -1
	var world_wear: Variant = formal_item.get("worldWear", {})
	if not world_wear is Dictionary or not world_wear.has("shape"):
		return -1
	return int(world_wear.get("shape", -1))


func _weapon_audio_event_id() -> String:
	var weapon := _equipped_record("武器")
	if weapon.is_empty():
		return "player.weapon.fist.swing"
	# MirClient selects the attack sample from (m_btWeapon div 2), not from
	# the item display name. Resolve the current stable item ID to the formal
	# classic weapon shape already used by world-wear rendering; an old
	# name-only/unknown equipped record stays silent instead of guessing.
	var classic_shape := _audio_classic_weapon_shape_for_record(weapon)
	if classic_shape < 0:
		return ""
	if classic_shape in [6, 20]:
		return "player.weapon.short.swing"
	if classic_shape == 1:
		return "player.weapon.wood.swing"
	if classic_shape in [2, 5, 9, 13, 14, 22]:
		return "player.weapon.sword.swing"
	if classic_shape in [4, 10, 15, 16, 17, 23]:
		return "player.weapon.blade.swing"
	if classic_shape in [3, 7, 11]:
		return "player.weapon.axe.swing"
	if classic_shape == 24:
		return "player.weapon.club.swing"
	if classic_shape in [8, 12, 18, 21]:
		return "player.weapon.long.swing"
	return ""


func _audio_stable_equipped_item_id(record: Dictionary) -> int:
	for field_name: String in ["item_id", "itemId"]:
		var raw_id: Variant = record.get(field_name, null)
		if raw_id is int or raw_id is float:
			var numeric_id := int(raw_id)
			if numeric_id >= 0:
				return numeric_id
		var text_id := str(raw_id)
		if text_id.is_valid_int() and text_id.to_int() >= 0:
			return text_id.to_int()
	return -1


func _weapon_swing_stream() -> AudioStream:
	var weapon := _equipped_record("武器")
	if weapon.is_empty():
		return PresentationAssets.audio("fist")
	if "木剑" in str(weapon.get("name", "")):
		return PresentationAssets.audio("wood")
	return PresentationAssets.audio("sword")
