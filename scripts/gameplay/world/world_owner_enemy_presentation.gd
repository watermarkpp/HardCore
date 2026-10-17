extends RefCounted
## Original retained Enemy observer/geometry. The model remains the sole HP,
## targeting and action authority; M supplies actual render/audio facts only.
const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const NAME_LABEL_SIZE := MonsterOverheadScript.NAME_LABEL_SIZE
const NAME_LABEL_HEALTH_BAR_GAP := MonsterOverheadScript.NAME_LABEL_HEALTH_BAR_GAP
const POISON_INDICATOR_DOT_RADIUS := 3.0
const POISON_INDICATOR_DOT_CENTER_OFFSET_X := 5.0
const TARGET_RING_FOOTPRINT_SCALE := 1.25
const AUDIO_SERVICE_NEGATIVE_CACHE_MSEC := 1000
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _model: WeakRef
var _id: int
var _shared: RefCounted
var _audio: RefCounted
var MonsterTargetRingGeometryScript: RefCounted
var RuntimeDiagnostics: RefCounted
func _init(core: RefCounted, model: RefCounted, id: int, shared: RefCounted, audio: RefCounted, ring: RefCounted) -> void:
	_core = weakref(core)
	_model = weakref(model)
	_id = id
	_shared = shared
	_audio = audio
	MonsterTargetRingGeometryScript = ring
	RuntimeDiagnostics = core.diagnostics
	if not audio.has_signal("actual_audio_result"): core.fault("MISSING_actual_audio_reply",{}); return
	audio.actual_audio_result.connect(_on_actual_audio_result)
func owner_thread_id() -> int: return _owner
func detach_actual_audio_observer_at_final_free() -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	if _audio.actual_audio_result.is_connected(_on_actual_audio_result): _audio.actual_audio_result.disconnect(_on_actual_audio_result)
	return true
func invoke_original(method: StringName, arguments: Array) -> Variant:
	assert(OS.get_thread_caller_id() == _owner and has_method(method))
	return callv(method, arguments)
func is_inside_tree() -> bool: return _model.get_ref().is_inside_world()
func is_physics_processing() -> bool: return _model.get_ref().lifetime.physics_processing_enabled()
func _record_performance_counter(key: StringName, amount := 1) -> void: RuntimeDiagnostics.increment_performance_counter(key, amount)
func _hc_life(_self: RefCounted) -> int: return _model.get_ref().current_life()
func queue_redraw() -> void: _core.get_ref().emit_original_main_event(&"enemy_redraw", [_id])
func _emit_render(operation: StringName, args: Array) -> void: _core.get_ref().emit_original_main_event(operation, [_id] + args)
var _audio_rng: RandomNumberGenerator
var _audio_rng_initialized := false
var _audio_appear_emitted := false
var _audio_death_emitted := false
var _audio_combat_session_active := false
var _audio_combat_entry_seen := false
var _audio_combat_session_serial := 0
var _audio_owner_key := ""
var _audio_attack_sequence := 0
var _audio_attack_frame_sequence := -1
var _audio_attack_presented_seen := false
var _audio_attack_frame_ready := false
var _audio_attack_start_accepted := false
var _audio_combat_epoch_target_instance_id := 0
var _audio_combat_epoch_method_available := false
var _audio_combat_epoch_property_available := false
var _audio_combat_epoch_probe_complete := false
var _audio_combat_epoch_property_probe_count := 0
var _audio_previous_visual_state := ""
var _audio_previous_visual_frame := -1
var _audio_previous_facing := Vector2.INF
var monster_id: Variant:
	get: return _model.get_ref().get("monster_id")
var runtime_map_id: Variant:
	get: return _model.get_ref().get("runtime_map_id")
var combat_enabled: Variant:
	get: return _model.get_ref().get("combat_enabled")
var process_mode: Variant:
	get: return _model.get_ref().get("process_mode")
var _background_deep_sleeping: Variant:
	get: return _model.get_ref().get("_background_deep_sleeping")
var _burrowed: Variant:
	get: return _model.get_ref().get("_burrowed")
var _dying: Variant:
	get: return _model.get_ref().get("_dying")
var _death_pending: Variant:
	get: return _model.get_ref().get("_death_pending")
var current_hp: Variant:
	get: return _model.get_ref().get("current_hp")
var max_hp: Variant:
	get: return _model.get_ref().get("max_hp")
var is_boss: Variant:
	get: return _model.get_ref().get("is_boss")
var behavior_profile: Variant:
	get: return _model.get_ref().get("behavior_profile")
var collision_radius_px: Variant:
	get: return _model.get_ref().get("collision_radius_px")
var facing: Variant:
	get: return _model.get_ref().get("facing")
var primary_target: Variant:
	get: return _model.get_ref().get("primary_target")
var target: Variant:
	get: return _model.get_ref().get("target")
var visual: Variant:
	get: return _model.get_ref().get("visual")
var _audio_runtime_service: Variant:
	get: return _shared._audio_runtime_service
	set(value): _shared._audio_runtime_service = value
var _audio_service_retry_after_msec: Variant:
	get: return _shared._audio_service_retry_after_msec
	set(value): _shared._audio_service_retry_after_msec = value
var _audio_service_lookup_count: Variant:
	get: return _shared._audio_service_lookup_count
	set(value): _shared._audio_service_lookup_count = value
var _audio_service_now_override_msec: Variant:
	get: return _shared._audio_service_now_override_msec
	set(value): _shared._audio_service_now_override_msec = value

func _audio_attack_started(action_serial := -1) -> void:
	if not combat_enabled:
		return
	# HC-MONSTER-COMBAT-R2 T3: the audio stream binds to the SAME parent
	# action identity as the presentation. The enemy allocates the serial at
	# the attack commit tick; presentation start and attack-start audio share
	# it, so a superseded action can neither emit nor replay audio.
	_audio_attack_sequence = action_serial if action_serial > 0 else _audio_attack_sequence + 1
	_audio_attack_frame_sequence = -1
	_audio_attack_frame_ready = false
	_audio_attack_start_accepted = false
	_audio_attack_presented_seen = false
	# Attack start is emitted only by accepted actions below, never by target
	# acquisition or an AI preview.
	_audio_attack_start_accepted = _emit_monster_audio("attack_start")


## HC-MONSTER-COMBAT-R3 W1: the parent action identity is allocated at the
## real admission point, BEFORE the release record is built and before any
## presentation is requested. The identity is a four-tuple anchored on the
## combat game clock: monotonic serial x source life x world generation, with
## `_attack_action_start_time_s` as the timing origin. Returns the serial.
## HC-MONSTER-COMBAT-R3 W1/W2: the single combat action clock. Advanced ONLY
## here (the Actor's own physics entry point calls it with exactly one physics
## delta): pause freezes it, background fast-path ticks accumulate to the same
## total. The active-action flag closes on the combat clock itself - it must
## not outlive the action's logical window.

func _audio_combat_epoch() -> int:
	var player_target := _audio_player_target()
	if player_target == null:
		return -1
	var target_instance_id: int = _core.get_ref().actor_access.canonical(player_target).get_instance_id()
	if (
		not _audio_combat_epoch_probe_complete
		or _audio_combat_epoch_target_instance_id != target_instance_id
	):
		_audio_combat_epoch_target_instance_id = target_instance_id
		_audio_combat_epoch_method_available = _core.get_ref().actor_access.supports(player_target, "combat_epoch")
		_audio_combat_epoch_property_available = false
		_audio_combat_epoch_probe_complete = true
		if not _audio_combat_epoch_method_available:
			_audio_combat_epoch_property_probe_count += 1
			for property_info: Dictionary in player_target.get_property_list():
				if str(property_info.get("name", "")) == "combat_epoch":
					_audio_combat_epoch_property_available = true
					break
	var epoch: Variant = null
	if _audio_combat_epoch_method_available:
		epoch = _core.get_ref().actor_access.invoke(player_target, &"combat_epoch", [])
	elif _audio_combat_epoch_property_available:
		epoch = player_target.get("combat_epoch")
	return int(epoch) if epoch is int or epoch is float else -1

func _audio_combat_transition_is_active() -> bool:
	# W3 adds this optional player contract after the audio branch baseline. The
	# has_method guard keeps this branch compatible with the current checkout and
	# rejects audio before service admission once the method is present.
	var player_target := _audio_player_target()
	if player_target == null or not _core.get_ref().actor_access.supports(player_target, "combat_transition_is_active"):
		return false
	var active: Variant = _core.get_ref().actor_access.invoke(player_target, &"combat_transition_is_active", [])
	return active is bool and bool(active)

func _audio_context(semantic_event: String) -> Dictionary:
	var context := {
		"source": "enemy_actor",
		"monster_id": monster_id,
		"runtime_map_id": runtime_map_id,
		"semantic_event": semantic_event,
		"audio_owner_key": _audio_owner_key_for_actor(),
		"source_instance_id": _id,
		"source_life": _hc_life(self),
	}
	var combat_epoch := _audio_combat_epoch()
	if combat_epoch >= 0:
		context["combat_epoch"] = combat_epoch
	if semantic_event in ["attack_start", "attack_frame"]:
		context["release_id"] = "attack:%d" % _audio_attack_sequence
	if semantic_event == "combat_prompt":
		context["session_id"] = "combat:%d" % _audio_combat_session_serial
	return context

func _audio_end_combat_session(_reason := "explicit_disengage") -> void:
	_audio_combat_session_active = false
	_audio_combat_entry_seen = false

func _audio_source_eligible(allow_death := false) -> bool:
	if not is_inside_tree() or process_mode == 4: return false
	if _audio_combat_transition_is_active(): return false
	if not allow_death and not is_physics_processing(): return false
	if _background_deep_sleeping: return false
	if _burrowed and not allow_death: return false
	if not allow_death and (_dying or _death_pending or current_hp <= 0): return false
	# Main observes actual root visibility/canvas at the original audio event
	# delivery. S makes no synchronous Main query or guessed visibility read.
	return true

func _audio_observe_visual_state() -> void:
	# R14-B5: only observe MonsterVisual while this attack sequence's frame
	# audio is still pending. Once the frame sound has settled (or no accepted
	# attack is running), return immediately without touching the visual node.
	if _audio_attack_sequence <= 0 or _audio_attack_frame_sequence == _audio_attack_sequence:
		return
	if visual == null or not is_instance_valid(visual):
		return
	# HC-MONSTER-COMBAT-R3 W2: phase observation is bound to the CURRENT
	# parent action. Cached draw state that belongs to another action (or a
	# finished one) can never ready or commit THIS action's audio phases.
	if visual.current_attack_action_id() != _audio_attack_sequence:
		return
	# R3 W2: the strike phase crossing comes from the action's OWN logical
	# age, not from a drawn frame index. A rejected start sound does not
	# erase the phase - the marking happens before the callback, exactly once.
	if not visual.attack_frame_phase_reached():
		return
	_audio_attack_frame_ready = true
	_audio_attack_presented_seen = true
	_audio_attack_frame_sequence = _audio_attack_sequence
	_emit_monster_audio("attack_frame")
	# R3 W2: EXPIRY, not supplementary playback. If the action finishes before
	# its frame phase fired, the phase expires with the action - there is no
	# post-action attack_frame emission (the R2 branch that replayed the frame
	# sound after the action ended was removed with its test contract).
	_audio_previous_visual_state = str(visual.current_state)
	_audio_previous_visual_frame = int(visual.current_frame)
	_audio_previous_facing = facing

func _audio_owner_key_for_actor() -> String:
	if _audio_owner_key.is_empty():
		_audio_owner_key = "monster:%d:%d" % [monster_id, _id]
	return _audio_owner_key

func _audio_player_target() -> Object:
	if _core.get_ref().actor_access.is_present(primary_target):
		return primary_target
	if _core.get_ref().actor_access.is_present(target) and _core.get_ref().actor_access.is_kind(target, &"player"):
		return target
	return null

func _audio_service() -> RefCounted:
	if not is_inside_tree(): return null
	if _audio_runtime_service != null:
		var state: Dictionary = _audio.service_state(_audio_runtime_service.token)
		if state.present and state.inside_tree and state.same_tree: return _audio_runtime_service
	_audio_runtime_service = null
	var now_msec := _audio_service_cache_now_msec()
	if now_msec < _audio_service_retry_after_msec: return null
	_audio_service_retry_after_msec = now_msec + AUDIO_SERVICE_NEGATIVE_CACHE_MSEC
	_audio_service_lookup_count += 1
	for candidate: RefCounted in _audio.find_services_in_original_group_order():
		var state: Dictionary = _audio.service_state(candidate.token)
		if state.present and state.inside_tree and &"play_monster_event" in state.methods:
			_audio_runtime_service = candidate
			_audio_service_retry_after_msec = 0
			return candidate
	return null

func _audio_service_cache_now_msec() -> int:
	return (
		_audio_service_now_override_msec
		if _audio_service_now_override_msec >= 0
		else _core.get_ref().clock_ports.get_ticks_msec()
	)

func _audio_target_changed(_next_target: Object) -> void:
	# Compatibility only: discovery/combat-state sound is retired.
	return

func _audio_try_emit_appear() -> void:
	# Compatibility shim for old test fixtures. Spawn/appear is intentionally
	# silent in the W4 production whitelist.
	return

func _audio_try_enter_combat_session() -> bool:
	# Compatibility only. No service lookup, context or session on pursuit.
	return false

func _draw_boss_warning_ground_projection() -> void:
	var model: RefCounted = _model.get_ref()
	var special: Dictionary = model.boss_rule.get("specialSkill", {})
	var warning_polygon_px: PackedVector2Array = model.boss_warning_polygon_px(special)
	if warning_polygon_px.size() < 3: return
	var is_cone := str(model._boss_skill_footprint_snapshot.get("shape_type", "")) == preload("res://scripts/skills/skill_footprint_snapshot.gd").SHAPE_SECTOR_ARC
	_emit_render(&"enemy_draw_colored_polygon", [warning_polygon_px, Color(0.95, 0.12, 0.04, 0.22) if is_cone else Color(0.95, 0.18, 0.06, 0.16)])
	var outline_px := warning_polygon_px.duplicate()
	outline_px.append(warning_polygon_px[0])
	_emit_render(&"enemy_draw_polyline", [outline_px, Color(1.0, 0.34, 0.08, 0.92) if is_cone else Color(1.0, 0.36, 0.12, 0.85), 5.0, true])

func _draw_ground_indicator_ellipse(
	center_px: Vector2,
	radii_px: Vector2,
	color: Color,
	width_px: float,
) -> void:
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center_px + Vector2(cos(angle) * radii_px.x, sin(angle) * radii_px.y)
		)
	_emit_render(&"enemy_draw_polyline", [points, color, width_px, true])

func _emit_monster_audio(
	semantic_event: String,
	allow_death := false,
	context_overrides: Dictionary = {},
) -> bool:
	if not combat_enabled and semantic_event in ["combat_prompt", "attack_start", "attack_frame"]:
		return false
	if monster_id <= 0 or not _audio_source_eligible(allow_death):
		return false
	var service := _audio_service()
	if service == null:
		return false
	# The service owns exact ID mapping, resource availability, voice pooling
	# and fail-closed status.  EnemyActor never resolves names/appearances.
	var context := _audio_context(semantic_event)
	context.merge(context_overrides, true)
	var result: Variant = _audio.invoke_service(service.token, &"play_monster_event", [monster_id, semantic_event, context])
	return result is Dictionary and str((result as Dictionary).get("status", "")) == "played"

func _emit_player_physical_contact(attacker: Object, damage_context: Dictionary) -> bool:
	if str(damage_context.get("damage_kind", "")) != "player_physical" or not bool(damage_context.get("confirmed_hit", false)) or not _core.get_ref().actor_access.is_kind(attacker, &"player") or not _audio_source_eligible(): return false
	var classic_shape := int(_audio.classic_weapon_shape(_core.get_ref().skill_actors.runtime_actor_id(attacker)))
	if classic_shape < 0: return false
	var service := _audio_service()
	if service == null or not _audio.reference_has_method(service.token, &"play_player_physical_contact"): return false
	var context := _audio_context("player_physical_contact")
	context.merge(damage_context, true)
	context["classic_weapon_shape"] = classic_shape
	var result: Variant = _audio.invoke_service(service.token, &"play_player_physical_contact", [classic_shape, context])
	return result is Dictionary and str((result as Dictionary).get("status", "")) == "played"

func _refresh_overhead_health() -> void:
	_record_performance_counter(&"overhead_health_refreshes")
	if _model.get_ref().presentation.has_overhead(): _emit_render(&"enemy_overhead_health", [current_hp, max_hp])

func _request_actor_redraw() -> void:
	_record_performance_counter(&"actor_redraw_requests")
	queue_redraw()


## Parent CanvasItem redraw is only needed when this actor owns procedural
## fallback geometry. Final textured actors keep their Sprite2D/MonsterVisual
## redraw ownership; stateful one-shot callers above still use the explicit
## _request_actor_redraw() path.

func _request_actor_redraw_if_dynamic() -> void:
	var visual_started_usec: int = RuntimeDiagnostics.begin_timed_segment(
		&"enemy_visual_update_calls"
	)
	_request_actor_redraw_if_dynamic_internal()
	RuntimeDiagnostics.end_timed_segment(
		&"enemy_visual_update_usec",
		visual_started_usec,
	)


## Enemy-owned visual invalidation gate. MonsterVisual's separate `_process`
## remains outside this file; this probe covers only redraw work requested by
## EnemyActor physics/state transitions.

func _request_actor_redraw_if_dynamic_internal() -> void:
	if visual != null and visual.uses_final_art():
		return
	var draws_procedural_fallback := should_draw_synthetic_ground_shadow()
	var fallback_attack_active: bool = visual != null and visual.is_fallback_attacking()
	if not draws_procedural_fallback and not fallback_attack_active:
		return
	_request_actor_redraw()

func _reset_monster_audio_observer() -> void:
	_retire_cached_audio_owner()
	_audio_appear_emitted = false
	_audio_death_emitted = false
	_audio_combat_session_active = false
	_audio_combat_entry_seen = false
	_audio_combat_session_serial = 0
	_audio_owner_key = ""
	_audio_attack_sequence = 0
	_audio_attack_frame_sequence = -1
	_audio_attack_frame_ready = false
	_audio_attack_start_accepted = false
	_audio_combat_epoch_target_instance_id = 0
	_audio_combat_epoch_method_available = false
	_audio_combat_epoch_property_available = false
	_audio_combat_epoch_probe_complete = false
	_audio_combat_epoch_property_probe_count = 0
	_audio_previous_visual_state = ""
	_audio_previous_visual_frame = -1
	_audio_previous_facing = Vector2.INF

func _retire_cached_audio_owner() -> void:
	if _audio_owner_key.is_empty() or _audio_runtime_service == null: return
	var state: Dictionary = _audio.service_state(_audio_runtime_service.token)
	if not state.present or &"retire_monster_audio_owner" not in state.methods: return
	_audio.invoke_service(_audio_runtime_service.token, &"retire_monster_audio_owner", [_audio_owner_key, _id])

func audio_combat_epoch_property_probe_count_for_test() -> int:
	return _audio_combat_epoch_property_probe_count

func audio_service_lookup_count_for_test() -> int:
	return _audio_service_lookup_count

func draw_ellipse_shadow(radius_px: float, center_px := Vector2.ZERO) -> void:
	_emit_render(&"enemy_draw_ellipse_shadow", [radius_px, center_px])

func ground_footprint_indicator_radii() -> Vector2:
	return (
		WorldSpatialRulesScript.actor_footprint_radii_px(collision_radius_px)
		* TARGET_RING_FOOTPRINT_SCALE
	)

func ground_indicator_center() -> Vector2:
	# Targeting geometry owns an actor-local coordinate contract. Grounded
	# monsters always target the physics origin; visual alignment data may move
	# the sprite around that origin but must never move gameplay/UI targeting.
	# Flying/hovering profiles keep their explicit ground projection.
	var fallback := Vector2.ZERO
	return visual.target_ring_position(fallback) if visual != null else fallback

func ground_indicator_radii() -> Vector2:
	# Presentation-only crawling scale; never changes collision or attack reach.
	return MonsterTargetRingGeometryScript.resolve(monster_id, ground_footprint_indicator_radii())

func health_bar_anchor_y() -> float:
	var radius_px := 27.0 if is_boss else 16.0
	var fallback_y := -92.0 if bool(behavior_profile.get("largeClientBoss", false)) else -radius_px - 24.0
	return visual.health_bar_anchor_y(fallback_y) if visual != null else fallback_y

func name_label_anchor_y() -> float:
	return health_bar_anchor_y() - NAME_LABEL_SIZE.y - NAME_LABEL_HEALTH_BAR_GAP

func poison_indicator_anchor_y() -> float:
	return health_bar_anchor_y() + MonsterOverheadScript.HEALTH_BAR_HEIGHT + 5.0

func poison_indicator_center() -> Vector2:
	return Vector2(-POISON_INDICATOR_DOT_CENTER_OFFSET_X, poison_indicator_anchor_y())

func poison_indicator_rect() -> Rect2:
	var center := poison_indicator_center()
	return Rect2(
		center - Vector2.ONE * POISON_INDICATOR_DOT_RADIUS,
		Vector2.ONE * POISON_INDICATOR_DOT_RADIUS * 2.0
	)

func red_poison_indicator_anchor_y() -> float:
	return poison_indicator_anchor_y()

func red_poison_indicator_center() -> Vector2:
	return Vector2(POISON_INDICATOR_DOT_CENTER_OFFSET_X, red_poison_indicator_anchor_y())

func red_poison_indicator_rect() -> Rect2:
	var center := red_poison_indicator_center()
	return Rect2(
		center - Vector2.ONE * POISON_INDICATOR_DOT_RADIUS,
		Vector2.ONE * POISON_INDICATOR_DOT_RADIUS * 2.0
	)

func refresh_name_label_position() -> void:
	if _model.get_ref().presentation.has_overhead(): _emit_render(&"enemy_overhead_anchor_y", [health_bar_anchor_y()])

func set_audio_seed_for_test(seed_value: int) -> void:
	if _audio_rng == null:
		_audio_rng = RandomNumberGenerator.new()
	_audio_rng.seed = seed_value
	_audio_rng_initialized = true


## The service is resolved only when a semantic event is ready.  Successful
## lookups are shared by all EnemyActor instances. A miss installs one shared
## one-second negative cache so thousands of actors cannot group-scan every
## frame, while a later service (or a replacement after world teardown) is
## still discovered without a production reset hook.

func set_audio_service_cache_clock_for_test(now_msec: int) -> void:
	_audio_service_now_override_msec = now_msec

func should_draw_synthetic_ground_shadow() -> bool:
	return visual == null or visual.should_draw_procedural_fallback()

func _on_actual_audio_result(source_id: int, semantic: String, action_serial: int, life: int, result: Dictionary) -> void:
	if source_id!=_id or _model.get_ref()==null or _model.get_ref().current_life()!=life: return
	if semantic=="attack_start" and action_serial==_audio_attack_sequence:
		_audio_attack_start_accepted=str(result.get("status",""))=="played"
