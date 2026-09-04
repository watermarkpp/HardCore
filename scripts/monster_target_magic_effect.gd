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
var _mage_frames: Array = []
var _priest_cast_frames: Array = []
var _priest_fly_frames: Array = []


static func create_visual(descriptor: Dictionary) -> Node2D:
	var effect := new()
	effect.setup(descriptor)
	return effect


static func presentation_effect_id_for_monster_id(monster_id: int) -> String:
	match monster_id:
		COW_MAGE_ID:
			return COW_MAGE_PRESENTATION_EFFECT_ID
		COW_PRIEST_ID:
			return COW_PRIEST_PRESENTATION_EFFECT_ID
		_:
			return ""


static func source_profile_for_monster_id(monster_id: int) -> Dictionary:
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
	if source_monster_id == COW_MAGE_ID:
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
	z_index = 2
	add_to_group("zone_content")
	queue_redraw()
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
	queue_redraw()
	if _elapsed_seconds >= _duration_seconds:
		_finished = true
		set_process(false)
		playback_finished.emit(self)
		queue_free()


func _draw() -> void:
	if not visible or _duration_seconds <= 0.0:
		return
	if source_monster_id == COW_MAGE_ID:
		_draw_mage_thunder()
	elif source_monster_id == COW_PRIEST_ID:
		_draw_priest_magic()


func _draw_mage_thunder() -> void:
	if _elapsed_seconds < CLIENT_MAGIC_RELEASE_SECONDS:
		return
	var thunder_elapsed := _elapsed_seconds - CLIENT_MAGIC_RELEASE_SECONDS
	var frame_index := mini(
		_mage_frames.size() - 1,
		int(floor(thunder_elapsed / MAGE_FRAME_SECONDS)),
	)
	_draw_source_frame(
		MAGE_THUNDER_TEXTURE,
		_mage_frames[frame_index],
		CLIENT_MAGIC_DRAW_OFFSET,
	)


func _draw_priest_magic() -> void:
	var cast_frame := mini(5, int(floor(_elapsed_seconds / PRIEST_CAST_FRAME_SECONDS)))
	var cast_record_index := source_direction8 * 6 + cast_frame
	var source_relative := source_world_px - target_world_px
	_draw_source_frame(
		PRIEST_CAST_TEXTURE,
		_priest_cast_frames[cast_record_index],
		source_relative,
	)
	if _elapsed_seconds < CLIENT_MAGIC_RELEASE_SECONDS:
		return
	if _fly_blocked_by_world:
		return
	var fly_elapsed := _elapsed_seconds - CLIENT_MAGIC_RELEASE_SECONDS
	if fly_elapsed > _fly_duration_seconds:
		return
	var fly_frame := int(floor(fly_elapsed / PRIEST_FLY_FRAME_SECONDS)) % 6
	var fly_record_index := fly_direction16 * 6 + fly_frame
	var fly_progress := clampf(
		fly_elapsed / maxf(_fly_duration_seconds, PRIEST_FLY_FRAME_SECONDS),
		0.0,
		1.0,
	)
	_draw_source_frame(
		PRIEST_FLY_TEXTURE,
		_priest_fly_frames[fly_record_index],
		source_relative.lerp(Vector2.ZERO, fly_progress) + CLIENT_MAGIC_DRAW_OFFSET,
	)


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


func _draw_source_frame(texture: Texture2D, frame: Dictionary, anchor: Vector2) -> void:
	var region_values: Array = frame.get("atlas_region", [])
	var offset_values: Array = frame.get("source_offset", [])
	if region_values.size() != 4 or offset_values.size() != 2:
		return
	var source_region := Rect2(
		float(region_values[0]),
		float(region_values[1]),
		float(region_values[2]),
		float(region_values[3]),
	)
	var destination := Rect2(
		anchor + Vector2(float(offset_values[0]), float(offset_values[1])),
		source_region.size,
	)
	draw_texture_rect_region(texture, destination, source_region)


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
		"visual_source_manifest": SOURCE_MANIFEST_PATH,
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
