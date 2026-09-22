class_name MonsterTargetMagicEffect
extends Node2D

## Presentation-only Race 200 monster magic. EnemyActor owns the immutable
## release snapshot, delayed magic-defense transaction, and collision gate.
## This node selects the exact source-policy-compliant client presentation by
## monster_id. Magic/Magic2 resolve from primary; Mon21 is an evidenced fallback.

const EFFECT_ID := "monster.target_lightning.v1"
const COW_MAGE_PRESENTATION_EFFECT_ID := "monster.cow_mage.thunder.primary.v1"
const COW_PRIEST_PRESENTATION_EFFECT_ID := "monster.cow_priest.fly.primary.v1"
const SOURCE_MANIFEST_PATH := "res://assets/data/monster_target_magic_sources_v1.json"
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const Frames := preload("res://scripts/monster_source_frames.gd")
const RenderOrder := preload("res://scripts/world_effect_render_order.gd")
const COW_KING_ID := 224
const COW_KING_PRESENTATION_EFFECT_ID := "monster.cow_king.mt13.source.v2"
const COW_MAGE_ID := 220
const COW_PRIEST_ID := 222
const MAGE_FRAME_SECONDS := 0.05
const PRIEST_CAST_FRAME_SECONDS := 0.12
const PRIEST_FLY_FRAME_SECONDS := 0.05
const CLIENT_MAGIC_RELEASE_FRAME := 4
const CLIENT_MAGIC_RELEASE_SECONDS := (
	float(CLIENT_MAGIC_RELEASE_FRAME) * PRIEST_CAST_FRAME_SECONDS
)
const PRIEST_FLY_SPEED_PX_PER_SECOND := 500.0
const CLIENT_MAGIC_DRAW_OFFSET := Vector2(-24.0, -16.0)

const MAGE_THUNDER_TEXTURE: Texture2D = preload(
	"res://assets/art/monsters/effects/monster_target_magic/cow_mage_thunder_magic2.png"
)
const PRIEST_CAST_TEXTURE: Texture2D = preload(
	"res://assets/art/monsters/effects/monster_target_magic/cow_priest_cast_wmon21.png"
)
const PRIEST_FLY_TEXTURE: Texture2D = preload(
	"res://assets/art/monsters/effects/monster_target_magic/cow_priest_fly_magic.png"
)

signal playback_finished(effect: Node2D)

static var _source_manifest_cache: Dictionary = {}

var release_descriptor: Dictionary = {}
var release_id := ""
var source_monster_id := -1
var presentation_effect_id := ""
var source_world_px := Vector2.ZERO
var target_world_px := Vector2.ZERO
var source_direction8 := 0
var fly_direction16 := 0
var _elapsed_seconds := 0.0
var _duration_seconds := 0.0
var _fly_duration_seconds := 0.0
var _fly_previous_world_px := Vector2.ZERO
var _fly_blocked_by_world := false
var _finished := false
var _king_frames: Array = []
var _target_sprite: Sprite2D
var _cast_sprite: Sprite2D
var _fly_sprite: Sprite2D
var _mage_frames: Array = []
var _priest_cast_frames: Array = []
var _priest_fly_frames: Array = []


static func create_visual(descriptor: Dictionary) -> Node2D:
	var effect := new()
	effect.setup(descriptor)
	return effect


static func presentation_effect_id_for_monster_id(monster_id: int) -> String:
	match monster_id:
		COW_KING_ID:
			return COW_KING_PRESENTATION_EFFECT_ID
		COW_MAGE_ID:
			return COW_MAGE_PRESENTATION_EFFECT_ID
		COW_PRIEST_ID:
			return COW_PRIEST_PRESENTATION_EFFECT_ID
		_:
			return ""


static func source_profile_for_monster_id(monster_id: int) -> Dictionary:
	if monster_id == COW_KING_ID:
		var king := Frames.profile_for_id(monster_id).duplicate(true)
		king["presentation_effect_id"] = COW_KING_PRESENTATION_EFFECT_ID
		return king
	var effects: Variant = _source_manifest().get("effects_by_monster_id", {})
	if not effects is Dictionary:
		return {}
	var profile: Variant = effects.get(str(monster_id), {})
	return profile.duplicate(true) if profile is Dictionary else {}


func setup(descriptor: Dictionary) -> void:
	release_descriptor = descriptor if descriptor.is_read_only() else descriptor.duplicate(true)
	if not release_descriptor.is_read_only():
		release_descriptor.make_read_only()
	if str(release_descriptor.get("effect_id", "")) != EFFECT_ID:
		_reject_visual()
		return
	source_monster_id = int(release_descriptor.get("source_monster_id", -1))
	presentation_effect_id = presentation_effect_id_for_monster_id(source_monster_id)
	if presentation_effect_id.is_empty():
		# Retired 221/223 and every unresolved caster fail closed. They must not
		# silently inherit either active Race 200 presentation.
		_reject_visual()
		return
	var profile := source_profile_for_monster_id(source_monster_id)
	if (
		profile.is_empty()
		or str(profile.get("presentation_effect_id", "")) != presentation_effect_id
	):
		_reject_visual()
		return
	release_id = str(release_descriptor.get("release_id", ""))
	target_world_px = release_descriptor.get("target_world_px", Vector2.ZERO)
	if not target_world_px.is_finite():
		_reject_visual()
		return
	source_world_px = _resolve_source_world_px(release_descriptor)
	if not source_world_px.is_finite():
		_reject_visual()
		return
	global_position = target_world_px
	_fly_previous_world_px = source_world_px
	var source_to_target := target_world_px - source_world_px
	fly_direction16 = _client_fly_direction16(source_to_target)
	source_direction8 = _resolve_source_direction8(release_descriptor, source_to_target)
	_load_profile_frames(profile)
	if source_monster_id == COW_KING_ID:
		_king_frames = profile.get("frames", [])
		Frames.request_profile(profile)
		_duration_seconds = CLIENT_MAGIC_RELEASE_SECONDS + 0.02 * float(_king_frames.size())
		if _king_frames.size() != 20: _reject_visual()
	elif source_monster_id == COW_MAGE_ID:
		_duration_seconds = (
			CLIENT_MAGIC_RELEASE_SECONDS
			+ MAGE_FRAME_SECONDS * float(_mage_frames.size())
		)
		if _mage_frames.size() != 6:
			_reject_visual()
	elif source_monster_id == COW_PRIEST_ID:
		_fly_duration_seconds = maxf(
			PRIEST_FLY_FRAME_SECONDS,
			source_to_target.length() / PRIEST_FLY_SPEED_PX_PER_SECOND,
		)
		_duration_seconds = maxf(
			PRIEST_CAST_FRAME_SECONDS * 6.0,
			CLIENT_MAGIC_RELEASE_SECONDS + _fly_duration_seconds,
		)
		if _priest_cast_frames.size() != 48 or _priest_fly_frames.size() != 96:
			_reject_visual()


func _ready() -> void:
	z_as_relative = true
	z_index = 0
	add_to_group("zone_content")
	if not visible:
		queue_free()
		return
	_target_sprite = _make_world_sprite("Target")
	if source_monster_id == COW_PRIEST_ID:
		_cast_sprite = _make_world_sprite("Cast")
		_fly_sprite = _make_world_sprite("Fly")
	elif source_monster_id == COW_KING_ID:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_target_sprite.material = additive
	_update_presentation()
	set_process(visible and _duration_seconds > 0.0)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_seconds = minf(
		_duration_seconds,
		_elapsed_seconds + maxf(0.0, delta),
	)
	if source_monster_id == COW_PRIEST_ID:
		_update_priest_fly_world_occlusion()
	_update_presentation()
	if _elapsed_seconds >= _duration_seconds:
		_finished = true
		set_process(false)
		playback_finished.emit(self)
		queue_free()


func _make_world_sprite(label: String) -> Sprite2D:
	var proxy := RenderOrder.create_proxy(self)
	proxy.name = label + "Footpoint"
	var visual := Sprite2D.new()
	visual.name = label + "Frame"
	visual.centered = false
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	proxy.add_child(visual)
	return visual


func _update_presentation() -> void:
	if _target_sprite == null: return
	var released := _elapsed_seconds >= CLIENT_MAGIC_RELEASE_SECONDS
	_target_sprite.visible = released and source_monster_id != COW_PRIEST_ID
	if source_monster_id == COW_MAGE_ID and released:
		var frame := mini(_mage_frames.size() - 1, int((_elapsed_seconds - CLIENT_MAGIC_RELEASE_SECONDS) / MAGE_FRAME_SECONDS))
		_set_atlas_frame(_target_sprite, MAGE_THUNDER_TEXTURE, _mage_frames[frame], Vector2.ZERO, CLIENT_MAGIC_DRAW_OFFSET)
	elif source_monster_id == COW_KING_ID and released:
		var frame := mini(_king_frames.size() - 1, int((_elapsed_seconds - CLIENT_MAGIC_RELEASE_SECONDS) / 0.02))
		var record: Dictionary = _king_frames[frame]
		_target_sprite.texture = Frames.texture(str(record.path))
		_target_sprite.position = Vector2(float(record.x), float(record.y)) + CLIENT_MAGIC_DRAW_OFFSET + Vector2(0, RenderOrder.SORT_EPSILON_PX)
	elif source_monster_id == COW_PRIEST_ID:
		var source_relative := source_world_px - target_world_px
		var cast_frame := mini(5, int(_elapsed_seconds / PRIEST_CAST_FRAME_SECONDS))
		_set_atlas_frame(_cast_sprite, PRIEST_CAST_TEXTURE, _priest_cast_frames[source_direction8 * 6 + cast_frame], source_relative, Vector2.ZERO)
		_cast_sprite.visible = _elapsed_seconds < PRIEST_CAST_FRAME_SECONDS * 6.0
		var fly_elapsed := _elapsed_seconds - CLIENT_MAGIC_RELEASE_SECONDS
		_fly_sprite.visible = released and not _fly_blocked_by_world and fly_elapsed <= _fly_duration_seconds
		if _fly_sprite.visible:
			var frame := int(fly_elapsed / PRIEST_FLY_FRAME_SECONDS) % 6
			var progress := clampf(fly_elapsed / maxf(_fly_duration_seconds, PRIEST_FLY_FRAME_SECONDS), 0.0, 1.0)
			_set_atlas_frame(_fly_sprite, PRIEST_FLY_TEXTURE, _priest_fly_frames[fly_direction16 * 6 + frame], source_relative.lerp(Vector2.ZERO, progress), CLIENT_MAGIC_DRAW_OFFSET)


func _set_atlas_frame(visual: Sprite2D, texture: Texture2D, frame: Dictionary, footpoint: Vector2, origin: Vector2) -> void:
	var region: Array = frame.get("atlas_region", [])
	var hot: Array = frame.get("source_offset", [])
	if region.size() != 4 or hot.size() != 2: return
	visual.texture = texture
	visual.region_enabled = true
	visual.region_filter_clip_enabled = true
	visual.region_rect = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	(visual.get_parent() as Node2D).position = footpoint - Vector2(0, RenderOrder.SORT_EPSILON_PX)
	visual.position = origin + Vector2(float(hot[0]), float(hot[1])) + Vector2(0, RenderOrder.SORT_EPSILON_PX)


func _update_priest_fly_world_occlusion() -> void:
	if _fly_blocked_by_world or _elapsed_seconds < CLIENT_MAGIC_RELEASE_SECONDS:
		return
	var fly_elapsed := _elapsed_seconds - CLIENT_MAGIC_RELEASE_SECONDS
	var fly_progress := clampf(
		fly_elapsed / maxf(_fly_duration_seconds, PRIEST_FLY_FRAME_SECONDS),
		0.0,
		1.0,
	)
	var next_world_px := source_world_px.lerp(target_world_px, fly_progress)
	if not _world_segment_is_clear(_fly_previous_world_px, next_world_px):
		_fly_blocked_by_world = true
		# This node is presentation-only. Stop/hide the mtFly body without
		# changing EnemyActor's immutable delayed damage transaction.
		_duration_seconds = minf(
			_duration_seconds,
			PRIEST_CAST_FRAME_SECONDS * 6.0,
		)
		return
	_fly_previous_world_px = next_world_px


func _world_segment_is_clear(from_world_px: Vector2, to_world_px: Vector2) -> bool:
	if from_world_px.is_equal_approx(to_world_px):
		return true
	var world := get_world_2d()
	if world == null:
		return false
	var physics_space: PhysicsDirectSpaceState2D = world.direct_space_state
	if physics_space == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(
		from_world_px,
		to_world_px,
		WorldSpatialRulesScript.WORLD_MASK,
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	return physics_space.intersect_ray(query).is_empty()


func current_progress() -> float:
	return clampf(_elapsed_seconds / maxf(_duration_seconds, 0.001), 0.0, 1.0)


func visual_descriptor() -> Dictionary:
	var descriptor := {
		"effect_id": EFFECT_ID,
		"presentation_effect_id": presentation_effect_id,
		"release_id": release_id,
		"source_monster_id": source_monster_id,
		"source_world_px": source_world_px,
		"target_world_px": target_world_px,
		"duration_seconds": _duration_seconds,
		"damage_owner": "enemy.target_magic_release",
		"visual_source_manifest": Frames.MANIFEST if source_monster_id == COW_KING_ID else SOURCE_MANIFEST_PATH,
		"background_policy": "transparent_source_policy_compliant_client_frames_only",
		"world_collision_policy": (
			"swept_world_mask_body_and_area"
			if source_monster_id == COW_PRIEST_ID
			else "none_target_anchored_thunder"
		),
		"flight_blocked_by_world": _fly_blocked_by_world,
	}
	descriptor.make_read_only()
	return descriptor


func _load_profile_frames(profile: Dictionary) -> void:
	for asset_value: Variant in profile.get("assets", []):
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		var frames: Variant = asset.get("frames", [])
		if not frames is Array:
			continue
		match str(asset.get("role", "")):
			"target_thunder":
				_mage_frames = frames
			"caster_directional_overlay":
				_priest_cast_frames = frames
			"flying_spell":
				_priest_fly_frames = frames


func _resolve_source_world_px(descriptor: Dictionary) -> Vector2:
	var explicit_value: Variant = descriptor.get("source_world_px", Vector2.INF)
	if explicit_value is Vector2 and (explicit_value as Vector2).is_finite():
		return explicit_value as Vector2
	var source_instance_id := int(descriptor.get("source_instance_id", 0))
	if source_instance_id <= 0:
		return Vector2.INF
	var source: Object = instance_from_id(source_instance_id)
	if source is Node2D:
		return (source as Node2D).global_position
	return Vector2.INF


func _resolve_source_direction8(descriptor: Dictionary, source_to_target: Vector2) -> int:
	var source_instance_id := int(descriptor.get("source_instance_id", 0))
	if source_instance_id > 0:
		var source: Object = instance_from_id(source_instance_id)
		if source != null:
			var visual_value: Variant = source.get("visual")
			if visual_value is Node and is_instance_valid(visual_value):
				var row_value: Variant = (visual_value as Node).get("current_direction")
				if row_value is int:
					return posmod(int(row_value), 8)
	return posmod(int(round(float(_client_fly_direction16(source_to_target)) / 2.0)), 8)


static func _client_fly_direction16(screen_delta: Vector2) -> int:
	var fx := screen_delta.x
	var fy := screen_delta.y
	if is_zero_approx(fx):
		return 0 if fy < 0.0 else 8
	if is_zero_approx(fy):
		return 12 if fx < 0.0 else 4
	var result := 0
	if fx > 0.0 and fy < 0.0:
		result = 4
		if -fy > fx / 4.0: result = 3
		if -fy > fx / 1.9: result = 2
		if -fy > fx * 1.4: result = 1
		if -fy > fx * 4.0: result = 0
	elif fx > 0.0 and fy > 0.0:
		result = 4
		if fy > fx / 4.0: result = 5
		if fy > fx / 1.9: result = 6
		if fy > fx * 1.4: result = 7
		if fy > fx * 4.0: result = 8
	elif fx < 0.0 and fy > 0.0:
		result = 12
		if fy > -fx / 4.0: result = 11
		if fy > -fx / 1.9: result = 10
		if fy > -fx * 1.4: result = 9
		if fy > -fx * 4.0: result = 8
	else:
		result = 12
		if -fy > -fx / 4.0: result = 13
		if -fy > -fx / 1.9: result = 14
		if -fy > -fx * 1.4: result = 15
		if -fy > -fx * 4.0: result = 0
	return result


func _reject_visual() -> void:
	visible = false
	_duration_seconds = 0.0
	set_process(false)


static func _source_manifest() -> Dictionary:
	if not _source_manifest_cache.is_empty():
		return _source_manifest_cache
	if not FileAccess.file_exists(SOURCE_MANIFEST_PATH):
		return {}
	var file := FileAccess.open(SOURCE_MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		_source_manifest_cache = parsed
	return _source_manifest_cache
