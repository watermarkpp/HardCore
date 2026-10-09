class_name MonsterVisual
extends Node2D

const SourceFrames := preload("res://scripts/monster_source_frames.gd")
const AttackOverlay := preload("res://scripts/monster_attack_source_overlay.gd")
const ProjectileVisual := preload("res://scripts/monster_ranged_projectile_effect.gd")

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const MonsterStruckPolicyScript := preload("res://scripts/monster_struck_policy.gd")
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
# R4 T1: strike-phase threshold frozen at action admission from the canonical
# frame metadata; hot/cold resource residency cannot move the boundary.
var _attack_strike_threshold_s := 0.0
var _hit_remaining := 0.0
# R1.2 vanilla presentation FIFO (review closure): struck and attack
# presentation events queue in strict arrival order - exactly the original
# client model where the next action message is consumed only after the
# current action finishes (`while m_nCurrentAction = 0 and GetMessage(@Msg)`).
# Fixed capacity, preallocated packed arrays, O(1) enqueue/dequeue, no
# per-hit Timer/Node/Dictionary allocation. Gameplay authority (_attack_timer,
# pending release records, WalkTick, damage) is untouched by this queue.
const PRESENTATION_QUEUE_CAPACITY := 16

enum PresentationAction {
	STRUCK,
	ATTACK,
}

var _presentation_kind := PackedByteArray()
var _presentation_duration := PackedFloat32Array()
# Legacy field retained for serialized/test compatibility. Authoritative combat
# no longer waits for a movement-step barrier: a struck may begin as soon as
# the committed attack (if any) has finished. Movement is paused by the owner
# for the exact hit-animation slice through advance_struck_action().
var _presentation_step_barrier := PackedInt32Array()
var _presentation_head := 0
var _presentation_tail := 0
var _presentation_count := 0
# R1.3 canonical hit-frame metadata (review closure): the ActStruck frame
# count is appearance metadata from the monster animation catalog, NOT a
# texture-residency state. Cached once at _ready so a struck enqueued during
# cold activation / async streaming / released residency still gets the exact
# vanilla duration (e.g. monster 241 = 6 frames, never the 2-frame fallback).
var _canonical_struck_frame_count := 2
# Acceleration/diagnostic counter only: the number of struck events WAITING
# in the queue (the playing struck is dequeued first). It drives the vanilla
# backlog 1.5x playback speed; it NEVER decides the action order anymore.
var _pending_struck_count := 0
# HC-MONSTER-COMBAT-R1 Task 3: presentation-side identity of the critical
# attack currently owning the body. Purely diagnostic (no gameplay reads).
var _attack_action_serial := 0
# HC-MONSTER-COMBAT-R2 T3: the attack presentation is bound to the LOGIC
# release that started it - the enemy allocates the parent action id and its
# logic start timestamp at the same tick that commits the damage release, and
# the visual replays that exact action. The presentation age is consumed from
# the action's own start timestamp (logic clock), never by subtracting one
# whole render delta that may predate the attack start.
var _attack_action_id := -1
var _attack_logic_started_at_ms := -1
var _attack_started_at_ms := 0
var _attack_facing_at_commit := Vector2.INF
# Injectable monotonic millisecond clock (test seam). Production keeps the
# engine clock; tests drive a fake clock to reproduce cross-frame boundaries.
var _clock_ms: Callable = Callable()
# HC-MONSTER-COMBAT-R3 W1: the production combat clock seam. The owning
# EnemyActor binds this to its single game-time getter (seconds, advanced
# only by the Actor's own physics update - pause freezes it, engine time
# scaling is already inside the delta). When bound, the attack age is
# `owner_game_time - action_start_game_time`; the wall clock is never
# consulted for production combat timing. Unbound => legacy preview path.
var _combat_clock_s: Callable = Callable()
var _attack_action_start_game_time_s := -1.0
var _motion_overridden_attack_action_id := -1
var _attack_overlay_node: Node = null
var _death_remaining := 0.0
var _death_pose_held := false
var _action_duration := 0.0
var _hc_m30_attack_duration: float = 0.46
var _hc_m30_hit_duration: float = 0.22
var _hc_m30_death_duration: float = 0.62
var _hc_m30_last_geometry_origin: Vector2 = Vector2.INF
var _hc_m30_last_geometry_radius: float = -1.0
var _hc_m30_last_geometry_radius_px: float = -1.0
var _fixed_health_bar_y := 0.0
var _render_state_update_count := 0
var _resource_residency_timer := 0.0
var _residency_wakeup_timer: Timer
var _inactive_action_last_tick_msec := 0
var _streaming_resource_key := ""
var _streaming_world_generation := -1
var _last_ground_contact_position := Vector2.INF
var _last_ground_indicator_radii := Vector2.INF
var _selection_ring_direction_offsets: Dictionary = {}
var _selection_ring_offset := Vector2.ZERO


func _init() -> void:
	# Preallocate the presentation FIFO once per visual (16 bytes + 16 floats
	# + 16 ints for the movement-step barriers).
	_presentation_kind.resize(PRESENTATION_QUEUE_CAPACITY)
	_presentation_duration.resize(PRESENTATION_QUEUE_CAPACITY)
	_presentation_step_barrier.resize(PRESENTATION_QUEUE_CAPACITY)


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
	_selection_ring_direction_offsets = actor.MonsterTargetRingGeometryScript.direction_offsets(actor.monster_id)
	_selection_ring_offset = Vector2.ZERO


func _ready() -> void:
	configure_actor_y_sort_item(self, "visual_root")
	_has_authored_client_art = not _client_mapping_for(actor.monster_data).is_empty()
	# Canonical struck frame count is resolved once from appearance metadata.
	_canonical_struck_frame_count = _load_canonical_struck_frame_count(actor.monster_id)
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
	# Enlarging a visible selection ring must not enlarge the contact shadow.
	_draw_contact_core(center, actor.ground_footprint_indicator_radii())
	if actor._dying or not actor.is_targeted:
		return
	center = selection_ring_local_position()
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center
			+ Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		)
	draw_polyline(points, Color(1.0, 0.78, 0.18, 0.78), 2.0, true)


func refresh_selection_ring_direction() -> void:
	if _selection_ring_direction_offsets.is_empty():
		return
	var offset: Vector2 = _selection_ring_direction_offsets.get(current_direction, Vector2.ZERO)
	if offset != _selection_ring_offset:
		_selection_ring_offset = offset
		if actor.is_targeted:
			queue_redraw()


func selection_ring_direction_offset() -> Vector2:
	return _selection_ring_offset


func selection_ring_local_position() -> Vector2:
	# Only the selected outline receives reviewed directional presentation offsets.
	# The authored foot, contact shadow and gameplay origin remain fixed.
	return target_ring_local_position() + _selection_ring_offset


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
	RuntimeDiagnostics.increment_performance_counter(&"visual_animation_updates")
	_update_animation_frame(delta)


func _advance_action_timers(delta: float) -> void:
	var death_was_playing := _death_remaining > 0.0
	# HC-MONSTER-COMBAT-R2 T3: the attack presentation consumes its OWN age.
	# The render delta may span time before the attack started (for example a
	# 0.50 s frame that contains a 0.46 s attack that began 0.01 s before the
	# draw); subtracting that whole delta from a fresh action zeroed it. The
	# attack's remaining time is `duration - age(now - action start)` instead.
	if _attack_remaining > 0.0:
		if _motion_overridden_attack_action_id == _attack_action_id:
			_attack_remaining = 0.0
		else:
			_attack_remaining = maxf(
				0.0,
				_hc_m30_attack_duration - _attack_age_seconds()
			)
	# Production struck time is owned by EnemyActor's physics clock. Rendering
	# may be throttled or absent, so it must never consume the authoritative hit
	# interval or start a queued event. The unbound path remains for previews and
	# isolated visual fixtures.
	if not _combat_clock_s.is_valid():
		_hit_remaining = maxf(
			0.0,
			_hit_remaining
			- delta * MonsterStruckPolicyScript.struck_speed_multiplier(
				_presentation_count
			)
		)
	_death_remaining = maxf(0.0, _death_remaining - delta)
	if not _combat_clock_s.is_valid():
		_try_start_next_presentation()
	if death_was_playing and _death_remaining <= 0.0 and actor._dying:
		# Keep the final frame continuously. The owner timer later extends this as
		# the corpse hold; there must never be a one-frame idle flash in between.
		_death_pose_held = true


func _now_ms() -> int:
	return int(_clock_ms.call()) if _clock_ms.is_valid() else Time.get_ticks_msec()


func _attack_age_seconds() -> float:
	# HC-MONSTER-COMBAT-R3 W1: production attack age consumes the OWNER's
	# combat game clock (seconds, advanced only by the Actor's physics update;
	# pause freezes it, engine time scaling is already inside the delta). The
	# engine wall clock never participates in production timing - it remains
	# only as the legacy preview path for unbound fixtures.
	if _combat_clock_s.is_valid():
		if _attack_action_start_game_time_s < 0.0:
			return INF
		return maxf(0.0, float(_combat_clock_s.call()) - _attack_action_start_game_time_s)
	return float(maxi(0, _now_ms() - _attack_started_at_ms)) / 1000.0


## R4 T1: action validity is the OWNER's logical window, never the draw
## cache. `_attack_remaining` only updates when the rendering process
## advances, and several physics frames can pass without a draw; with the
## owner's combat clock bound, the action lives on [start, start+duration)
## of that clock and expires by pure logic even without any render advance.
func _attack_logic_active() -> bool:
	if _combat_clock_s.is_valid():
		return _attack_age_seconds() < _hc_m30_attack_duration
	return _attack_remaining > 0.0


## True while an attack presentation owns the body (logic-clock authoritative).
func is_attack_presenting() -> bool:
	return _attack_logic_active()


## Parent action identity of the attack presentation currently owning the
## body, or -1. Bound by the enemy at the same tick that commits the damage
## release (HC-MONSTER-COMBAT-R2 T3). R4 T1: an expired action never exposes
## its identity just because no draw has refreshed the cached remaining time.
func current_attack_action_id() -> int:
	return _attack_action_id if _attack_logic_active() else -1


## HC-MONSTER-COMBAT-R3 W2: the attack action's OWN logical age in seconds,
## or -1 when no attack presentation owns the body. Phase crossings are
## judged from this age, never from cached draw state.
func attack_action_age_seconds() -> float:
	return _attack_age_seconds() if _attack_logic_active() else -1.0


## HC-MONSTER-COMBAT-R3 W2 + R4 T1: the logical strike-frame phase of the
## CURRENT action. The threshold was frozen at action admission from the
## canonical frame metadata (hot/cold residency cannot move it mid-action),
## and the window is bounded by the action's own end - a stale cache from a
## previous action can never satisfy it, and an expired action can never
## keep it true.
func attack_frame_phase_reached() -> bool:
	if not _attack_logic_active():
		return false
	var age := _attack_age_seconds()
	return age >= _attack_strike_threshold_s and age < _hc_m30_attack_duration


func _update_resource_residency() -> void:
	if active_resources.is_empty():
		if _inside_visual_distance_px(VISUAL_ACTIVATION_DISTANCE_PX):
			_activate_resources()
	elif not _inside_visual_distance_px(VISUAL_RELEASE_DISTANCE_PX):
		_release_resources()


func _update_animation_frame(delta: float) -> void:
	_hc_m30_last_visual_process_frame = Engine.get_process_frames()
	if _death_remaining > 0.0 or _death_pose_held:
		current_state = "death"
	elif _attack_remaining > 0.0:
		current_state = "attack"
	elif _hit_remaining > 0.0:
		current_state = "hit"
	elif _hc_m30_is_walking():
		current_state = "walk"
	else:
		current_state = "idle"
	# HC-MONSTER-COMBAT-R3 W2 (R3-03): one facing authority per delivery
	# phase. While an attack presentation owns the body, the BODY row uses
	# the same commit-facing the overlay froze - a live target turn during
	# the action must not split the body row from the swing overlay. Walk
	# keeps its own movement facing; every other state follows the actor.
	var visual_facing: Vector2
	if current_state == "attack" and _attack_facing_at_commit != Vector2.INF:
		visual_facing = _attack_facing_at_commit
	elif current_state == "walk":
		visual_facing = actor.movement_facing
	else:
		visual_facing = actor.facing
	current_direction = _direction_row(visual_facing)
	refresh_selection_ring_direction()
	if current_state != _last_state:
		_elapsed = 0.0
		_last_state = current_state
	_elapsed += delta
	var frame_count: int = (
		actor._canonical_attack_frame_count(1) if current_state == "attack"
		else maxi(1, MonsterAnimationPolicy.frame_count(active_resources, StringName(current_state)))
	)
	if _death_pose_held and current_state == "death":
		current_frame = frame_count - 1
	elif current_state == "attack":
		current_frame = HCM30WalkPhaseScript.action_frame_index(_attack_remaining, _hc_m30_attack_duration, frame_count)
	elif current_state == "hit":
		current_frame = HCM30WalkPhaseScript.action_frame_index(_hit_remaining, _hc_m30_hit_duration, frame_count)
	elif current_state == "death":
		current_frame = HCM30WalkPhaseScript.action_frame_index(_death_remaining, _hc_m30_death_duration, frame_count)
	elif current_state == "walk" and _hc_m30_melee_tick == Engine.get_physics_frames():
		current_frame = mini(frame_count - 1, int(floor(fposmod(_hc_m30_walk.phase + _blocked_walk_phase, 1.0) * float(frame_count))))
	else:
		var fps: float = MonsterAnimationPolicy.loop_fps(StringName(current_state))
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
	var effect_profile := SourceFrames.profile_for_id(actor.monster_id)
	var effect_direction := 0 if int(effect_profile.get("direction_count", 8)) == 1 else _direction_row(actor.facing)
	if int(effect_profile.get("direction_count", 8)) == 16: effect_direction *= 2
	SourceFrames.request_profile(effect_profile, effect_direction)
	ProjectileVisual.prewarm_for_monster_id(actor.monster_id)
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


func _appearance_profile_for(monster_id: int) -> Dictionary:
	if is_instance_valid(actor) and actor.monster_id == monster_id:
		var published := actor.published_monster_inputs_view()
		if not published.is_empty():
			return published.appearance
	return MonsterIdentityScript.appearance_profile(monster_id)


func _client_mapping_for(monster_data: Dictionary) -> Dictionary:
	var monster_id := MonsterIdentityScript.monster_id(monster_data)
	var profile := _appearance_profile_for(monster_id)
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
	RuntimeDiagnostics.increment_performance_counter(&"actor_redraw_requests")
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
	var texture_changed: bool = sprite.texture != texture
	var changed: bool = texture_changed or sprite.region_rect != region
	var radius: float = actor.combat_radius_gu if is_instance_valid(actor) else -1.0
	var radius_px: float = actor.collision_radius_px if is_instance_valid(actor) else -1.0
	var geometry_changed: bool = (
		position != _hc_m30_last_geometry_origin
		or radius != _hc_m30_last_geometry_radius
		or radius_px != _hc_m30_last_geometry_radius_px
	)
	if texture_changed:
		sprite.texture = texture
	if sprite.region_rect != region:
		sprite.region_rect = region
	if changed:
		_render_state_update_count += 1
		RuntimeDiagnostics.increment_performance_counter(&"visual_render_state_changes")
	# Frame/row changes do not alter the reviewed footprint. Preserve resource
	# transitions AND legitimate actor radius/visual-origin edits.
	if texture_changed or geometry_changed:
		_refresh_actor_ground_indicator()
		_hc_m30_last_geometry_origin = position
		_hc_m30_last_geometry_radius = radius
		_hc_m30_last_geometry_radius_px = radius_px


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


## R1.2 attack presentation entry (vanilla action FIFO). While any action is
## playing or queued the request is appended in arrival order - multiple
## attack requests stay separate events and are never merged or overwritten.
## Only when nothing is playing does the attack start immediately (the
## historical play_attack behaviour). Presentation-only waiting: gameplay
## attack authority is untouched.
func play_attack(duration := 0.46) -> void:
	if _death_remaining > 0.0 or _death_pose_held:
		return
	if _hit_remaining > 0.0 or _attack_remaining > 0.0 or _presentation_count > 0:
		_enqueue_presentation(PresentationAction.ATTACK, duration)
		return
	_start_attack_visual(duration)


## HC-MONSTER-COMBAT-R1 Task 3 (F01): critical attack arbitration entry for
## production combat transactions (contract
## hardcore.monster.combat_presentation.r1). A newly accepted attack:
## - starts immediately at its logic moment (same call, actor clock),
## - is never queued behind a struck backlog and never dropped on overflow,
## - merges waiting pure STRUCK feedback into at most one bounded item that
##   keeps the NEWEST struck (presentation only: damage counts, delays and
##   status judgements are untouched - they were already applied by the
##   combat layer),
## - is suppressed while a death presentation owns the body (frozen rule).
## HC-MONSTER-COMBAT-R2 T3: the production caller binds the parent action
## identity - action_id, the logic start timestamp and the facing captured at
## the same commit tick. Legacy/preview callers may omit them (sentinels).
## The legacy play_attack() FIFO above remains only for preview/test callers.
func begin_attack_presentation(
	duration := 0.46,
	action_id := -1,
	logic_started_at_ms := -1,
	facing_at_commit := Vector2.INF,
	logic_started_game_time_s := -1.0,
) -> bool:
	if _death_remaining > 0.0 or _death_pose_held:
		return false
	# HC-MONSTER-COMBAT-R3 W1 + R4 T1: an idempotent re-begin of the SAME
	# logical action must not reset the action age and must not re-trigger
	# the start phase - and the caller must be able to TELL, so this returns
	# false (accepted, nothing new started) instead of true. A same-id retry
	# whose action has already expired is likewise rejected outright: the
	# caller may not resurrect an expired action into a fresh presentation.
	if action_id >= 0 and _attack_action_id == action_id:
		return false
	var merged := _merge_pending_struck_feedback()
	if merged > 0:
		RuntimeDiagnostics.increment_performance_counter(
			&"monster_presentation_struck_merged", merged
		)
	_attack_action_serial += 1
	_attack_action_id = action_id
	_motion_overridden_attack_action_id = -1
	_attack_logic_started_at_ms = logic_started_at_ms
	_attack_facing_at_commit = facing_at_commit
	# R3 W1: when the production caller provides the owner's combat game time
	# at the action start, the age authority becomes the OWNER's clock and the
	# wall-clock stamp is kept only as legacy diagnostics for preview paths.
	if logic_started_game_time_s >= 0.0:
		_attack_action_start_game_time_s = logic_started_game_time_s
	elif _combat_clock_s.is_valid():
		_attack_action_start_game_time_s = float(_combat_clock_s.call())
	_start_attack_visual(duration)
	return true


## Drains the presentation ring, collapsing stale pure-STRUCK items into the
## single newest feedback item. HC-MONSTER-COMBAT-R2 T3: the kept item is the
## NEWEST struck (the contract always said so; the R1 loop actually kept the
## oldest because it never overwrote the first match). Any pending
## presentation (including preview attacks that a newer logical attack
## supersedes) is merged, never replayed.
func _merge_pending_struck_feedback() -> int:
	if _presentation_count <= 0:
		return 0
	var merged := 0
	var kept_kind := -1
	var kept_duration := 0.0
	var kept_barrier := -1
	for i in _presentation_count:
		var idx := (_presentation_head + i) % PRESENTATION_QUEUE_CAPACITY
		var kind: int = _presentation_kind[idx]
		if kind == PresentationAction.STRUCK:
			# Overwrite on every struck: iteration runs oldest -> newest, so
			# the loop lands on the NEWEST struck item.
			kept_kind = kind
			kept_duration = _presentation_duration[idx]
			kept_barrier = _presentation_step_barrier[idx]
		merged += 1
	_presentation_head = 0
	_presentation_tail = 0
	_presentation_count = 0
	_pending_struck_count = 0
	if kept_kind == PresentationAction.STRUCK:
		_presentation_kind[0] = kept_kind
		_presentation_duration[0] = kept_duration
		_presentation_step_barrier[0] = kept_barrier
		_presentation_head = 0
		_presentation_tail = 1
		_presentation_count = 1
		_pending_struck_count = 1
	return merged


func _start_attack_visual(duration: float) -> void:
	_hc_m30_walk.interrupt_pose()
	if is_instance_valid(_attack_overlay_node):
		_attack_overlay_node.queue_free()
	_motion_overridden_attack_action_id = -1
	_attack_overlay_node = null
	# HC-MONSTER-COMBAT-R2 T3: the logic clock starts NOW (the action's own
	# age authority). A later render delta can never predate this timestamp.
	_attack_started_at_ms = _now_ms()
	# R4 T1: the strike phase threshold is frozen at action admission from
	# the canonical frame metadata. Hot/cold resource residency can never
	# move the phase boundary mid-action; residency only decides whether the
	# overlay is drawn, never when the phase becomes true.
	var frame_count_for_phase := actor._canonical_attack_frame_count(1)
	_attack_strike_threshold_s = duration * 2.0 / float(maxi(frame_count_for_phase, 4))
	if visible and not SourceFrames.profile_for_id(actor.monster_id).is_empty() and actor.monster_id != 224:
		var overlay := AttackOverlay.new()
		# Facing policy: the swing direction is frozen at the commit tick. The
		# commit facing is authoritative for the 8-direction row; the 16-step
		# refinement still aims once at the target line captured at start (a
		# per-start aim, not a per-frame track).
		var commit_facing := (
			_attack_facing_at_commit
			if _attack_facing_at_commit != Vector2.INF
			else actor.facing
		)
		var direction8 := _direction_row(commit_facing)
		var direction16 := direction8 * 2
		if is_instance_valid(actor.target):
			direction16 = ProjectileVisual._direction16_for_line(actor.global_position, actor.target.global_position)
		overlay.setup(actor.monster_id, direction8, direction16, duration / float(frame_count_for_phase), Vector2(actor_ground_offset))
		add_child(overlay)
		_attack_overlay_node = overlay
	_attack_remaining = duration
	_hc_m30_attack_duration = float(duration)
	_action_duration = duration
	_elapsed = 0.0

func mark_attack_motion_overridden(action_id: int) -> void:
	if action_id < 0 or action_id != _attack_action_id:
		return
	_motion_overridden_attack_action_id = action_id
	_attack_remaining = 0.0
	if is_instance_valid(_attack_overlay_node):
		_attack_overlay_node.visible = false
		_attack_overlay_node.queue_free()
	_attack_overlay_node = null


## O(1) FIFO append. HC-MONSTER-COMBAT-R2 T3 sustained backpressure: when the
## ring is full and struck items are waiting, the waiting struck items
## collapse into the single NEWEST one right here (the same newest-kept
## contract as the attack-time merge) instead of waiting for the next attack
## to clean up; only a backlog with no struck item left still drops the
## newest event and counts the overflow.
func _enqueue_presentation(kind: PresentationAction, duration: float, step_barrier := -1) -> void:
	if _presentation_count >= PRESENTATION_QUEUE_CAPACITY and _pending_struck_count > 0:
		var collapsed := _merge_pending_struck_feedback()
		if collapsed > 1:
			RuntimeDiagnostics.increment_performance_counter(
				&"monster_presentation_struck_backpressure_collapsed",
				collapsed - 1
			)
	if _presentation_count >= PRESENTATION_QUEUE_CAPACITY:
		RuntimeDiagnostics.increment_performance_counter(
			&"monster_presentation_queue_overflow"
		)
		return
	_presentation_kind[_presentation_tail] = kind
	_presentation_duration[_presentation_tail] = duration
	_presentation_step_barrier[_presentation_tail] = step_barrier
	_presentation_tail = (_presentation_tail + 1) % PRESENTATION_QUEUE_CAPACITY
	_presentation_count += 1
	if kind == PresentationAction.STRUCK:
		_pending_struck_count += 1


## Dequeues and starts the next presentation event in strict arrival order.
## A struck waits only for the committed logical attack. Movement steps stay
## intact and pause in place while the owner consumes the authored hit time.
func _try_start_next_presentation() -> void:
	if _presentation_count <= 0:
		return
	if _hit_remaining > 0.0 or _attack_remaining > 0.0:
		return
	# The owner action clock is authoritative in production. The render cache
	# can reach zero first when the logical attack duration is longer than the
	# visual clip, so never start a queued hit while the committed action still
	# owns the actor body.
	if (
		_combat_clock_s.is_valid()
		and is_instance_valid(actor)
		and actor._attack_action_active
	):
		return
	if _death_remaining > 0.0 or _death_pose_held:
		return
	var kind: int = _presentation_kind[_presentation_head]
	var duration := _presentation_duration[_presentation_head]
	_presentation_head = (_presentation_head + 1) % PRESENTATION_QUEUE_CAPACITY
	_presentation_count -= 1
	if kind == PresentationAction.STRUCK:
		_pending_struck_count -= 1
		_start_struck_visual(duration)
	else:
		# A queued (legacy/preview) attack carries no parent action identity.
		_attack_action_id = -1
		_attack_logic_started_at_ms = -1
		_attack_facing_at_commit = Vector2.INF
		if _combat_clock_s.is_valid():
			_attack_action_start_game_time_s = float(_combat_clock_s.call())
		_start_attack_visual(duration)


## Vanilla R1 entry for monster struck visuals: enqueue one struck event in
## arrival order. O(1): three packed-array writes, no per-hit Timer/Node/
## Dictionary allocation. Duration is resolved from the CANONICAL ActStruck
## frame count (appearance metadata cached at _ready - residency independent)
## and struck_frame_ms(level).
func queue_struck(monster_level := -1) -> void:
	if _death_remaining > 0.0 or _death_pose_held:
		return
	if not is_instance_valid(actor):
		return
	RuntimeDiagnostics.increment_performance_counter(
		&"monster_struck_event_count"
	)
	var struck_level := (
		monster_level
		if monster_level > 0
		else maxi(1, actor.level)
	)
	# Vanilla duration = ActStruck frames x max(80, 200 - level * 5) ms.
	# No per-monster-name switch and no global 0.22s constant.
	var duration := float(
		_canonical_struck_frame_count
		* MonsterStruckPolicyScript.struck_frame_ms(struck_level)
	) / 1000.0
	# A hit never waits for an autonomous movement step. In production the owner
	# consumes the exact animation interval and subtracts it from movement; the
	# only hard ordering barrier is a committed attack action.
	_enqueue_presentation(PresentationAction.STRUCK, duration, -1)
	# A direct hit on an idle or moving actor starts in this same owner tick.
	# Production timing remains physics-owned; this call only dequeues and
	# initializes the presentation. A committed attack is held by the guard in
	# _try_start_next_presentation until its logical action ends.
	if _combat_clock_s.is_valid():
		if not actor._attack_action_active:
			_attack_remaining = maxf(
				0.0,
				_hc_m30_attack_duration - _attack_age_seconds()
			)
		_try_start_next_presentation()
	RuntimeDiagnostics.record_performance_max(
		&"monster_struck_visual_pending_max",
		float(_pending_struck_count)
	)


func pending_struck_count() -> int:
	return _pending_struck_count


func _start_struck_visual(duration: float) -> void:
	_hc_m30_walk.interrupt_pose()
	_hit_remaining = duration
	_hc_m30_hit_duration = duration
	_action_duration = duration
	_elapsed = 0.0


## Authoritative physics owner entry for production struck presentation.
## Returns the exact portion of this actor's physics interval spent playing
## struck animation. A committed attack is allowed to finish first; if it ends
## inside this interval, only the remaining slice is available to struck. The
## caller subtracts the returned value from cooldown and movement progress.
##
## This method is intentionally the only production writer that advances
## `_hit_remaining`. It is safe when the visual is cold or invisible because
## the countdown is independent of rendering. Each queued hit consumes its
## full authored duration; no backlog acceleration or restart is applied.
func advance_struck_action(delta: float) -> float:
	if not _combat_clock_s.is_valid() or not is_instance_valid(actor):
		return 0.0
	var available := maxf(0.0, delta)
	if available <= 0.0 or _death_remaining > 0.0 or _death_pose_held:
		return 0.0
	# EnemyActor advances and owns the combat clock before entering this method.
	# If the logical action is still active, the current physics interval has not
	# crossed its completion boundary; never let an overlap calculation or a
	# stale visual cache dequeue/start a struck early.
	if actor._attack_action_active:
		_attack_remaining = 0.0 if _motion_overridden_attack_action_id == _attack_action_id else maxf(
			0.0,
			_hc_m30_attack_duration - _attack_age_seconds()
		)
		return 0.0

	# Sync the visual cache from the owner's logical action before arbitration.
	# The actor duration is authoritative: the visual clip may be shorter.
	var clock_now := float(_combat_clock_s.call())
	var interval_start := clock_now - available
	var action_start := float(actor._attack_action_start_time_s)
	var action_duration := maxf(0.0, float(actor._attack_action_duration_s))
	var action_end := action_start + action_duration
	var attack_left := 0.0
	if action_duration > 0.0 and action_start >= 0.0:
		# Use overlap with this physics interval rather than the active flag. The
		# owner closes that flag while advancing its clock, so this also handles
		# an attack whose logical end falls inside the interval.
		var overlap_start := maxf(interval_start, action_start)
		var overlap_end := minf(clock_now, action_end)
		var attack_overlap := maxf(0.0, overlap_end - overlap_start)
		attack_left = attack_overlap
		# The visual cache follows the authored presentation clip for rendering;
		# the actor overlap above remains the sole ordering barrier.
		if _motion_overridden_attack_action_id != _attack_action_id:
			_attack_remaining = maxf(0.0, _hc_m30_attack_duration - _attack_age_seconds())
	if attack_left > 0.0:
		available -= attack_left
	if available <= 0.0:
		return 0.0

	var paused := 0.0
	while available > 0.0:
		if _hit_remaining <= 0.0:
			if _presentation_count <= 0:
				break
			if _presentation_kind[_presentation_head] != PresentationAction.STRUCK:
				break
			var duration := _presentation_duration[_presentation_head]
			_presentation_head = (_presentation_head + 1) % PRESENTATION_QUEUE_CAPACITY
			_presentation_count -= 1
			_pending_struck_count = maxi(0, _pending_struck_count - 1)
			_start_struck_visual(duration)
		var consumed := minf(available, _hit_remaining)
		_hit_remaining = maxf(0.0, _hit_remaining - consumed)
		available -= consumed
		paused += consumed
		if consumed <= 0.0:
			break
	return paused


func is_struck_action_active() -> bool:
	return _hit_remaining > 0.000001


## Canonical ActStruck frame count from the monster identity boundary (read
## once at _ready). Evidence note (R1.3): the runtime authority is
## canonical_monster_catalog.json - every one of the 156 entries resolves
## through appearance_profile_id to appearance_profiles[].actions.hit
## .framesPerDirection (109 profiles = 2 frames, monster 241's shared profile
## = 6 frames). This is appearance metadata, not texture-residency state, so
## a struck enqueued during cold activation / async streaming still gets the
## exact vanilla duration. Published actors use their frozen appearance;
## standalone actors retain the canonical one-shot read per visual.
func _load_canonical_struck_frame_count(monster_id: int) -> int:
	var actions: Variant = _appearance_profile_for(monster_id).get("actions", {})
	if actions is Dictionary:
		var hit: Variant = actions.get("hit", {})
		if hit is Dictionary:
			var count := int(hit.get("framesPerDirection", 2))
			if count > 0:
				return count
	return 2


## Legacy direct-start primitive (test/compatibility callers only). The
## production damage path must go through queue_struck so a struck during an
## attack or committed movement step waits instead of silently burning away.
func play_hit(duration := 0.22) -> void:
	_hc_m30_walk.interrupt_pose()
	if _death_remaining > 0.0:
		return
	_hit_remaining = duration
	_hc_m30_hit_duration = float(duration)
	# A hit cannot reset a higher-priority attack clock/fallback lunge.
	if _attack_remaining <= 0.0:
		_action_duration = duration
		_elapsed = 0.0


func death_animation_duration() -> float:
	var frame_count := MonsterAnimationPolicy.frame_count(
		active_resources,
		&"death"
	)
	return maxf(0.62, float(maxi(1, frame_count)) / DEATH_ANIMATION_FPS)


func play_death(duration := -1.0) -> float:
	_hc_m30_walk.interrupt_pose()
	var resolved_duration := (
		death_animation_duration()
		if duration <= 0.0
		else float(duration)
	)
	_death_pose_held = false
	_death_remaining = resolved_duration
	_hc_m30_death_duration = resolved_duration
	_hit_remaining = 0.0
	_attack_remaining = 0.0
	# Death is the highest priority action: the whole presentation FIFO must
	# not outlive the monster or play on the corpse.
	_presentation_head = 0
	_presentation_tail = 0
	_presentation_count = 0
	_pending_struck_count = 0
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

# HCM30-R4: authoritative physical movement feeds a presentation-only phase.
const HCM30WalkPhaseScript := preload("res://scripts/monster_ai_package/m30/walk_phase.gd")
var _hc_m30_walk: HCM30WalkPhase = HCM30WalkPhaseScript.new()
var _hc_m30_melee_tick: int = -1
var _hc_m30_last_visual_process_frame: int = -1
var _hc_m30_stride_configured: bool = false
var _locomotion_intent_tick := -1
var _locomotion_intent := false
var _blocked_walk_phase := 0.0

func hc_m30_finish_locomotion_tick(intent: bool, physics_delta: float) -> void:
	_locomotion_intent_tick = Engine.get_physics_frames()
	_locomotion_intent = intent
	if not intent or actor.actual_ground_motion_gu.length_squared() > 0.00000001:
		return
	if _death_remaining > 0.0 or _death_pose_held or _hit_remaining > 0.0 or _attack_logic_active():
		return
	var count := maxi(1, MonsterAnimationPolicy.frame_count(active_resources, &"walk"))
	# Blocked locomotion is presentation intent, never manufactured distance.
	# Its phase advances once on the owner's native physics tick, so engine
	# pause freezes it and control/attack holds leave this phase untouched.
	_blocked_walk_phase = fposmod(_blocked_walk_phase + maxf(0.0, physics_delta) * MonsterAnimationPolicy.loop_fps(&"walk") / float(count), 1.0)

func hc_m30_begin_melee_tick() -> void:
	_hc_m30_melee_tick = Engine.get_physics_frames()

func hc_m30_accept_ground_motion(distance_gu: float) -> void:
	if not is_finite(distance_gu) or distance_gu <= 0.000001:
		return
	if _death_remaining > 0.0 or _death_pose_held:
		return
	if not _hc_m30_stride_configured and not active_resources.is_empty() and is_instance_valid(actor):
		var count: int = MonsterAnimationPolicy.frame_count(active_resources, &"walk")
		var fps: float = MonsterAnimationPolicy.loop_fps(&"walk")
		var nominal_speed: float = actor.move_speed_gu_per_sec
		if count > 0 and fps > 0.0 and nominal_speed > 0.000001:
			# At normal full speed this exactly preserves the existing walk FPS.
			# Slow/blocked/short actual movement advances only its travelled fraction.
			_hc_m30_walk.configure_cycle(nominal_speed * float(count) / fps)
			_hc_m30_stride_configured = true
	_hc_m30_walk.accept_distance(distance_gu, Engine.get_physics_frames())
	# The existing physics path already forbids movement during pending impact.
	# Cancel ONLY the settled attack's visual tail; do not change hit/cooldown.
	if is_instance_valid(actor) and actor._pending_attack_time < 0.0:
		_attack_remaining = 0.0

func _hc_m30_is_walking() -> bool:
	if _locomotion_intent_tick == Engine.get_physics_frames() and _locomotion_intent:
		return true
	if _hc_m30_melee_tick == Engine.get_physics_frames():
		return _hc_m30_walk.moving_on(Engine.get_physics_frames())
	# Charmed/special/legacy movement did not enter the new ordinary-melee tick.
	# Preserve its existing presentation instead of accidentally showing idle.
	return actor.ground_velocity_gu_per_sec().length_squared() > MOVEMENT_ANIMATION_MIN_SPEED_GU_PER_SEC * MOVEMENT_ANIMATION_MIN_SPEED_GU_PER_SEC

func hc_m30_motion_snapshot() -> Dictionary:
	# On-demand diagnostics only; do not JSON-log every actor every frame.
	return {
		"visual_process_frame": _hc_m30_last_visual_process_frame,
		"attack_duration": _hc_m30_attack_duration,
		"hit_duration": _hc_m30_hit_duration,
		"pose_remaining": actor._hc_m30_attack_pose_remaining if is_instance_valid(actor) else 0.0,
		"physics_tick": Engine.get_physics_frames(),
		"melee_tick": _hc_m30_melee_tick,
		"last_motion_tick": _hc_m30_walk.last_motion_tick,
		"walk_phase": _hc_m30_walk.phase,
		"locomotion_intent": _locomotion_intent,
		"locomotion_intent_tick": _locomotion_intent_tick,
		"blocked_walk_phase": _blocked_walk_phase,
		"reference_cycle_gu": _hc_m30_walk.cycle_gu,
		"actual_distance_gu": _hc_m30_walk.total_ground_distance_gu,
		"state": current_state, "frame": current_frame,
		"attack_visual_remaining": _attack_remaining,
		"pending_impact": actor._pending_attack_time if is_instance_valid(actor) else -1.0,
	}
