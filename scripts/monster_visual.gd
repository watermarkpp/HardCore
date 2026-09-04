class_name MonsterVisual
extends Node2D

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const OVERHEAD_ANCHOR_DATA_PATH := "res://assets/data/runtime/monster_overhead_anchors.json"
const GROUND_CONTACT_DATA_PATH := "res://assets/data/runtime/monster_ground_contacts.json"
const MANUAL_ALIGNMENT_DATA_PATH := (
	"res://assets/data/runtime/monster_ground_alignment_manual_v1.json"
)
# The frozen manual drafts were authored in the original acceptance lab at its
# default 3x preview zoom. EnemyActor's overlap guard moved the co-located
# preview monster toward S by one collision-safe distance in global pixels; the
# scaled preview root converted that into this smaller local visual offset.
# Reapply that historical presentation displacement at runtime, then remove it
# from the visual-foot vector, so the sprite matches the authored preview while
# the canonical actor/targeting foot remains exactly (0,0).
const MANUAL_ALIGNMENT_PREVIEW_ZOOM := 3.0
const MANUAL_ALIGNMENT_SPAWN_GAP := 14.0
# WIL px/py values are relative to the classic DrawChr origin, not to the
# actor's ground point. The player client-art path already migrates this same
# origin by (+32,+28); monsters must use the identical coordinate conversion.
const CLIENT_ACTOR_GROUND_OFFSET := Vector2i(32, 28)
const HEALTH_BAR_BODY_GAP := 8.0
const CLIENT_RESOURCE_CACHE_CAPACITY := 12
## Compatibility name retained for callers; this is decoded RGBA8 residency
## (four bytes per pixel across all five action atlases), not ETC2 bytes.
const CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES := 64 * 1024 * 1024
const CLIENT_RESOURCE_CACHE_BUDGET_BYTES := CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES
const RESOURCE_RESIDENCY_CONTRACT_ID := "monster.visual.resource_residency.screen_px.v1"
## Viewport-space guard margins. They include the largest reviewed monster
## footprint plus more than half a second of camera travel, while avoiding the
## old 1600/2000 world-radius lease around every off-screen spawn.
const VISUAL_ACTIVATION_DISTANCE_PX := 320.0
const VISUAL_RELEASE_DISTANCE_PX := 640.0
const RESOURCE_RESIDENCY_CHECK_SECONDS := 0.12
const MOVEMENT_ANIMATION_MIN_SPEED_GU_PER_SEC := 5.0 / 32.0
const DEATH_ANIMATION_FPS := 12.0
const MAX_CONCURRENT_PROFILE_LOADS := 2
const ACTOR_Y_SORT_RENDER_DOMAIN := "actor_y_sort"
const ACTOR_Y_SORT_RENDER_CONTRACT := "monster.actor_y_sort.v1"
const OVERHEAD_ANCHOR_CONTRACT := "monster.overhead_anchor.v4"
const GROUND_CONTACT_CONTRACT := "monster.ground_contact.v5"
const MANUAL_ALIGNMENT_REPLAY_CONTRACT := (
	"monster.ground_alignment.manual_replay.v1"
)
const GROUND_SHADOW_MODE_AUTHORED_CAST_WITH_CONTACT_CORE := (
	"authored_cast_with_contact_core"
)
const GROUND_SHADOW_MODE_PROCEDURAL_FALLBACK := "procedural_fallback"
const GROUND_SHADOW_MODE_HIDDEN_PENDING_ART := "hidden_pending_art"
const CONTACT_CORE_RADIUS_SCALE := 0.42
const CONTACT_CORE_ALPHA_GROUNDED := 0.24
const CONTACT_CORE_ALPHA_AIRBORNE := 0.18

static var _overhead_anchor_data: Dictionary = {}
static var _ground_contact_data: Dictionary = {}
static var _manual_alignment_data: Dictionary = {}
static var _client_texture_load_request_count := 0
static var _synchronous_loading_for_tests := true
## Q2-D: single streaming coordinator owned by GameRoot. The static pointer is
## the access path only - there is exactly one coordinator instance and no
## second cache truth. MonsterVisual instances register needs and keep their
## own animation; the coordinator owns the global poll.
static var _streaming_coordinator

var actor: EnemyActor
var sprite: Sprite2D
var active_resources: Dictionary = {}
var current_state := "idle"
var current_direction := 0
var current_frame := 0
var frame_size := ArtSpec.MONSTER_FRAME
var foot_anchor := ArtSpec.MONSTER_FOOT_ANCHOR
var actor_ground_offset := Vector2i.ZERO
var health_bar_top_by_direction: Array = []
var ground_contact_profile: Dictionary = {}
var _has_authored_client_art := false
var _elapsed := 0.0
var _last_state := ""
var _attack_remaining := 0.0
var _hit_remaining := 0.0
var _death_remaining := 0.0
var _death_pose_held := false
var _action_duration := 0.0
var _fixed_health_bar_y := 0.0
var _render_state_update_count := 0
var _resource_residency_timer := 0.0
var _residency_wakeup_timer: Timer
var _inactive_action_last_tick_msec := 0
var _streaming_resource_key := ""
var _streaming_world_generation := -1
var _last_ground_contact_position := Vector2.INF
var _last_ground_indicator_radii := Vector2.INF


static func configure_actor_y_sort_item(item: CanvasItem, role: String) -> void:
	# Keep the complete monster composite under EnemyActor's GameRoot Y-sort key.
	item.z_index = 0
	item.z_as_relative = true
	item.y_sort_enabled = false
	item.show_behind_parent = false
	item.set_as_top_level(false)
	item.set_meta("monster_render_domain", ACTOR_Y_SORT_RENDER_DOMAIN)
	item.set_meta("monster_render_contract", ACTOR_Y_SORT_RENDER_CONTRACT)
	item.set_meta("monster_render_role", role)


func setup(owner_actor: EnemyActor) -> void:
	actor = owner_actor


func _ready() -> void:
	configure_actor_y_sort_item(self, "visual_root")
	_has_authored_client_art = not _client_mapping_for(actor.monster_data).is_empty()
	# 普通怪下沉4px，Boss下沉6px，使脚底与阴影中心实际重叠。
	position = _runtime_visual_origin()
	visible = false
	sprite = Sprite2D.new()
	sprite.name = "BodySprite"
	configure_actor_y_sort_item(sprite, "body_sprite")
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.centered = false
	sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	# Procedural setup is replaced by the per-monster stable body crown as soon
	# as final client art activates. Never derive overhead position from the
	# current animation frame: that would reintroduce pose/direction jitter.
	_fixed_health_bar_y = position.y + sprite.position.y
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	# Production residency is scheduled centrally by the streaming coordinator.
	# Isolated visual fixtures retain one local fallback timer.
	if _streaming_coordinator == null or not is_instance_valid(_streaming_coordinator):
		_residency_wakeup_timer = Timer.new()
		_residency_wakeup_timer.name = "ResidencyWakeupTimer"
		_residency_wakeup_timer.wait_time = RESOURCE_RESIDENCY_CHECK_SECONDS
		_residency_wakeup_timer.one_shot = true
		_residency_wakeup_timer.timeout.connect(_on_residency_wakeup_timeout)
		add_child(_residency_wakeup_timer)
	_resource_residency_timer = RESOURCE_RESIDENCY_CHECK_SECONDS * float(posmod(get_instance_id(), 7)) / 7.0
	# Registration is the R state only. Declare an actual W demand from
	# _activate_resources after this subscription exists, so a near visual
	# cannot miss its first protection window.
	_register_with_streaming_coordinator()
	if _inside_visual_distance_px(VISUAL_ACTIVATION_DISTANCE_PX):
		_activate_resources()
	_sync_process_tier()


func _exit_tree() -> void:
	var coordinator = _streaming_coordinator
	if coordinator != null and is_instance_valid(coordinator):
		coordinator.release_visual_resource(get_instance_id(), _streaming_resource_key)
		coordinator.unregister_visual(get_instance_id())


func _register_with_streaming_coordinator() -> void:
	var coordinator = _streaming_coordinator
	if coordinator == null or not is_instance_valid(coordinator):
		return
	var mapping := _client_mapping_for(actor.monster_data)
	if mapping.is_empty():
		# Keep the lifecycle in R even for a procedural/unmapped visual. It has no
		# resource key and therefore cannot become a waiter, but it still needs a
		# generation-safe unregister on teardown.
		coordinator.register_visual(
			self,
			actor.monster_id,
			actor.runtime_map_id,
			coordinator.current_world_generation(),
			"",
			{},
			int(actor.get_meta("spawn_serial", actor.get_instance_id()))
		)
		_streaming_world_generation = coordinator.current_world_generation()
		return
	coordinator.register_visual(
		self,
		actor.monster_id,
		actor.runtime_map_id,
		coordinator.current_world_generation(),
		_client_resource_cache_key(mapping),
		_client_resource_paths(mapping),
		int(actor.get_meta("spawn_serial", actor.get_instance_id()))
	)
	_streaming_resource_key = _client_resource_cache_key(mapping)
	_streaming_world_generation = coordinator.current_world_generation()


static func set_streaming_coordinator(
	coordinator
) -> void:
	_streaming_coordinator = coordinator


static func streaming_coordinator():
	return _streaming_coordinator


func _client_resource_paths(client_mapping: Dictionary) -> Dictionary:
	var actions: Variant = client_mapping.get("actions", {})
	var paths := {}
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = (
			actions.get(action_name, {})
			if actions is Dictionary
			else {}
		)
		paths[action_name] = str(action.get("path", ""))
	return paths


func _draw() -> void:
	# Final WIL art owns the cast shadow. Keep its contact core and the optional
	# target ring in this same CanvasItem and derive both from one reviewed foot.
	if not is_instance_valid(actor) or not uses_final_art() or actor._burrowed:
		return
	var center := target_ring_local_position()
	var radii := ground_indicator_radii(Vector2.ZERO)
	_draw_contact_core(center, radii)
	if actor._dying or not actor.is_targeted:
		return
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center
			+ Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		)
	draw_polyline(points, Color(1.0, 0.78, 0.18, 0.78), 2.0, true)


func _draw_contact_core(center: Vector2, radii: Vector2) -> void:
	var scale := CONTACT_CORE_RADIUS_SCALE
	var points := PackedVector2Array()
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		points.append(
			center
			+ Vector2(cos(angle) * radii.x * scale, sin(angle) * radii.y * scale)
		)
	var alpha := (
		CONTACT_CORE_ALPHA_AIRBORNE
		if ground_projection_strategy() in ["flying", "hover"]
		else CONTACT_CORE_ALPHA_GROUNDED
	)
	draw_colored_polygon(points, Color(0.05, 0.04, 0.03, alpha))


func ground_shadow_layout_snapshot() -> Dictionary:
	var final_art := uses_final_art()
	var pending_art := _has_authored_client_art and active_resources.is_empty()
	var mode := GROUND_SHADOW_MODE_HIDDEN_PENDING_ART
	var owner := "none"
	var draw_contact_core := false
	if final_art:
		mode = GROUND_SHADOW_MODE_AUTHORED_CAST_WITH_CONTACT_CORE
		owner = "monster_visual"
		draw_contact_core = not actor._burrowed
	elif not _has_authored_client_art:
		mode = GROUND_SHADOW_MODE_PROCEDURAL_FALLBACK
		owner = "enemy"
	return {
		"contract_id": "monster.ground_shadow.contact_core.v1",
		"mode": mode,
		"owner": owner,
		"contact_center_local": actor.ground_indicator_center(),
		"actor_local_center": actor.ground_indicator_center(),
		"ring_center_local": actor.ground_indicator_center(),
		"visual_center_local": target_ring_local_position(),
		"radii": ground_indicator_radii(Vector2.ZERO),
		"draw_contact_core": draw_contact_core,
		"pending_authored_art": pending_art,
		"ring_visible": final_art and not actor._dying and actor.is_targeted,
	}


func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	_advance_action_timers(delta)
	if _streaming_coordinator == null or not is_instance_valid(_streaming_coordinator):
		_resource_residency_timer -= delta
		if _resource_residency_timer <= 0.0:
			_resource_residency_timer = RESOURCE_RESIDENCY_CHECK_SECONDS
			_update_resource_residency()
	if active_resources.is_empty() or not visible:
		return
	_update_animation_frame(delta)


func _advance_action_timers(delta: float) -> void:
	var death_was_playing := _death_remaining > 0.0
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	_hit_remaining = maxf(0.0, _hit_remaining - delta)
	_death_remaining = maxf(0.0, _death_remaining - delta)
	if death_was_playing and _death_remaining <= 0.0 and actor._dying:
		# Keep the final frame continuously. The owner timer later extends this as
		# the corpse hold; there must never be a one-frame idle flash in between.
		_death_pose_held = true


func _update_resource_residency() -> void:
	if active_resources.is_empty():
		if _inside_visual_distance_px(VISUAL_ACTIVATION_DISTANCE_PX):
			_activate_resources()
	elif not _inside_visual_distance_px(VISUAL_RELEASE_DISTANCE_PX):
		_release_resources()


func _update_animation_frame(delta: float) -> void:
	if _death_remaining > 0.0 or _death_pose_held:
		current_state = "death"
	elif _attack_remaining > 0.0:
		current_state = "attack"
	elif _hit_remaining > 0.0:
		current_state = "hit"
	elif (
		actor.ground_velocity_gu_per_sec().length_squared()
		> MOVEMENT_ANIMATION_MIN_SPEED_GU_PER_SEC * MOVEMENT_ANIMATION_MIN_SPEED_GU_PER_SEC
	):
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
	if _death_pose_held and current_state == "death":
		current_frame = maxi(0, frame_count - 1)
	elif current_state in ["attack", "hit", "death"]:
		var progress := clampf(_elapsed / maxf(_action_duration, 0.001), 0.0, 0.999)
		current_frame = mini(frame_count - 1, int(floor(progress * frame_count)))
	else:
		var fps := MonsterAnimationPolicy.loop_fps(StringName(current_state))
		current_frame = int(floor(_elapsed * fps)) % frame_count
	var next_region := Rect2(current_frame * frame_size.x, current_direction * frame_size.y, frame_size.x, frame_size.y)
	if sprite.texture != active_resources[current_state] or sprite.region_rect != next_region:
		_apply_render_state(active_resources[current_state], next_region)


func _inside_visual_distance_px(distance_px: float) -> bool:
	if not is_instance_valid(actor):
		return true
	var viewport := get_viewport()
	if viewport == null or not actor.is_inside_tree():
		return true
	# Rendering residency follows the actual camera/canvas rectangle. A grown
	# viewport retains every on-screen or soon-to-enter monster irrespective of
	# device aspect ratio; it is deliberately unrelated to combat Ground GU.
	var actor_viewport_position := actor.get_global_transform_with_canvas().origin
	return viewport.get_visible_rect().grow(maxf(0.0, distance_px)).has_point(
		actor_viewport_position
	)


func _on_residency_wakeup_timeout() -> void:
	streaming_residency_poll(Time.get_ticks_msec())
	if (
		_residency_wakeup_timer != null
		and not is_processing()
		and _residency_wakeup_timer.is_stopped()
	):
		_residency_wakeup_timer.start(RESOURCE_RESIDENCY_CHECK_SECONDS)


func streaming_residency_poll(now_msec: int) -> void:
	if not is_instance_valid(actor):
		return
	if not is_processing():
		var elapsed_seconds := RESOURCE_RESIDENCY_CHECK_SECONDS
		if _inactive_action_last_tick_msec > 0:
			elapsed_seconds = clampf(
				float(maxi(1, now_msec - _inactive_action_last_tick_msec)) / 1000.0,
				1.0 / 120.0,
				2.0,
			)
		_advance_action_timers(elapsed_seconds)
		_inactive_action_last_tick_msec = now_msec
	_update_resource_residency()


func _sync_process_tier() -> void:
	var needs_frame_process := (
		not _has_authored_client_art
		or not active_resources.is_empty()
	)
	set_process(needs_frame_process)
	if needs_frame_process:
		_inactive_action_last_tick_msec = 0
		if _residency_wakeup_timer != null:
			_residency_wakeup_timer.stop()
	else:
		_inactive_action_last_tick_msec = Time.get_ticks_msec()
		if _residency_wakeup_timer != null:
			var phase_slot := posmod(
				int(actor.get_meta("spawn_serial", get_instance_id())) * 7
				+ actor.monster_id * 11,
				15,
			)
			var stagger := (
				RESOURCE_RESIDENCY_CHECK_SECONDS
				* float(phase_slot + 1)
				/ 15.0
			)
			_residency_wakeup_timer.start(stagger)


func _activate_resources() -> void:
	if not active_resources.is_empty():
		return
	var resources := _resources_for(actor.monster_data)
	if resources.is_empty():
		return
	active_resources = resources
	frame_size = resources.get("frame_size", ArtSpec.MONSTER_FRAME)
	foot_anchor = resources.get("foot_anchor", ArtSpec.MONSTER_FOOT_ANCHOR)
	actor_ground_offset = resources.get("actor_ground_offset", Vector2i.ZERO)
	health_bar_top_by_direction = resources.get("health_bar_top_by_direction", [])
	ground_contact_profile = _ground_contact_profile_for_actor()
	position = reviewed_visual_origin()
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	_fixed_health_bar_y = _stable_overhead_anchor_y()
	visible = not actor._burrowed
	_last_state = ""
	_apply_render_state(active_resources["idle"], Rect2(Vector2.ZERO, frame_size))
	# The coordinator only receives L after the complete profile has been
	# applied. Until this point the explicit W demand remains the eviction guard.
	var coordinator = _streaming_coordinator
	if (
		coordinator != null
		and is_instance_valid(coordinator)
		and not _streaming_resource_key.is_empty()
	):
		coordinator.notify_visual_applied(
			get_instance_id(),
			_streaming_resource_key,
			_streaming_world_generation
		)
	# A cold runtime profile reaches this method after the EnemyActor has already
	# created its overhead. Apply the real texture before asking the actor for its
	# anchor: health_bar_anchor_y() deliberately uses the procedural fallback
	# while no final texture is resident. Refreshing one line earlier therefore
	# left every asynchronously activated monster permanently at that fallback.
	actor.refresh_name_label_position()
	_refresh_actor_ground_indicator()
	_sync_process_tier()


func _release_resources() -> void:
	var coordinator = _streaming_coordinator
	if (
		coordinator != null
		and is_instance_valid(coordinator)
		and not _streaming_resource_key.is_empty()
	):
		coordinator.release_visual_resource(
			get_instance_id(),
			_streaming_resource_key
		)
	_streaming_resource_key = ""
	_streaming_world_generation = -1
	if active_resources.is_empty():
		return
	visible = false
	sprite.texture = null
	active_resources = {}
	ground_contact_profile = {}
	position = _runtime_visual_origin()
	_refresh_actor_ground_indicator()
	_sync_process_tier()


func _resources_for(monster_data: Dictionary) -> Dictionary:
	var client_mapping := _client_mapping_for(monster_data)
	return _client_resources(client_mapping) if not client_mapping.is_empty() else {}


func _client_mapping_for(monster_data: Dictionary) -> Dictionary:
	var monster_id := MonsterIdentityScript.monster_id(monster_data)
	var profile := MonsterIdentityScript.appearance_profile(monster_id)
	if profile.is_empty() or str(profile.get("status", "")) != "formal":
		return {}
	var atlas: Dictionary = profile.get("atlas", {}) if profile.get("atlas", {}) is Dictionary else {}
	var frame_size: Array = atlas.get("frame_size", [160, 160])
	var foot_anchor: Array = atlas.get("foot_anchor", [80, 138])
	if frame_size.size() < 2 or foot_anchor.size() < 2:
		return {}
	var actions: Variant = profile.get("actions", {})
	if not actions is Dictionary:
		return {}
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Variant = actions.get(action_name, {})
		if not action is Dictionary or str(action.get("path", "")).is_empty() or str(action.get("path_sha256", "")).is_empty():
			return {}
	return {
		"appearance_profile_id": str(profile.get("appearance_profile_id", "")),
		"frameSize": frame_size,
		"footAnchor": foot_anchor,
		"healthBarTopByDirection": [],
		"directionPolicy": "mir2_directional",
		"actions": actions,
	}


func ground_contact_offset() -> Vector2:
	var values: Variant = ground_contact_profile.get("ringCenterOffset", [])
	if not values is Array or values.size() < 2:
		return Vector2.ZERO
	var result := Vector2(float(values[0]), float(values[1]))
	if (
		ground_projection_strategy() in ["flying", "hover"]
		and not _manual_alignment_profile_for_actor().is_empty()
	):
		result -= manual_alignment_replay_displacement()
	return result


func visual_root_offset() -> Vector2:
	var values: Variant = ground_contact_profile.get("visualRootOffset", [])
	if not values is Array or values.size() < 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


func reviewed_visual_origin() -> Vector2:
	# The user's draft stores both the runtime origin that was visible while
	# calibrating and the additional drag offset. The generated contact table
	# previously retained only the latter, which silently changed the final
	# sprite origin for drafts whose starting origin was not the generic
	# (0,4)/(0,6). The historical lab also applied a deterministic S overlap
	# displacement to the preview actor. Recompose both immutable manual values
	# and that read-time-only displacement so the game matches what was authored.
	var manual := _manual_alignment_profile_for_actor()
	var runtime_values: Variant = manual.get("runtimeVisualOrigin", [])
	var root_values: Variant = manual.get("visualRootOffset", [])
	if (
		runtime_values is Array
		and runtime_values.size() >= 2
		and root_values is Array
		and root_values.size() >= 2
	):
		return Vector2(
			float(runtime_values[0]) + float(root_values[0]),
			float(runtime_values[1]) + float(root_values[1]),
		) + manual_alignment_replay_displacement()
	return _runtime_visual_origin() + visual_root_offset()


func manual_alignment_replay_displacement() -> Vector2:
	if (
		not is_instance_valid(actor)
		or _manual_alignment_profile_for_actor().is_empty()
	):
		return Vector2.ZERO
	var authored_spawn_distance_px := (
		actor.collision_radius_px
		+ ArtSpec.PLAYER_COLLISION_RADIUS_PX
		+ MANUAL_ALIGNMENT_SPAWN_GAP
	)
	return (
		Vector2.DOWN
		* authored_spawn_distance_px
		/ MANUAL_ALIGNMENT_PREVIEW_ZOOM
	)


func _runtime_visual_origin() -> Vector2:
	if not is_instance_valid(actor):
		return Vector2.ZERO
	return Vector2(0.0, 6.0 if actor.is_boss else 4.0)


func ground_contact_position(fallback: Vector2) -> Vector2:
	if not uses_final_art() or ground_contact_profile.is_empty():
		return fallback
	if ground_projection_strategy() in ["flying", "hover"]:
		return position + ground_contact_offset()
	# Grounded monsters use the user's picked visual foot directly. The formal
	# visual root may move, but root + picked foot remains the actor origin.
	return position + visual_foot_offset()


func target_ring_position(fallback: Vector2) -> Vector2:
	# The yellow ring is a presentation of the user's reviewed visual foot.
	# Grounded manual drafts resolve that point to actor-local (0,0), while
	# flying/hovering profiles retain their authored ground projection.
	return ground_contact_position(fallback)


func target_ring_local_position() -> Vector2:
	if ground_projection_strategy() in ["flying", "hover"]:
		return ground_contact_offset()
	return visual_foot_offset()


func ground_indicator_radii(fallback: Vector2) -> Vector2:
	if is_instance_valid(actor):
		return actor.ground_indicator_radii()
	return fallback


func visual_foot_offset() -> Vector2:
	var manual := _manual_alignment_profile_for_actor()
	var has_manual := not manual.is_empty()
	var values: Variant = (
		manual.get("visualFootOffset", [])
		if has_manual
		else ground_contact_profile.get("visualFootOffset", [])
	)
	if not values is Array or values.size() < 2:
		return Vector2.ZERO
	var result := Vector2(float(values[0]), float(values[1]))
	if has_manual:
		result -= manual_alignment_replay_displacement()
	return result


func ground_projection_strategy() -> String:
	return str(ground_contact_profile.get("projectionStrategy", "grounded"))


func _ground_contact_profile_for_actor() -> Dictionary:
	var manifest := _ground_contact_manifest()
	var monster_key := str(actor.monster_id) if is_instance_valid(actor) else ""
	var profile: Variant = manifest.get("entriesByMonsterId", {}).get(monster_key, {})
	return profile if profile is Dictionary else {}


func _manual_alignment_profile_for_actor() -> Dictionary:
	if not is_instance_valid(actor):
		return {}
	var value: Variant = _manual_alignment_manifest().get(
		"entriesByMonsterId", {}
	).get(str(actor.monster_id), {})
	return value if value is Dictionary else {}


static func _ground_contact_manifest() -> Dictionary:
	if _ground_contact_data.is_empty() and FileAccess.file_exists(GROUND_CONTACT_DATA_PATH):
		var file := FileAccess.open(GROUND_CONTACT_DATA_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_ground_contact_data = parsed if parsed is Dictionary else {}
	return _ground_contact_data


static func _manual_alignment_manifest() -> Dictionary:
	if (
		_manual_alignment_data.is_empty()
		and FileAccess.file_exists(MANUAL_ALIGNMENT_DATA_PATH)
	):
		var file := FileAccess.open(MANUAL_ALIGNMENT_DATA_PATH, FileAccess.READ)
		var parsed: Variant = (
			JSON.parse_string(file.get_as_text()) if file != null else null
		)
		_manual_alignment_data = parsed if parsed is Dictionary else {}
	return _manual_alignment_data


func _refresh_actor_ground_indicator() -> void:
	if not is_instance_valid(actor):
		return
	var next_position := actor.ground_indicator_center()
	var next_radii := actor.ground_indicator_radii()
	if (
		_last_ground_contact_position.is_equal_approx(next_position)
		and _last_ground_indicator_radii.is_equal_approx(next_radii)
	):
		return
	_last_ground_contact_position = next_position
	_last_ground_indicator_radii = next_radii
	# CanvasItem retains the previous _draw command list until queue_redraw().
	# Resource activation/release changes whether the procedural ground shadow
	# is legal even for an unselected actor, so every transition must invalidate
	# that cached list.
	actor.queue_redraw()
	queue_redraw()


func refresh_target_ring() -> void:
	queue_redraw()


func health_bar_anchor_y(fallback_y: float) -> float:
	if not uses_final_art():
		return fallback_y
	return _fixed_health_bar_y


func _stable_overhead_anchor_y() -> float:
	# The checked-in data records one semantic body crown for each monsterId:
	# the topmost visible pixel across every neutral idle frame and direction.
	# Attack weapons, jumps and collapsed death poses are deliberately excluded
	# from body height, while the immutable result remains stable throughout
	# every action/direction/frame at runtime.
	var body_top := stable_body_top()
	return (
		position.y
		+ sprite.position.y
		+ body_top
		- MonsterOverheadScript.HEALTH_BAR_HEIGHT
		- HEALTH_BAR_BODY_GAP
	)


func stable_body_top() -> float:
	var anchors: Dictionary = _overhead_anchor_manifest().get("anchorsByMonsterId", {})
	var entry: Variant = anchors.get(str(actor.monster_id), {}) if is_instance_valid(actor) else {}
	if entry is Dictionary and entry.has("stableBodyTop"):
		return float(entry["stableBodyTop"])
	# Formal art should always resolve through the generated per-ID table. Keep
	# a conservative compatibility fallback for isolated legacy fixtures.
	if not health_bar_top_by_direction.is_empty():
		var top := float(frame_size.y)
		for value: Variant in health_bar_top_by_direction:
			top = minf(top, float(value))
		return top
	return 0.0


static func _overhead_anchor_manifest() -> Dictionary:
	if _overhead_anchor_data.is_empty() and FileAccess.file_exists(OVERHEAD_ANCHOR_DATA_PATH):
		var file := FileAccess.open(OVERHEAD_ANCHOR_DATA_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_overhead_anchor_data = parsed if parsed is Dictionary else {}
	return _overhead_anchor_data


func _direction_row(direction: Vector2) -> int:
	if str(active_resources.get("direction_policy", "mir2_directional")) == "fixed_source_direction":
		return 0
	# Raw Mon*.wil atlases are north-first. Project-authored turnaround atlases
	# are south-first. Every resource declares its convention here instead of
	# forcing one global mapping and breaking half the monster roster.
	return MonsterAnimationPolicy.direction_row(direction, StringName(str(active_resources.get("direction_mode", "logical_south_first"))))


func _client_resources(client_mapping: Dictionary) -> Dictionary:
	var cache_key := _client_resource_cache_key(client_mapping)
	var coordinator = _streaming_coordinator
	if coordinator != null and is_instance_valid(coordinator):
		# The visual must explicitly enter W before reading the cache. R alone is
		# not a permanent waiter, so far-away actors cannot pin every atlas.
		var request_async := not PlayerState.test_mode or not _synchronous_loading_for_tests
		var requested = coordinator.request_visual_resources(
			self,
			client_mapping,
			actor.monster_id if is_instance_valid(actor) else -1,
			request_async
		)
		if requested is Dictionary and not requested.is_empty():
			_streaming_resource_key = cache_key
			_streaming_world_generation = coordinator.current_world_generation()
			return requested
		# A stale subscription is fenced and must never fall through to a
		# synchronous load that could apply a new-map profile to an old actor.
		if not coordinator.visual_subscription_is_current(get_instance_id(), cache_key):
			return {}
		# Unit/asset tests retain their deterministic immediate-load fixture.
		# Runtime activation never enters the sync branch: it queues the five
		# atlases on the threaded loader and keeps the fallback until ready.
		if not PlayerState.test_mode or not _synchronous_loading_for_tests:
			return {}
	elif not PlayerState.test_mode or not _synchronous_loading_for_tests:
		return {}
	_streaming_resource_key = cache_key
	if coordinator != null and is_instance_valid(coordinator):
		_streaming_world_generation = coordinator.current_world_generation()
	return _load_client_profile_synchronously(client_mapping)


func _client_profile_shell(client_mapping: Dictionary) -> Dictionary:
	var actions: Variant = client_mapping.get("actions", {})
	return {
		"frame_size": Vector2i(int(client_mapping.get("frameSize", [160, 160])[0]), int(client_mapping.get("frameSize", [160, 160])[1])),
		"foot_anchor": Vector2i(int(client_mapping.get("footAnchor", [80, 138])[0]), int(client_mapping.get("footAnchor", [80, 138])[1])),
		"actor_ground_offset": CLIENT_ACTOR_GROUND_OFFSET,
		"health_bar_top_by_direction": client_mapping.get("healthBarTopByDirection", []),
		"frame_counts": {},
		"direction_mode": "mir2_north_first",
		"direction_policy": str(client_mapping.get("directionPolicy", "mir2_directional")),
		"animation_source": "classic_client_wil",
	}


func _client_resource_cache_key(client_mapping: Dictionary) -> String:
	var frame_values: Array = client_mapping.get("frameSize", [160, 160])
	var foot_values: Array = client_mapping.get("footAnchor", [80, 138])
	var parts := PackedStringArray([
		"%sx%s" % [int(frame_values[0]), int(frame_values[1])],
		"%s,%s" % [int(foot_values[0]), int(foot_values[1])],
		str(client_mapping.get("directionPolicy", "mir2_directional")),
		str(client_mapping.get("healthBarTopByDirection", [])),
	])
	var actions: Dictionary = client_mapping.get("actions", {})
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = actions.get(action_name, {})
		parts.append(
			"%s:%d"
			% [str(action.get("path", "")), int(action.get("framesPerDirection", 0))]
		)
	return "|".join(parts)


func _load_client_profile_synchronously(client_mapping: Dictionary) -> Dictionary:
	var cache_key := _client_resource_cache_key(client_mapping)
	var actions: Variant = client_mapping.get("actions", {})
	var result := _client_profile_shell(client_mapping)
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
	if not MonsterAnimationPolicy.validate(result).is_empty():
		return {}
	# Keep a bounded strong-reference window across nearby streamed areas. Godot's
	# resource cache may release an atlas after the last actor leaves; this LRU
	# prevents an immediate return from decoding/uploading all five actions again
	# without eventually retaining the entire 214-monster catalog on mobile.
	var coordinator = _streaming_coordinator
	if coordinator != null and is_instance_valid(coordinator):
		coordinator.retain_client_resource_profile(cache_key, result)
	return result


func _apply_render_state(texture: Texture2D, region: Rect2) -> void:
	var changed := false
	if sprite.texture != texture:
		sprite.texture = texture
		changed = true
	if sprite.region_rect != region:
		sprite.region_rect = region
		changed = true
	if changed:
		_render_state_update_count += 1
		_refresh_actor_ground_indicator()


func render_state_update_count() -> int:
	return _render_state_update_count


static func set_synchronous_loading_for_tests(enabled: bool) -> void:
	_synchronous_loading_for_tests = enabled


static func reset_client_resource_cache() -> void:
	_client_texture_load_request_count = 0
	_synchronous_loading_for_tests = true
	_ground_contact_data = {}
	var coordinator = _streaming_coordinator
	if coordinator != null and is_instance_valid(coordinator):
		coordinator.reset_for_tests()


static func client_texture_load_request_count() -> int:
	return _client_texture_load_request_count


func _load_client_texture(path: String, expected_size: Vector2i) -> Texture2D:
	_client_texture_load_request_count += 1
	var coordinator = _streaming_coordinator
	if coordinator != null and is_instance_valid(coordinator):
		# Q2-D: the sync fallback only exists in the deterministic test path;
		# record it so the formal streaming path can prove zero sync loads.
		coordinator.record_sync_load(path)
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


func death_animation_duration() -> float:
	var frame_count := MonsterAnimationPolicy.frame_count(
		active_resources,
		&"death"
	)
	return maxf(0.62, float(maxi(1, frame_count)) / DEATH_ANIMATION_FPS)


func play_death(duration := -1.0) -> float:
	var resolved_duration := (
		death_animation_duration()
		if duration <= 0.0
		else float(duration)
	)
	_death_pose_held = false
	_death_remaining = resolved_duration
	_hit_remaining = 0.0
	_attack_remaining = 0.0
	_action_duration = resolved_duration
	_elapsed = 0.0
	return resolved_duration


func hold_death_pose() -> void:
	if active_resources.is_empty() or not visible:
		return
	_death_remaining = 0.0
	_death_pose_held = true
	current_state = "death"
	_last_state = "death"
	var frame_count := MonsterAnimationPolicy.frame_count(
		active_resources,
		&"death"
	)
	current_frame = maxi(0, frame_count - 1)
	var next_region := Rect2(
		current_frame * frame_size.x,
		current_direction * frame_size.y,
		frame_size.x,
		frame_size.y
	)
	_apply_render_state(active_resources["death"], next_region)


func uses_final_art() -> bool:
	return visible and sprite != null and sprite.texture != null


func has_authored_client_art() -> bool:
	return _has_authored_client_art


func should_draw_procedural_fallback() -> bool:
	# A stable monsterId with authored client art may briefly wait for its
	# threaded atlases. Drawing the old green placeholder during that window
	# makes it look like a ground marker underneath the real monster as the
	# resource becomes resident. Only genuinely unmapped monsters use it.
	return not uses_final_art() and not _has_authored_client_art


func is_fallback_attacking() -> bool:
	return not uses_final_art() and _attack_remaining > 0.0


func fallback_attack_progress() -> float:
	if not is_fallback_attacking() or _action_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _attack_remaining / _action_duration, 0.0, 1.0)


func fallback_lunge_offset_px(direction_px: Vector2) -> Vector2:
	return direction_px.normalized() * sin(fallback_attack_progress() * PI) * 12.0 if is_fallback_attacking() else Vector2.ZERO


func fallback_attack_scale() -> Vector2:
	if not is_fallback_attacking():return Vector2.ONE
	var pulse:=sin(fallback_attack_progress()*PI)
	return Vector2(1.0+0.18*pulse,1.0-0.12*pulse)


func fallback_attack_angle(direction_px: Vector2) -> float:
	if not is_fallback_attacking():return 0.0
	var side:=signf(direction_px.x) if absf(direction_px.x)>0.05 else 1.0
	return side*sin(fallback_attack_progress()*TAU)*0.12
