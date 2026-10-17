extends RefCounted

const ActorLink := preload("res://scripts/gameplay/foundation/actor_link.gd")
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const AUDIO_MONSTER_HOOK_CONTRACT_ID := "skills.summon.audio_monster_identity.v1"
const AUDIO_MONSTER_ID_BY_SUMMON_ID := {"skeleton":145,"divine_beast":146}
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _registry: WeakRef
var _handle: WeakRef
var _model: WeakRef
var _host: Object
var _motion: WeakRef
var _screen_to_ground := Callable()
var _radius_gu := 0.0
var _visual_available := false
var _recording_enabled := false
var _red_poison: Variant = null
var _failed := false
var _ordinal := 0
var _facts: Array[Dictionary] = []
var _audio_death_emitted := false
var _audio_attack_sequence := 0
var _audio_attack_frame_sequence := -1
var _buff_signature := Vector2i(-1,-1)
var _graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")

var recording_enabled: bool:
	get: return _recording_enabled

func _init(core: RefCounted, registry: RefCounted, handle: Object, model: RefCounted, host: Object, screen_to_ground: Callable, radius_gu: float, visual_available: bool, observer_enabled: bool) -> void:
	_core = weakref(core)
	_registry = weakref(registry)
	_handle = weakref(handle)
	_model = weakref(model)
	_host = host
	_screen_to_ground = screen_to_ground
	_radius_gu = radius_gu
	_visual_available = visual_available
	_recording_enabled = observer_enabled

func owner_thread_id() -> int: return _owner

func _owned() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return OS.get_thread_caller_id() == _owner

func faulted() -> bool:
	return not _owned() or _failed or bool(_core.get_ref().call("actor_runtime_is_faulted", runtime_id()))

func fail(code: String, details: Dictionary) -> void:
	assert(_owned())
	_failed = true
	_core.get_ref().call("fault", code, details)

func bind_motion(motion: RefCounted) -> void:
	assert(_owned())
	_motion = weakref(motion)

func rebind_projection(screen_to_ground: Callable, radius_gu: float) -> bool:
	if faulted() or not screen_to_ground.is_valid() or not is_finite(radius_gu) or radius_gu < 0.0: return false
	_screen_to_ground = screen_to_ground
	_radius_gu = radius_gu
	return true

func runtime_id() -> int:
	assert(_owned())
	return _handle.get_ref().get_instance_id()

func publish_pose() -> bool:
	if faulted(): return false
	var screen: Vector2 = _motion.get_ref().position_screen_px()
	var ground: Variant = _screen_to_ground.call(screen)
	if not ground is Vector2 or not ground.is_finite() or not _handle.get_ref().set_pose(screen, ground, _radius_gu):
		fail("actor_pose_publication_failed", {"runtime_id":runtime_id(),"screen":screen,"ground":ground})
		return false
	if not bool(_core.get_ref().call("update_actor_spatial", runtime_id(), _handle.get_ref().runtime_actor_view())):
		fail("actor_spatial_publication_failed", {"runtime_id":runtime_id()})
		return false
	return true

func create_timer(delay_seconds: float, process_always := true, process_in_physics := false, ignore_time_scale := false) -> RefCounted:
	assert(_owned())
	if faulted(): return null
	# Forward all four SceneTreeTimer flags and admission directly; never tick a
	# parallel timer list. Native Host owns first debit, list cutoff and timeout.
	var timer: RefCounted = _host.call("create_timer", delay_seconds, process_always, process_in_physics, ignore_time_scale)
	if timer == null: fail("actor_timer_admission_failed", {"delay":delay_seconds})
	return timer

func is_present() -> bool:
	assert(_owned())
	var record: Object = _handle.get_ref()
	return record != null and record.runtime_object_is_present() and record.is_inside_world()

func is_retiring(link: RefCounted = null) -> bool:
	var record: Object = _record(link) if link != null else _handle.get_ref()
	return record == null or record.is_queued_for_retirement()

func unregister_combat_target() -> void:
	if faulted(): return
	if not bool(_core.get_ref().call("unregister_combat_target", runtime_id())):
		fail("actor_target_unregister_failed", {"runtime_id":runtime_id()})

func request_retirement() -> void:
	if faulted(): return
	# Queue only. WorldCore performs source-mapped removal/lease destruction.
	if not bool(_core.get_ref().call("queue_actor_retirement", runtime_id())):
		fail("actor_retirement_queue_failed", {"runtime_id":runtime_id()})

func keyboard_movement_vector() -> Vector2:
	assert(_owned())
	var value: Variant = _core.get_ref().call("player_keyboard_movement_vector", runtime_id())
	if not value is Vector2 or not value.is_finite():
		fail("actor_input_vector_invalid", {})
		return Vector2.ZERO
	return value

func _record(link: RefCounted) -> Object:
	assert(_owned())
	return link.resolve_record() if link != null else null

func capture_actor(record: Object) -> RefCounted:
	assert(_owned())
	return ActorLink.capture(_registry.get_ref(), record)

func capture_accepted_actor_ref() -> RefCounted:
	assert(_owned())
	return ActorRef.capture_domain(_registry.get_ref(), _handle.get_ref())

func resolve_model(link: RefCounted) -> Object:
	var record := _record(link)
	return record.model() if record != null else null

func actor_is_present(link: RefCounted) -> bool:
	var record := _record(link)
	# The original is_instance_valid check is NOT an inside-world/queued check.
	return record != null and record.runtime_object_is_present()

func is_enemy(link: RefCounted) -> bool:
	var record := _record(link)
	return record != null and record.kind() == &"enemy"

func actor_position_screen_px(link: RefCounted) -> Vector2:
	return _record(link).runtime_actor_view().position_screen_px

func position_ground_gu(link: RefCounted) -> Vector2:
	return _record(link).runtime_actor_view().position_ground_gu

func runtime_map_id(link: RefCounted) -> int:
	return _record(link).identity().world.runtime_map_id

func current_hp(link: RefCounted) -> int:
	return resolve_model(link).current_hp

func movement_facing(link: RefCounted) -> Vector2:
	return resolve_model(link).movement_facing

func facing(link: RefCounted) -> Vector2:
	return resolve_model(link).facing

func agility(link: RefCounted) -> int:
	return resolve_model(link).agility

func combat_transition_is_active(link: RefCounted) -> bool:
	return resolve_model(link).combat_transition_is_active()

func accepts_external_attack(link: RefCounted) -> bool:
	return resolve_model(link).accepts_external_attack_from(_handle.get_ref())

func enemy_combat_radius_gu(link: RefCounted) -> float:
	return maxf(0.0, float(_record(link).runtime_actor_view().combat_radius_gu)) if is_enemy(link) else 0.0

func apply_enemy_damage(target_model: Object, amount: int) -> void:
	if faulted(): return
	# Borrowed once by the original synchronous release. The caller deliberately
	# reads HP and monster level from THIS model after its death handler returns.
	target_model.take_damage(amount, _handle.get_ref())

func actor_view(id: int) -> Dictionary:
	assert(_owned())
	var record: Object = _registry.get_ref().resolve_runtime_actor(id)
	if record == null or not record.is_inside_world(): return {}
	return record.runtime_actor_view()

func available() -> bool:
	return not faulted() and bool(_core.get_ref().call("actor_spatial_available"))

func query_aabb_candidates(map_id: int, bounds: Rect2, padding: float) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if faulted(): return output
	var result: Variant = _core.get_ref().call("query_aabb_candidates", map_id, bounds, padding)
	if not result is Dictionary or result.get("ok") != true or not result.get("candidates") is Array:
		fail("actor_spatial_query_failed", {"result":result})
		return output
	for source: Variant in result.candidates:
		if not source is Dictionary or not source.get("actor_runtime_id") is int or not source.get("bounds_gu") is float or not source.get("stable_combat_order") is int:
			fail("actor_spatial_candidate_invalid", {})
			return []
		var record: Object = _registry.get_ref().resolve_runtime_actor(source.actor_runtime_id)
		if record == null:
			fail("actor_spatial_candidate_absent", {"runtime_id":source.actor_runtime_id})
			return []
		var row: Dictionary = source.duplicate(false)
		row["actor"] = capture_actor(record)
		if row.actor == null:
			fail("actor_spatial_candidate_lease_failed", {"runtime_id":source.actor_runtime_id})
			return []
		output.append(row)
	return output

func canonical_follow_landing_plan() -> Dictionary:
	assert(_owned())
	var result: Variant = _core.get_ref().call("canonical_summon_follow_landing_plan", runtime_id())
	if not result is Dictionary or not result.get("valid") is bool:
		fail("actor_landing_plan_invalid", {})
		return {"valid":false,"reason":"actor_landing_plan_invalid","defer_allowed":false}
	return result

func capture_follow_landing_authority() -> RefCounted:
	assert(_owned())
	return _core.get_ref().call("capture_follow_landing_authority", runtime_id())

func register_pending_arrival(authority: RefCounted) -> void:
	if faulted(): return
	if authority == null or not bool(_core.get_ref().call("register_pending_main_pet_arrival", authority, runtime_id())):
		fail("actor_pending_arrival_registration_failed", {})

func read_red_poison() -> Variant:
	assert(_owned())
	return _red_poison

func write_red_poison(value: Dictionary) -> void:
	assert(_owned())
	var captured: Dictionary = _graph.call("capture", value, true, false)
	if not captured.success:
		fail("actor_status_value_invalid", {})
		return
	_red_poison = captured.value

func _source_identity(source: Variant) -> Variant:
	if source == null or source is Dictionary or source is String or source is int: return source
	if source is RefCounted and source.has_method("identity"): return source.identity()
	if source is Object and source.has_method("identity"): return source.identity()
	fail("actor_damage_source_not_numeric", {})
	return null

func call_damage_write_hook(_hook: Callable, _identity: Variant, _damage: int) -> Variant:
	# Test-only legacy write hooks must not become an alternate S HP authority.
	fail("actor_legacy_damage_write_hook_forbidden", {})
	return 0

func record_hp_mutation(amount: int, hp_before: int, hp_after: int, damage_type: String, source: Variant = null, mp_before := -1, mp_after := -1) -> void:
	if not _recording_enabled: return
	_fact("damage_hp_mutation", {"amount":amount,"hp_before":hp_before,"hp_after":hp_after,"damage_type":damage_type,"source":_source_identity(source),"mp_before":mp_before,"mp_after":mp_after})

func record_terminal(source: Variant, kind: String, reason: String, hp_before := -1, hp_after := -1, mp_before := -1, mp_after := -1) -> void:
	if not _recording_enabled: return
	_fact("damage_terminal", {"source":_source_identity(source),"kind":kind,"reason":reason,"hp_before":hp_before,"hp_after":hp_after,"mp_before":mp_before,"mp_after":mp_after})

func _fact(event: String, payload: Dictionary) -> void:
	if faulted(): return
	if _handle.get_ref().kind() == &"player" and event in ["redraw","play_hit","play_death","play_action","refresh_profession","stats_changed","resources_changed"]:
		var projection: Dictionary = _core.get_ref().capture_original_actor_visual_projection(runtime_id(),false,0.0)
		if projection.is_empty():
			fail("original_player_visual_capture_missing",{"event":event}); return
		payload = payload.duplicate(true)
		payload["visual_projection"] = projection
	var captured: Dictionary = _graph.call("capture", payload, true, false)
	if not captured.success:
		fail("actor_fact_not_plain", {"event":event})
		return
	_ordinal += 1
	_facts.append({"runtime_id":runtime_id(),"actor_ordinal":_ordinal,"event":event,"payload":captured.value})
	flush_facts()

func flush_facts() -> bool:
	assert(_owned())
	while not _facts.is_empty():
		var fact: Dictionary = _facts.front()
		if not bool(_core.get_ref().call("emit_actor_fact", fact.runtime_id, fact.event, {"actor_ordinal":fact.actor_ordinal,"value":fact.payload})):
			return false
		_facts.pop_front()
	return true

func pending_fact_count() -> int:
	assert(_owned())
	return _facts.size()

func has_visual() -> bool:
	assert(_owned())
	return _visual_available

func redraw() -> void: _fact("redraw", {})
func play_hit(duration: float) -> void: _fact("play_hit", {"duration":duration})
func play_death() -> void: _fact("play_death", {})
func play_action(action: String, duration: float) -> void: _fact("play_action", {"action":action,"duration":duration})
func refresh_profession() -> void: _fact("refresh_profession", {"profession_id":_model.get_ref().profile.profession_id})
func update_stealth_visual() -> void: _fact("update_stealth_visual", {"stealthed":_model.get_ref().is_stealthed()})
func update_fire_visual(delta: float) -> void: _fact("update_fire_visual", {"delta":delta})
func reset_fire_visual() -> void: _fact("reset_fire_visual", {})
func start_fire_visual() -> void: _fact("start_fire_visual", {})
func poll_visual_activation() -> void: _fact("poll_visual_activation", {})
func apply_visual_frame(state: String, direction: int, frame: int) -> void: _fact("apply_visual_frame", {"state":state,"direction":direction,"frame":frame})
func set_visible(value: bool) -> void: _fact("set_visible", {"visible":value})

func _current_buff_signature() -> Vector2i:
	var model: Object = _model.get_ref()
	return Vector2i(ceili(model.ac_buff_remaining_seconds) if model.ac_buff_bonus > 0 and model.ac_buff_remaining_seconds > 0.0 else 0,
		ceili(model.mac_buff_remaining_seconds) if model.mac_buff_bonus > 0 and model.mac_buff_remaining_seconds > 0.0 else 0)

func refresh_buff_draw_signature() -> void:
	assert(_owned())
	_buff_signature = _current_buff_signature()

func refresh_buff_redraw_if_needed() -> void:
	assert(_owned())
	var signature := _current_buff_signature()
	if signature != _buff_signature:
		_buff_signature = signature
		redraw()

func reset_audio_state() -> void:
	assert(_owned())
	_audio_death_emitted = false
	_audio_attack_sequence = 0
	_audio_attack_frame_sequence = -1
	_fact("reset_audio_state", {})

func audio_attack_started() -> void:
	assert(_owned())
	_audio_attack_sequence += 1
	_audio_attack_frame_sequence = -1
	_summon_audio("attack_start")

func audio_attack_frame() -> void:
	assert(_owned())
	if _audio_attack_sequence <= 0 or _audio_attack_frame_sequence == _audio_attack_sequence: return
	_audio_attack_frame_sequence = _audio_attack_sequence
	_summon_audio("attack_frame")

func audio_death_once() -> void:
	assert(_owned())
	if _audio_death_emitted: return
	_audio_death_emitted = true
	_summon_audio("death", true)

func audio_hurt() -> void: _summon_audio("hurt")

func _summon_audio(semantic_event: String, allow_death := false) -> void:
	if faulted(): return
	var model: Object = _model.get_ref()
	if not AUDIO_MONSTER_ID_BY_SUMMON_ID.has(model.summon_id):
		fail("summon_audio_identity_unknown", {"summon_id":model.summon_id})
		return
	# M applies the original viewport/visible/process-mode audibility guard.
	# The stable identity and already-accepted phase travel as frozen values.
	_fact("audio_monster_event", {"source":"summon_actor","contract_id":AUDIO_MONSTER_HOOK_CONTRACT_ID,
		"monster_id":AUDIO_MONSTER_ID_BY_SUMMON_ID[model.summon_id],"summon_id":model.summon_id,"skill_id":model.skill_id,
		"runtime_map_id":model.runtime_map_id,"semantic_event":semantic_event,"allow_death":allow_death,
		"sequence":_audio_attack_sequence,"position_screen_px":_motion.get_ref().position_screen_px()})

func on_stats_changed(hp: int, maximum: int) -> void:
	if faulted(): return
	_core.get_ref().call("on_player_stats_changed", runtime_id(), hp, maximum)
	_fact("stats_changed", {"hp":hp,"max_hp":maximum})

func on_resources_changed(hp: int, max_hp: int, mp: int, max_mp: int) -> void:
	if faulted(): return
	_core.get_ref().call("on_player_resources_changed", runtime_id(), hp, max_hp, mp, max_mp)
	_fact("resources_changed", {"hp":hp,"max_hp":max_hp,"mp":mp,"max_mp":max_mp})

func on_passive_wakeup_changed() -> void:
	if faulted(): return
	_core.get_ref().call("on_actor_passive_wakeup_changed", runtime_id())

func on_attack_requested(origin: Vector2, direction: Vector2, damage: int) -> void:
	if faulted(): return
	_core.get_ref().call("on_player_attack_requested", runtime_id(), _model.get_ref(), origin, direction, damage)

func on_skill_requested(skill: String, origin: Vector2, direction: Vector2, damage: int) -> void:
	if faulted(): return
	_core.get_ref().call("on_player_skill_requested", runtime_id(), _model.get_ref(), skill, origin, direction, damage)

func on_death_requested() -> void:
	if faulted(): return
	_core.get_ref().call("on_player_death_requested", runtime_id())

func on_movement_performed(position: Vector2, facing_value: Vector2) -> void:
	if faulted(): return
	if not publish_pose(): return
	_core.get_ref().call("on_player_movement_performed", runtime_id(), position, facing_value)
	_fact("movement_performed", {"position":position,"facing":facing_value})

func on_skill_cast_started(skill: String) -> void:
	if faulted(): return
	_core.get_ref().call("on_player_skill_cast_started", runtime_id(), skill)
	_fact("skill_cast_started", {"skill_id":skill})

func on_warrior_skill_state_changed(skill: String, enabled: bool, message: String) -> void:
	if faulted(): return
	_core.get_ref().call("on_player_warrior_skill_state_changed", runtime_id(), skill, enabled, message)
	_fact("warrior_skill_state_changed", {"skill_id":skill,"enabled":enabled,"message":message})

func on_summon_state_changed(previous: int, current: int) -> void:
	if faulted(): return
	_core.get_ref().call("on_summon_state_changed", runtime_id(), previous, current)
	_fact("summon_state_changed", {"previous":previous,"current":current})

func configure_shared_index(index: RefCounted) -> void:
	assert(_owned() and is_same(index, _core.get_ref().spatial), "original summon must bind the sole world spatial index")
