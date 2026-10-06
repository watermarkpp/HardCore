extends "res://tests/framework/natural_effect_lifecycle_test.gd"

const DamageObserver := preload("res://scripts/damage_ledger_observer.gd")
const MANA_SUPPLY_ID := "hc.service_item.000663"
const MANA_SUPPLY_SEED_COUNT := 20
const MANA_SUPPLY_TRIGGER_MP := 250
const MAX_SUPPLY_INPUTS := 32
const MAX_RESTORE_EVENTS := 512

## Test-owned boundary observation. Both overrides call the real Root exactly
## once; no source identity is inferred for later asynchronous damage.
class ObservedSustainedRoot extends ObservedChildRoot:
	var skill_release_rows: Array[Dictionary] = []
	var canonical_release_rows: Array[Dictionary] = []
	var release_observation_overflowed := false

	# Observer state belongs only to this fixture. No actor, lease or plan is retained.
	var observer_tail_owner: WeakRef
	var observer_aim_row: Dictionary = {}
	var last_entry_gate_observation: Dictionary = {}
	var _observer_input_active := false
	var _observer_canonical_active := false
	var _observer_tail_geometry: Dictionary = {}
	var _observer_extra_usec := 0

	func _try_release_skill(skill_name: String, show_failure := true) -> StringName:
		var observation_started := Time.get_ticks_usec()
		_observer_input_active = skill_name in ["hc.skill.wizard.ice_storm","wizard.ice_storm"]
		_observer_extra_usec = 0
		last_entry_gate_observation = {"schema":"sustained.entry_gate.v1", "scope":"wizard.ice_storm", "input_skill_name":skill_name,
			"scope_supported":_observer_input_active,
			"before":_observer_player_fields(), "resource_boundary_seen":false,
			"preflight_seen":false, "admission_seen":false,
			"windup_timer":{"status":"MISSING", "reason":"Player creates an unretained SceneTreeTimer at player.gd:1283"}}
		_observer_extra_usec += Time.get_ticks_usec()-observation_started
		var result := super._try_release_skill(skill_name,show_failure)
		observation_started = Time.get_ticks_usec()
		last_entry_gate_observation["after"] = _observer_player_fields()
		last_entry_gate_observation["result"] = str(result)
		if result == &"busy" and bool(last_entry_gate_observation.scope_supported):
			if bool(last_entry_gate_observation.get("admission_seen",false)):
				last_entry_gate_observation["busy_boundary"] = "request_skill:configuration_admission" if not bool(last_entry_gate_observation.get("admission_success",false)) else "MISSING:busy_after_successful_admission"
			elif bool(last_entry_gate_observation.get("preflight_seen",false)):
				last_entry_gate_observation["busy_boundary"] = "request_skill:world_preflight" if not bool(last_entry_gate_observation.get("preflight_result",false)) else "request_skill:configuration_accept_before_admission"
			else:
				last_entry_gate_observation["busy_boundary"] = "can_request_skill_or_request_skill_before_preflight"
		_observer_input_active = false
		_observer_extra_usec += Time.get_ticks_usec()-observation_started
		last_entry_gate_observation["measured_observer_block_usec"] = _observer_extra_usec
		return result

	func _canonical_resource_context(stable_skill_id: String, configuration: RefCounted = null) -> Dictionary:
		var result := super._canonical_resource_context(stable_skill_id,configuration)
		if _observer_input_active:
			var observation_started := Time.get_ticks_usec()
			last_entry_gate_observation["resource_boundary_seen"] = true
			last_entry_gate_observation["stable_skill_id"] = stable_skill_id
			var owner_fields := _observer_player_fields()
			last_entry_gate_observation["before_can_request_owner_fields"] = owner_fields
			# The actual capture already loaded this document. Fail closed if absent:
			# action_configuration_versions() would otherwise load/build Loader caches.
			var configuration_current: Variant = null
			if configuration != null and not SkillDataLoaderScript._document.is_empty() \
				and player.hc_action_configuration_identity == Callable(self,"_action_configuration_identity"):
				var versions := PlayerState.action_configuration_versions()
				var identity := _action_configuration_identity()
				configuration_current = configuration.current_before_accept(
					versions,identity)
				last_entry_gate_observation["configuration_versions_read"] = versions
				last_entry_gate_observation["actor_identity_read"] = identity
			last_entry_gate_observation["configuration_current_read"] = configuration_current
			last_entry_gate_observation["first_false_owner_gate"] = _observer_first_false_gate(owner_fields,configuration_current)
			last_entry_gate_observation["gate_read_status"] = "owner_reads_before_check_not_a_second_can_request_call"
			_observer_extra_usec += Time.get_ticks_usec()-observation_started
		return result

	func _hc_skill_preflight(stable_skill_id: String, target_id: int) -> bool:
		var result := super._hc_skill_preflight(stable_skill_id,target_id)
		if _observer_input_active:
			var observation_started := Time.get_ticks_usec()
			last_entry_gate_observation["preflight_seen"] = true
			last_entry_gate_observation["preflight_result"] = result
			last_entry_gate_observation["preflight_target_id"] = target_id
			_observer_extra_usec += Time.get_ticks_usec()-observation_started
		return result

	func _reserve_feature_action(configuration: RefCounted) -> Dictionary:
		var result := super._reserve_feature_action(configuration)
		if _observer_input_active:
			var observation_started := Time.get_ticks_usec()
			last_entry_gate_observation["admission_seen"] = true
			last_entry_gate_observation["admission_success"] = bool(result.get("success",false))
			last_entry_gate_observation["admission_reason"] = str(result.get("reason",""))
			last_entry_gate_observation["admission_has_reservation"] = result.get("reservation") != null
			_observer_extra_usec += Time.get_ticks_usec()-observation_started
		return result

	func _observer_player_fields() -> Dictionary:
		return {"wall_usec":Time.get_ticks_usec(), "simulation_usec":_time_domains.simulation_usec(),
			"physics_frame":Engine.get_physics_frames(), "process_frame":Engine.get_process_frames(),
			"attack_timer_seconds":player._attack_timer, "attack_action_timer_seconds":player._attack_action_timer,
			"struck_lock_seconds":player._struck_lock_remaining,
			"struck_reaction_lock_seconds":player._struck_reaction_lock_remaining, "control_seconds":player.control_time,
			"dead":player._dead, "hp":player.current_hp, "mp":player.current_mp,
			"combat_transition_active":not player._combat_transition_token.is_empty(), "combat_epoch":player.combat_epoch,
			"skill_cooldown_seconds":float(player._skill_cooldown_remaining.get("wizard.ice_storm",0.0)),
			"skill_cooldown_remaining_ms":player.skill_cooldown_remaining_ms("wizard.ice_storm"),
			"melee_can_start_attack_read":player.can_start_attack(),
			"pending_action_id":player._pending_combat_action_id, "pending_action_active":player._pending_combat_action_active,
			"pending_action_committed":player._pending_combat_action_committed, "pending_action_epoch":player._pending_combat_action_epoch,
			"pending_action_kind":player._pending_combat_action_kind,
			"accepted_release_producer_count":player._accepted_release_producers.size()}

	func _observer_first_false_gate(fields: Dictionary, configuration_current: Variant) -> String:
		# Only the fixed ice-storm input is covered. This is a read-only branch
		# explanation, never an eligibility/planner authority or actual Player return.
		if configuration_current == null: return "MISSING:configuration_current"
		if not bool(configuration_current): return "configuration_current:player.gd:509"
		if float(fields.struck_lock_seconds)>0.0 or float(fields.struck_reaction_lock_seconds)>0.0 \
			or float(fields.control_seconds)>0.0 or bool(fields.dead) or int(fields.hp)<=0 or bool(fields.combat_transition_active):
			return "life_or_control_or_struck:player.gd:513"
		if float(fields.attack_timer_seconds)>0.0: return "attack_timer:player.gd:517"
		if int(fields.skill_cooldown_remaining_ms)>0: return "skill_cooldown:player.gd:522"
		return "none_of_observed_owner_gates:do_not_infer_ready"

	func _observer_tail_state() -> Dictionary:
		var tail := observer_tail_owner.get_ref() as EnemyActor if observer_tail_owner != null else null
		if not is_instance_valid(tail): return {"status":"MISSING", "reason":"tail_weak_owner_not_live"}
		var point := tail.global_position
		var result := {"status":"PASS", "runtime_id":tail.get_instance_id(),
			"wall_usec":Time.get_ticks_usec(), "simulation_usec":_time_domains.simulation_usec(),
			"physics_frame":Engine.get_physics_frames(), "process_frame":Engine.get_process_frames(),
			"slot":str(tail.get_meta("spawn_context",{}).get("spawn_slot_id","")),
			"life":int(tail.get_meta("hc_combat_life_epoch",0)), "generation":int(tail.get_meta("zone_generation",-1)),
			"hp":tail.current_hp, "max_hp":tail.max_hp, "combat_radius_gu":tail.combat_radius_gu,
			"inside_tree":tail.is_inside_tree(), "queued_for_deletion":tail.is_queued_for_deletion(),
			"screen_position_px":[point.x,point.y], "projection_status":"MISSING"}
		# Read only an already-resolved formal profile. Never resolve/load a map,
		# refresh cache identity, increment a projection counter or use a fallback.
		var cache_key := "%d|0" % current_map_id
		var profile: Dictionary = _projection_profile_cache.get(cache_key,{})
		if not reference_audit_mode and not _projection_profile_cache_audit_mode \
			and bool(profile.get("success",false)) and int(profile.get("runtime_map_id",-1)) == current_map_id \
			and str(profile.get("policy","")) == "map_editor_runtime_absolute" \
			and MapEditorRuntimeBridgeScript._runtime_cache.has(current_map_id) \
			and is_same(_projection_profile_runtime_identity_cache.get(cache_key),MapEditorRuntimeBridgeScript._runtime_cache[current_map_id]):
			var projection: Callable = profile.get("screen_to_ground",Callable())
			if projection.is_valid():
				var ground: Vector2 = projection.call(point)
				if ground.is_finite():
					result["runtime_map_absolute_ground_gu"] = [ground.x,ground.y]
					result["projection_status"] = "PASS:existing_formal_cache_math"
		return result

	func _aoe_query_enemy_candidates_aabb(plan: Dictionary, bounds_ground_gu: Rect2, allow_reference_fallback := true) -> bool:
		var result := super._aoe_query_enemy_candidates_aabb(plan,bounds_ground_gu,allow_reference_fallback)
		if _observer_canonical_active:
			var observation_started := Time.get_ticks_usec()
			var tail := observer_tail_owner.get_ref() as EnemyActor if observer_tail_owner != null else null
			_observer_tail_geometry["query_call_count"] = int(_observer_tail_geometry.get("query_call_count",0))+1
			var rows: Array = _observer_tail_geometry.query_rows
			if rows.size()<4:
				rows.append({"query_result":result, "allow_reference_fallback":allow_reference_fallback,
					"candidate_count":_aoe_candidate_scratch.size(), "tail_in_actual_candidates":_aoe_candidate_scratch.has(tail) if is_instance_valid(tail) else false,
					"bounds_ground_gu":[bounds_ground_gu.position.x,bounds_ground_gu.position.y,bounds_ground_gu.size.x,bounds_ground_gu.size.y],
					"tail_after_actual_query":_observer_tail_state(), "actual_frozen_snapshot":_observer_frozen_cell_union(plan)})
			else: _observer_tail_geometry["detail_overflowed"] = true
			_observer_extra_usec += Time.get_ticks_usec()-observation_started
		return result

	func _aoe_validated_snapshot_intersects(plan: Dictionary, enemy: EnemyActor) -> bool:
		var result := super._aoe_validated_snapshot_intersects(plan,enemy)
		if _observer_canonical_active and observer_tail_owner != null and enemy == observer_tail_owner.get_ref():
			var observation_started := Time.get_ticks_usec()
			_observer_tail_geometry["exact_tail_call_count"] = int(_observer_tail_geometry.get("exact_tail_call_count",0))+1
			var rows: Array = _observer_tail_geometry.exact_rows
			if rows.size()<4:
				rows.append({"actual_exact_result":result, "plan_id":str(plan.get("plan_id","")),
					"plan_release_id":str(plan.get("release_id","")), "tail_after_actual_exact":_observer_tail_state(), "actual_frozen_snapshot":_observer_frozen_cell_union(plan)})
			else: _observer_tail_geometry["detail_overflowed"] = true
			_observer_extra_usec += Time.get_ticks_usec()-observation_started
		return result

	func _observer_frozen_cell_union(plan: Dictionary) -> Dictionary:
		var snapshot := _aoe_plan_snapshot(plan)
		var frozen: Dictionary = {}
		for key: String in ["snapshot_id","skill_id","release_id","shape_type","shape_contract_id","schema_version","coordinate_space","runtime_map_id","projection_contract_id","origin_ground_gu","projection_origin_ground_gu","cell_origin_offset_gu","created_by"]:
			frozen[key] = _plain_observation(snapshot.get(key))
		var polygons: Variant = snapshot.get("polygons_ground_gu",[])
		var cells: Variant = snapshot.get("geometry_cells_grid_steps",[])
		# Fixed ice storm has 9 quadrilaterals. Unexpected shape stays MISSING;
		# observer caps do not truncate production geometry or target selection.
		if str(snapshot.get("shape_type","")) != "cell_union":
			frozen["geometry_detail_status"] = "MISSING:outside_fixed_cell_union_scope"
		elif polygons is Array and cells is Array and polygons.size()<=16 and cells.size()<=16:
			var bounded := true
			for polygon: Variant in polygons:
				if not polygon is PackedVector2Array or polygon.size()>8: bounded = false
			for cell: Variant in cells:
				if not cell is Vector2i: bounded = false
			if bounded:
				frozen["polygons_ground_gu"] = _plain_observation(polygons)
				frozen["geometry_cells_grid_steps"] = _plain_observation(cells)
				frozen["geometry_detail_status"] = "PASS:bounded_actual_snapshot_copy"
			else: frozen["geometry_detail_status"] = "MISSING:unexpected_polygon_or_cell_size_or_type"
		else: frozen["geometry_detail_status"] = "MISSING:unexpected_cell_union_size_or_type"
		return frozen

	func _on_player_skill(skill_name: String, origin: Vector2, direction: Vector2, damage: int) -> void:
		var context: Dictionary = player.consume_skill_context()
		var geometry: Dictionary = context.get("release_geometry",{})
		var started := Time.get_ticks_usec()
		var simulation: int = _time_domains.simulation_usec()
		var physics := Engine.get_physics_frames()
		var process := Engine.get_process_frames()
		var plan_start := canonical_release_rows.size()
		var event_start := DamageObserver.events.size()
		var target_id := int(geometry.get("locked_target_instance_id",0))
		var target_node := instance_from_id(target_id) if target_id>0 else null
		var target_identity: Dictionary = {}
		if is_instance_valid(target_node) and target_node is EnemyActor:
			var canonical_point: Vector2 = _canonical_screen_px_to_ground_gu(target_node.global_position)
			target_identity = {"runtime_id":target_id,"life":int(target_node.get_meta("hc_combat_life_epoch",0)),
				"generation":int(target_node.get_meta("zone_generation",-1)),"hp":target_node.current_hp,
				"screen_position_px":[target_node.global_position.x,target_node.global_position.y],
				"runtime_map_absolute_ground_gu":[canonical_point.x,canonical_point.y],
				"slot":str(target_node.get_meta("spawn_context",{}).get("spawn_slot_id","")),
				"inside_tree":target_node.is_inside_tree(),"queued_for_deletion":target_node.is_queued_for_deletion()}
		var tail_at_signal := _observer_tail_state()
		super._on_player_skill(skill_name,origin,direction,damage)
		if skill_release_rows.size()>=128:
			release_observation_overflowed = true
			return
		skill_release_rows.append({"release_id":str(geometry.get("release_id","")),"skill_name":skill_name,
			"wall_started_usec":started,"wall_finished_usec":Time.get_ticks_usec(),"simulation_usec":simulation,
			"physics_frame":physics,"process_frame":process,"configuration_present":context.get("action_config_lease")!=null,
			"release_geometry":_plain_observation(geometry),"selected_target_at_signal":target_identity,
			"tail_at_signal":tail_at_signal,
			"canonical_row_start":plan_start,"canonical_row_end":canonical_release_rows.size(),
			"damage_event_start":event_start,"damage_event_end":DamageObserver.events.size()})

	func _execute_canonical_skill(skill_name: String, origin: Vector2, direction: Vector2, client_damage: int,
		extra_target_context: Dictionary = {}, apply_effects := true, authoritative_cast_target := false,
		configuration: RefCounted = null) -> Dictionary:
		var started := Time.get_ticks_usec()
		var event_start := DamageObserver.events.size()
		var simulation: int = _time_domains.simulation_usec()
		var mp_before: int = player.current_mp
		var observation_started := Time.get_ticks_usec()
		var prior_canonical_active := _observer_canonical_active
		var prior_tail_geometry := _observer_tail_geometry
		var prior_observer_usec := _observer_extra_usec
		_observer_extra_usec = 0
		_observer_canonical_active = canonical_release_rows.size()<128
		_observer_tail_geometry = {"schema":"sustained.tail_geometry.v1", "query_call_count":0,
			"exact_tail_call_count":0, "query_rows":[], "exact_rows":[], "detail_overflowed":false,
			"tail_before_canonical":_observer_tail_state(), "exact_if_absent":"NOT_RUN:no_actual_tail_exact_callback"}
		_observer_extra_usec += Time.get_ticks_usec()-observation_started
		var result := super._execute_canonical_skill(skill_name,origin,direction,client_damage,
			extra_target_context,apply_effects,authoritative_cast_target,configuration)
		observation_started = Time.get_ticks_usec()
		_observer_tail_geometry["tail_after_canonical"] = _observer_tail_state()
		_observer_extra_usec += Time.get_ticks_usec()-observation_started
		_observer_tail_geometry["measured_observer_block_usec"] = _observer_extra_usec
		var tail_geometry_row := _observer_tail_geometry
		_observer_canonical_active = prior_canonical_active
		_observer_tail_geometry = prior_tail_geometry
		_observer_extra_usec = prior_observer_usec
		if canonical_release_rows.size()<128:
			var plan: Dictionary = result.get("canonical_plan",{})
			var execution: Dictionary = result.get("execution_result",{})
			canonical_release_rows.append({"release_id":str(extra_target_context.get("release_id","")),
				"skill_name":skill_name,"wall_started_usec":started,"wall_finished_usec":Time.get_ticks_usec(),
				"simulation_usec":simulation,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),
				"accepted":bool(result.get("accepted",false)),"effect_success":bool(result.get("effect_success",false)),
				"reason":str(result.get("reason","")),"mp_before":mp_before,"mp_after":player.current_mp,
				"plan_id":str(plan.get("plan_id","")),"plan_hash":str(plan.get("plan_hash","")),
				"plan_release_id":str(plan.get("release_id","")),"snapshot":_plain_observation(plan.get("canonical_snapshot",{})),
				"geometry_cells":_plain_observation(plan.get("geometry_cells",[])),
				"effective_geometry_cells":_plain_observation(plan.get("effective_geometry_cells",[])),
				"tail_geometry_observation":tail_geometry_row,
				"damage_results":_plain_observation(execution.get("damage_results",[])),
				"damage_event_start":event_start,"damage_event_end":DamageObserver.events.size()})
		else: release_observation_overflowed = true
		return result

	func _plain_observation(value: Variant, depth := 0) -> Variant:
		if depth>20:
			release_observation_overflowed = true
			return {"unrepresented":"depth_limit"}
		if value is Vector2 or value is Vector2i: return [value.x,value.y]
		if value is Dictionary:
			var result: Dictionary = {}
			for key: Variant in value: result[str(key)] = _plain_observation(value[key],depth+1)
			return result
		if value is Array or value is PackedVector2Array:
			var result: Array = []
			for entry: Variant in value: result.append(_plain_observation(entry,depth+1))
			return result
		if value==null or value is bool or value is int or value is float or value is String or value is StringName: return value
		return {"unrepresented_type":type_string(typeof(value))}

## Same-process, same-world continuation of the existing natural input fixture.
## Production clocks, pumps, accepted promises, HP and MP are never reset.
var completed_rounds: Array[Dictionary] = []
var round_death_base := 0
var round_peak_states := 0
var round_peak_evidence: Dictionary = {}
var spawned_owners: Array[WeakRef] = []
var boundary_spans: Array[Dictionary] = []
var action_observations: Array[Dictionary] = []
var action_observation_overflowed := false
var profile_cap_observations: Array[Dictionary] = []
var profile_cap_observation_overflowed := false
var death_collision_observations: Array[Dictionary] = []
var original_damage_recording := false
var supply_catalog: Dictionary = {}
var supply_record: Dictionary = {}
var supply_recovery_profile: Dictionary = {}
var supply_initial_count := 0
var supply_seed_receipts: Array[Dictionary] = []
var supply_inputs: Array[Dictionary] = []
var supply_input_overflowed := false
var supply_last_use_frame := -1
var supply_successes := 0
var supply_out_of_stock_reported := false
var supply_restore_events: Array[Dictionary] = []
var supply_restore_overflowed := false
var supply_restored_mana := 0
var supply_last_signal_mp := 0
var supply_last_signal_pending := 0
var supply_last_signal_max_mp := 0
var observed_non_cap_mp_decrease := 0
var observed_mp_cap_removal := 0
var mp_cap_events: Array[Dictionary] = []
var mp_cap_observation_overflowed := false

func _scenario() -> String:
	return "natural_sustained_chain" if periodic_children else "natural_sustained_resource"

func _ready() -> void:
	report_path = "res://outputs/test_logs/framework/"+_scenario()+"_trace.json"
	expected_path = "res://outputs/test_logs/framework/"+_scenario()+"_expected.json"
	process_priority = 10000
	_run.call_deferred()

func _process(delta: float) -> void:
	var previous_size := samples.size()
	var previous_wall: int = previous_frame_usec
	super._process(delta)
	# The synchronous resource signal records each real delayed-restore tick;
	# synchronize here as well if Player discarded a remaining queue at its cap.
	if is_instance_valid(game) and is_instance_valid(game.player):
		supply_last_signal_mp = game.player.current_mp
		supply_last_signal_pending = game.player._pending_potion_mana
		supply_last_signal_max_mp = game.player.max_mp
	if not observing or runtime == null: return
	if runtime.active_count() > round_peak_states:
		round_peak_states = runtime.active_count()
		round_peak_evidence = _capture_state_cohort()
	if samples.size() > previous_size:
		samples[-1]["round"] = completed_rounds.size()
		samples[-1]["wall_start_usec"] = previous_wall
		samples[-1]["wall_end_usec"] = previous_frame_usec
		samples[-1]["process_frame"] = Engine.get_process_frames()
		samples[-1]["physics_frame"] = Engine.get_physics_frames()
		samples[-1]["engine_process_usec"] = int(Performance.get_monitor(Performance.TIME_PROCESS)*1000000.0)
		samples[-1]["engine_physics_usec"] = int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000.0)

func _run() -> void:
	check(resource_backed and not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata"),
		"sustained natural fixture owns an isolated real resource-backed profile")
	PlayerState.begin_startup_save_upgrade()
	var startup: bool = PlayerState.finish_startup_save_upgrade()
	var profile_name := "持续周期连锁" if periodic_children else "持续资源战斗"
	var creation: String = PlayerState.create_character(profile_name,"hc.profession.wizard") if startup else "startup not ready"
	check(startup and creation.is_empty(),"real startup and new production profile: "+creation)
	if not startup or not creation.is_empty(): _finish(); return
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.equipment["hc.slot.weapon"] = Drop.create_instance(GameData.get_item_record({"item_id":85}),"sustained:weapon")
	PlayerState.recalculate_stats(false)
	# Service 663 is a registered consumable, not an equipment drop instance.
	# Receive twenty exact typed records without an intermediate save. The
	# existing single baseline checkpoint below is the production writer.
	supply_catalog = GameData.get_entity_record(MANA_SUPPLY_ID)
	check(not supply_catalog.is_empty() and GameData.item_entity_id(supply_catalog) == MANA_SUPPLY_ID
		and int(supply_catalog.get("serviceIndex", -1)) == 663
		and str(supply_catalog.get("kind", "")) == "consumable"
		and str(supply_catalog.get("useEffect", "")) == "delayed_restore"
		and int(supply_catalog.get("restoreHealth", -1)) == 0
		and int(supply_catalog.get("restoreMana", -1)) == 180,
		"registered service 663 is the exact delayed MP-only 180 potion")
	if not failures.is_empty(): _finish(); return
	supply_record = {"service_index":int(supply_catalog.serviceIndex),
		"name":str(supply_catalog.name),"count":1}
	check(GameData.item_entity_id(supply_record) == MANA_SUPPLY_ID,
		"baseline inventory record carries the exact registered service identity")
	if not failures.is_empty(): _finish(); return
	supply_initial_count = PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
	var all_received := true
	for seed_index in MANA_SUPPLY_SEED_COUNT:
		var receipt: Dictionary = PlayerState.receive_record(supply_record.duplicate(true), false)
		supply_seed_receipts.append({"index":seed_index,"success":bool(receipt.get("success",false)),
			"reason":str(receipt.get("reason",""))})
		all_received = all_received and bool(receipt.get("success",false))
		if not all_received: break
	check(all_received and supply_seed_receipts.size() == MANA_SUPPLY_SEED_COUNT
		and PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID) == supply_initial_count + MANA_SUPPLY_SEED_COUNT,
		"twenty typed potions enter the one baseline profile without an interim writer")
	if not failures.is_empty(): _finish(); return
	check(PlayerState.save_game(true,true,true),"real writer saves baseline equipment, skill and exact twenty-potion supply")
	if not failures.is_empty(): _finish(); return
	var binding: Dictionary = PlayerState.assign_quick_item_slot(0, MANA_SUPPLY_ID)
	check(bool(binding.get("ok",false)) and PlayerState.quick_item_slots[0] == MANA_SUPPLY_ID,
		"production binding writer saves exact service identity in quick slot zero")
	if not failures.is_empty(): _finish(); return
	supply_recovery_profile = GameData.potion_recovery_profile(PlayerState.level, 0, 180, "delayed_restore")
	check(str(supply_recovery_profile.get("effect_type", "")) == "delayed_restore"
		and int(supply_recovery_profile.get("total_restore_mana", 0)) == 180
		and int(supply_recovery_profile.get("tick_amount", 0)) > 0,
		"formal recovery profile describes delayed Player ticks without a fixture refund")
	if not failures.is_empty(): _finish(); return
	var profile: String = PlayerState.active_profile_id
	var xp_before: int = PlayerState.experience
	var registry := "res://assets/data/features/validation/natural_periodic_chain_registry.json" if periodic_children else "res://assets/data/features/validation/resource_natural_registry.json"
	check(await ContentLayers.reload_feature_catalog_async(registry),"existing default-off authoring package prepares through the formal service")
	resource_owner = weakref(ContentLayers.feature_configuration().resource_lease)
	check(resource_owner.get_ref() != null,"one prepared source closure owns the entire continuous run")
	if resource_owner.get_ref() == null: _finish(); return
	get_tree().node_added.connect(_observe_spawn)
	game = ObservedSustainedRoot.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"one actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	game._audio_runtime_service.event_started.connect(_observe_feature_audio)
	if periodic_children:
		check(await ContentLayers.set_feature_module_enabled_async("hc.validation.natural_periodic_chain",true),"READY enables the existing finite periodic-death child module")
	var event: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(PlayerState.feature_errors.is_empty() and event.size() == (4 if periodic_children else 3),"real equipment, learned skill and rule qualify three ignition sources and only the declared child subscription")
	if event.size() != (4 if periodic_children else 3): _finish(); return
	original_damage_recording = DamageObserver.recording_enabled
	check(not original_damage_recording,"new native process owns the existing bounded read-only damage observer")
	DamageObserver.reset(); DamageObserver.recording_enabled = true
	PlayerState.profile_changed.connect(_observe_profile_caps)
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5,13.5)))
	# Exactly the same declared initial stress stats as the single-cohort case.
	# These are assigned once. Later rounds inherit remaining HP/MP and cooldown.
	PlayerState.computed_stats.magic_min = 180; PlayerState.computed_stats.magic_max = 180
	game.player.max_hp = 100000; game.player.current_hp = 100000
	game.player.max_mp = 5000; game.player.current_mp = 5000
	game.player.resources_changed.connect(_observe_mana_resources)
	supply_last_signal_mp = game.player.current_mp
	supply_last_signal_pending = game.player._pending_potion_mana
	supply_last_signal_max_mp = game.player.max_mp
	for index in 2:
		await _combat_round(index)
		if completed_rounds.size() != index+1 or not failures.is_empty(): break
	check(completed_rounds.size() == 2,"two equal full-kill cohorts finish in the same native world")
	if runtime == null: _finish(); return
	if completed_rounds.size() == 2:
		check(completed_rounds[0].world == completed_rounds[1].world and completed_rounds[0].runtime_id == completed_rounds[1].runtime_id,
			"both rounds retain the exact same world identity and effect runtime")
		check(int(completed_rounds[1].simulation_start_usec) >= int(completed_rounds[0].simulation_end_usec),"the original simulation clock continues monotonically between rounds")
		check(int(completed_rounds[1].hp_before) == int(completed_rounds[0].hp_after) and int(completed_rounds[1].mp_before) == int(completed_rounds[0].mp_after),
			"round two inherits actual remaining HP and MP without a test refund")
	var expected_xp := xp_before
	var fixture_deaths := 0
	for death: Dictionary in observed_deaths.values():
		expected_xp += int(death.experience)
		if str(death.spawn_slot_id).begins_with("test:natural:sustained:"): fixture_deaths += 1
	check(fixture_deaths == 60 and deaths == 60,"independent death signals contain sixty distinct named fixture deaths")
	check(game._enemy_death_terminal_total_count == observed_deaths.size() and PlayerState.experience == expected_xp,
		"all fixture and incidental world deaths commit exactly their canonical rewards once")
	check(scopes_closed and samples.size() >= 240 and samples.size()<12000,"continuous raw observation stays bounded and shared budget scopes close")
	check(not action_observation_overflowed,"explicit test input observations remain within their finite bound")
	check(not profile_cap_observation_overflowed and not DamageObserver.overflowed,"profile and actual HP-write observations remain complete within existing bounded containers")
	check(not supply_input_overflowed and not supply_restore_overflowed and not mp_cap_observation_overflowed,
		"formal supply inputs and ordinary Player restore events remain within their finite bounds")
	var supply_frames: Dictionary = {}
	var unique_supply_frames := true
	for row: Dictionary in supply_inputs:
		unique_supply_frames = unique_supply_frames and not supply_frames.has(int(row.process_frame))
		supply_frames[int(row.process_frame)] = true
	check(unique_supply_frames and supply_inputs.size() == supply_successes,
		"each successful formal supply action occurs on a distinct process frame")
	check(supply_successes > 0 and supply_restored_mana > 0 and not supply_restore_events.is_empty(),
		"successful potion uses produce actual delayed MP ticks through ordinary Player processing")
	var valid_restore_ticks := true
	for row: Dictionary in supply_restore_events:
		valid_restore_ticks = valid_restore_ticks and (
			int(row.actual_restored) > 0
			and int(row.actual_restored) <= int(supply_recovery_profile.tick_amount)
			and int(row.pending_before) - int(row.pending_after) >= int(row.actual_restored)
		)
	check(valid_restore_ticks,"observed delayed MP restoration respects the formal per-tick amount")
	check(PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
		== supply_initial_count + MANA_SUPPLY_SEED_COUNT - supply_successes
		and PlayerState.quick_item_slots[0] == MANA_SUPPLY_ID,
		"every successful structured use consumes exactly one of the baseline twenty and keeps its binding")
	check(death_collision_observations.size() == 60,"every exact fixture death was observed after immediate collision retirement")
	var child_rows: Array = game.child_rows if periodic_children else []
	if periodic_children:
		var valid: bool = not game.child_observation_overflowed and not child_rows.is_empty()
		var periodic := 0
		for row: Dictionary in child_rows:
			valid = valid and bool(row.result.success) and int(row.generation) == 1
			periodic += 1 if row.parent_source_class == "periodic" else 0
		check(valid and periodic > 0 and int(runtime.metrics().child_actions) == child_rows.size(),"every observed real child completes once; natural periodic fatal input is included")
	check(runtime != null and not runtime.has_work() and runtime.errors.is_empty(),"continuous accepted work finishes before final save and retirement")
	var final_save_started := Time.get_ticks_usec()
	check(PlayerState.save_game(true,true,true),"continuous final rewards save through the sole production writer")
	var final_supply_count := PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
	boundary_spans.append({"round":2,"kind":"final_production_durable_checkpoint","started_usec":final_save_started,"finished_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames()})
	# Let the original Root and this observer finish the frame containing the
	# final checkpoint. No clock/pump is invoked or budget reset by the fixture.
	await get_tree().process_frame
	observing = false
	_write(report_path,{"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope":"PC headless two full 30-receiver natural combat rounds in one Root/profile/runtime; original attack, movement, HP and cohort timing retained; twenty real registered MP consumables added once to the baseline and used only through the formal quick slot; this new lawful supply is not an optimization comparison with the prior no-supply fixture; initial stress HP/MP are temporary and actual profile synchronization applies authoritative caps; cap changes are not counted as incoming damage; authored corpses, ground drops, shared caches and bounded test observations may retain memory; not Android/GPU or infinite duration",
		"phase":"after final production save; before teardown and cold handoff","phase_status":"PASS" if failures.is_empty() else "FAIL","phase_failures":failures,
		"rounds":completed_rounds,"samples":samples,"wall_frame_usec":_percentiles("wall_usec"),"engine_process_usec":_percentiles("engine_process_usec"),
		"engine_physics_usec":_percentiles("engine_physics_usec"),"observed_deaths":observed_deaths.values(),"terminal_death_jobs":game._enemy_death_terminal_jobs,
		"metrics":runtime.metrics() if runtime != null else {},"child_rows":child_rows,"expected_xp":expected_xp,"xp_after":PlayerState.experience,
		"boundary_spans":boundary_spans,"action_observations":action_observations,"profile_cap_observations":profile_cap_observations,"death_collision_observations":death_collision_observations,
		"mana_supply":{"entity_id":MANA_SUPPLY_ID,"catalog":{"serviceIndex":supply_catalog.get("serviceIndex"),
			"kind":supply_catalog.get("kind"),"useEffect":supply_catalog.get("useEffect"),
			"restoreHealth":supply_catalog.get("restoreHealth"),"restoreMana":supply_catalog.get("restoreMana")},
			"recovery_profile":supply_recovery_profile,"initial_count":supply_initial_count,
			"seed_count":MANA_SUPPLY_SEED_COUNT,"seed_receipts":supply_seed_receipts,
			"successful_uses":supply_successes,"remaining_count":final_supply_count,
			"inputs":supply_inputs,"input_overflowed":supply_input_overflowed,
			"actual_restored_mana":supply_restored_mana,"restore_events":supply_restore_events,
			"profile_cap_removed_mana":observed_mp_cap_removal,"profile_cap_events":mp_cap_events,
			"observed_non_cap_mp_decrease":observed_non_cap_mp_decrease,
			"restore_overflowed":supply_restore_overflowed},
		"damage_observation_counts":{"events":DamageObserver.events.size(),"admissions":DamageObserver.admissions.size(),"deliveries":DamageObserver.deliveries.size(),"terminal_events":DamageObserver.terminal_events.size(),"overflowed":DamageObserver.overflowed},
		"engine_monitor_scope":"engine monitor snapshots may repeat between engine updates; wall interval samples are the independent raw frame series; damage observer is enabled for this fixture",
		"audio_cue_starts":audio_cue_starts,"exact_prepared_streams":exact_prepared_streams,"memory_checkpoints":memory_checkpoints,
		"maximum_pending_age_frames":maximum_pending_age,"maximum_service_age_frames":maximum_service_age})
	var generation: String = PlayerState._world_clock_generation
	var owners := {"root":weakref(game),"runtime":weakref(runtime),"world":weakref(game._world_context),"clock":weakref(game._time_domains),"streaming":weakref(game._streaming_coordinator)}
	game.queue_free(); await get_tree().process_frame
	check(not runtime.has_work() and runtime._receipts.is_empty(),"formal Root exit retires the final transient effect owners")
	check(ContentLayers.reload_feature_catalog(),"retired world withdraws the existing prepared source")
	for frame in 180:
		if resource_owner.get_ref() == null and ContentLayers._feature_resource_service.pending_count() == 0: break
		await get_tree().process_frame
	check(resource_owner.get_ref() == null and ContentLayers._feature_resource_service.pending_count() == 0,"accepted source leases and resource retirement drain")
	check(PlayerState.select_character(profile) and PlayerState.experience == expected_xp,"actual profile reload retains exact continuous rewards")
	check(PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID) == final_supply_count
		and PlayerState.quick_item_slots[0] == MANA_SUPPLY_ID,
		"actual profile reload retains exact potion remainder and formal quick-slot binding")
	if failures.is_empty(): _write(expected_path,{"profile_id":profile,"experience":expected_xp,"generation":generation,"completed_rounds":2,"fixture_deaths":60,
		"mana_supply_id":MANA_SUPPLY_ID,"mana_supply_initial_count":supply_initial_count,
		"mana_supply_seed_count":MANA_SUPPLY_SEED_COUNT,"mana_supply_successful_uses":supply_successes,
		"mana_supply_remaining_count":final_supply_count,"mana_supply_quick_slot":PlayerState.quick_item_slots[0],
		"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")})
	var cleanup := {"sample_count":samples.size(),"before_clear":_memory_snapshot()}
	DamageObserver.recording_enabled = original_damage_recording; DamageObserver.reset()
	samples.clear(); targets.clear(); previous_actors.clear(); cast_targets.clear(); spawned_owners.clear(); runtime = null
	for frame in 4: await get_tree().process_frame
	var released := true
	for owner: WeakRef in owners.values(): released = released and owner.get_ref() == null
	check(released and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,"retired Root/runtime/world/clock/streaming release and no orphan nodes remain")
	cleanup["all_world_owners_released"] = released; cleanup["after_observation_clear"] = _memory_snapshot()
	var final_trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	final_trace["cleanup"] = cleanup; final_trace["final_checks_before_trace_write"] = checks
	final_trace["final_status_before_trace_write"] = "PASS" if failures.is_empty() else "FAIL"
	_write(report_path,final_trace)
	_finish()

func _combat_round(index: int) -> void:
	var label := "round %d: " % index
	game.observer_tail_owner = null
	game.observer_aim_row = {}
	targets.clear(); previous_actors.clear()
	round_death_base = deaths; round_peak_states = 0; round_peak_evidence = {}
	stream_started_usec = 0; stream_finished_usec = 0; resource_evidence = {}; resource_mapping = {}; concurrent_queues = false
	var before: Dictionary = runtime.metrics() if runtime != null else {}
	var tick_before := int(before.get("ticks",0))
	var damage_event_start := DamageObserver.events.size()
	var damage_admission_start := DamageObserver.admissions.size()
	var damage_delivery_start := DamageObserver.deliveries.size()
	var damage_terminal_start := DamageObserver.terminal_events.size()
	var accepted_before := accepted_casts
	var player_motion_before := movement_gu; var actor_motion_before := monster_movement_gu
	var mp: int = game.player.current_mp; var hp: int = game.player.current_hp
	var pending_mana_before: int = game.player._pending_potion_mana
	var restored_before := supply_restored_mana
	var cap_removal_before := observed_mp_cap_removal
	var non_cap_decrease_before := observed_non_cap_mp_decrease
	var supply_uses_before := supply_successes
	var supply_count_before := PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
	var simulation_start: int = game._time_domains.simulation_usec()
	var sample_start := samples.size()
	var initial_stats := {"computed":PlayerState.computed_stats.duplicate(true),"player_max_hp":game.player.max_hp,"player_max_mp":game.player.max_mp}
	var cohort_damage_identities: Dictionary = {}
	if index == 0: previous_frame_usec = Time.get_ticks_usec()
	var birth_started := Time.get_ticks_usec()
	for slot in 30:
		var point := Vector2(40.5+float(slot%6)*0.72+(0.36 if int(slot/6)%2 else 0.0),12.2+float(slot/6)*0.64)
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(point),false,-1.0,
			{"respawn_enabled":false,"spawn_slot_id":"test:natural:sustained:%d:%d" % [index,slot]})
		if actor != null:
			actor.max_hp = 1500+(slot*7 if periodic_children else 0); actor.current_hp = actor.max_hp
			actor.died.connect(_on_target_died); targets.append(actor); spawned_owners.append(weakref(actor))
			if slot == 29: game.observer_tail_owner = weakref(actor)
			cohort_damage_identities[actor.get_instance_id()] = {"runtime_id":actor.get_instance_id(),
				"life":int(actor.get_meta("hc_combat_life_epoch",0)),"generation":int(actor.get_meta("zone_generation",-1)),
				"slot":str(actor.get_meta("spawn_context",{}).get("spawn_slot_id","")),"initial_hp":actor.current_hp,
				"initial_regen_state":actor._natural_regen.state_snapshot(),
				"natural_regen_hp_per_tick":MonsterNaturalRegenPolicy.heal_amount(actor.max_hp)}
			check(actor._hc_point_walkable(point) and actor.is_physics_processing(),label+"real walkable receiver with AI active: "+str(slot))
	var nonoverlap := targets.size() == 30
	for i in targets.size():
		for j in range(i):
			var a: Vector2 = game._canonical_screen_px_to_ground_gu(targets[i].global_position)
			var b: Vector2 = game._canonical_screen_px_to_ground_gu(targets[j].global_position)
			nonoverlap = nonoverlap and a.distance_to(b) >= targets[i].combat_radius_gu+targets[j].combat_radius_gu
	check(nonoverlap,label+"thirty disjoint real footprints preserve the original cohort inputs")
	boundary_spans.append({"round":index,"kind":"actual_cohort_factory_and_fixture_checks","started_usec":birth_started,"finished_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames()})
	if not nonoverlap: return
	var start := Time.get_ticks_msec(); var next_input := start; var next_memory := start
	var cohort_deadline_started_usec := start * 1000
	var cohort_finished_usec := 0
	previous_player = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	observing = runtime != null
	while Time.get_ticks_msec()-start<35000:
		var now := Time.get_ticks_msec()
		game._on_gameplay_movement(Vector2(0.5,-0.25).normalized() if int((now-start)/1200)%2 == 0 else Vector2(-0.5,0.25).normalized())
		_maybe_use_mana_supply(index, now-start)
		if now >= next_input and deaths-round_death_base < 30:
			next_input = now+250
			var chosen := _current_aim_target()
			if chosen != null:
				game._set_magic_locked_target(chosen,true)
				var causal_snapshot: Dictionary = {}
				if action_observations.size()<512:
					causal_snapshot = _causal_enemy_snapshot(chosen)
				var input_started := Time.get_ticks_usec()
				var input_simulation: int = game._time_domains.simulation_usec()
				var input_physics := Engine.get_physics_frames()
				var input_process := Engine.get_process_frames()
				var result: StringName = game._try_release_skill("hc.skill.wizard.ice_storm",false)
				if action_observations.size()<512:
					var action_row: Dictionary = {"round":index,"wall_usec":Time.get_ticks_usec(),"simulation_usec":game._time_domains.simulation_usec(),"result":str(result),
						"input_started_usec":input_started,"input_simulation_usec":input_simulation,
						"input_physics_frame":input_physics,"input_process_frame":input_process,
						"expected_release_id":"player:%d:action:%d" % [game.player.get_instance_id(),game.player._pending_combat_action_id] if result==&"accepted" else "",
						"hp":game.player.current_hp,"mp":game.player.current_mp,"magic_min":PlayerState.computed_stats.get("magic_min",0),"magic_max":PlayerState.computed_stats.get("magic_max",0)}
					action_row["entry_gate_observation"] = game.last_entry_gate_observation.duplicate(true)
					action_row["actual_aim_selection_inputs"] = game.observer_aim_row.duplicate(true)
					action_row.merge(causal_snapshot,true)
					action_observations.append(action_row)
				else: action_observation_overflowed = true
				if result == &"accepted": accepted_casts += 1
				else: rejected_inputs[str(result)] = int(rejected_inputs.get(str(result),0))+1
		if runtime == null and game._feature_effect_runtime != null: runtime = game._feature_effect_runtime; observing = true
		if now >= next_memory:
			next_memory = now+5000; memory_checkpoints.append({"round":index,"elapsed_ms":now-start,"snapshot":_memory_snapshot()})
			print("NATURAL_SUSTAINED_PROGRESS ",JSON.stringify({"round":index,"elapsed_ms":now-start,"deaths":deaths-round_death_base,"accepted":accepted_casts-accepted_before,
				"hp":game.player.current_hp,"mp":game.player.current_mp,"input_enabled":game.gameplay_input_is_enabled(),"rejected":rejected_inputs,"metrics":runtime.metrics() if runtime != null else {}}))
		await get_tree().process_frame
		if _cohort_business_drained():
			cohort_finished_usec = Time.get_ticks_usec()
			break
	game._on_gameplay_movement(Vector2.ZERO)
	var damage_evidence_started := Time.get_ticks_usec()
	var cohort_damage_evidence := _cohort_damage_evidence(damage_event_start,cohort_damage_identities)
	var release_evidence := _cohort_release_evidence(index,cohort_damage_identities)
	boundary_spans.append({"round":index,"kind":"post_cohort_read_only_hp_evidence","started_usec":damage_evidence_started,
		"finished_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames()})
	check(not DamageObserver.overflowed and cohort_damage_evidence.targets.size()==30
		and bool(cohort_damage_evidence.all_hp_writes_reconcile),
		label+"all thirty original life/generation identities reconcile actual damage and terminal HP with explicit bounded unobserved gains")
	check(not game.release_observation_overflowed and not action_observation_overflowed
		and bool(release_evidence.all_observed_releases_match) and int(release_evidence.observed_signal_count)>0,
		label+"actual Timer signals uniquely match accepted action IDs and invoke the sole canonical planner at most once")
	check(runtime != null,label+"actual input creates its admitted runtime")
	if runtime == null: return
	var metrics: Dictionary = runtime.metrics()
	check(accepted_casts-accepted_before > 1 and movement_gu-player_motion_before>1.0 and monster_movement_gu-actor_motion_before>1.0,
		label+"repeated accepted casts, Player movement and live pursuit remain active")
	check(game.player.current_hp<hp and game.player.current_mp<mp,label+"live attacks and real casts spend HP and MP")
	var restored_this_round := supply_restored_mana - restored_before
	var cap_removed_this_round := observed_mp_cap_removal - cap_removal_before
	var actual_mana_spent := observed_non_cap_mp_decrease - non_cap_decrease_before
	check(actual_mana_spent == mp + restored_this_round - game.player.current_mp - cap_removed_this_round,
		label+"real resource signals reconcile MP spend separately from profile-cap clipping")
	check(actual_mana_spent > 0 and PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
		== supply_count_before - (supply_successes - supply_uses_before),
		label+"actual MP spend includes only observed formal restoration and exact inventory consumption")
	var damage_evidence := _player_damage_evidence(damage_event_start, damage_admission_start, damage_delivery_start, damage_terminal_start)
	check(not DamageObserver.overflowed and int(damage_evidence.actual_hp_loss)>0 and not damage_evidence.rows.is_empty(),
		label+"real incoming Player HP mutations independently prove attacks, excluding profile-cap changes")
	check(round_peak_states == 90 and bool(round_peak_evidence.get("identities_match",false))
		and bool(round_peak_evidence.get("all_named_thirty_fixture_targets_have_three_sources",false)),label+"all thirty exact ActorRefs simultaneously own three distinct states")
	check(int(metrics.ticks)-tick_before>=360 and int(metrics.tick_delivery_count)==int(metrics.ticks),label+"at least360 actual ticks complete without rejected damage delivery")
	check(int(metrics.maximum_tick_delivery_lateness_usec)<1000000,label+"every actual delivery so far is strictly below the original one-second period")
	check(deaths-round_death_base == 30 and not runtime.has_work() and runtime.errors.is_empty()
		and cohort_finished_usec >= cohort_deadline_started_usec and cohort_finished_usec > 0
		and cohort_finished_usec-cohort_deadline_started_usec < 35000000,
		label+"all thirty deaths and accepted effects finish before the original bounded cohort deadline")
	var reservations: Dictionary = runtime.reservation_snapshot()
	var empty := true
	for count: int in reservations.values(): empty = empty and count == 0
	check(empty and runtime._receipts.is_empty() and runtime.heap_count()==0 and runtime.child_count()==0 and runtime.pending_count()==0 and _settlement_drained(),
		label+"all transient reservations, states, receipts, facts, children and both writer queues drain naturally")
	check(concurrent_queues and bool(resource_evidence.get("five_textures_available",false)) and str(resource_evidence.get("request_kind",""))=="threaded_new_job"
		and int(resource_evidence.get("get_delta",0))>=5 and int(resource_evidence.get("request_delta",0))>=5,label+"actual first-death demand completes its own new five-texture job while settlement overlaps")
	check(runtime.presentation().node_count()==0 and game._streaming_coordinator.pending_request_count()==0,label+"actual cues and global resource backlog reach terminal drain")
	game._streaming_coordinator.unregister_visual(get_instance_id())
	var save_started := Time.get_ticks_usec()
	check(PlayerState.save_game(true,true,true),label+"real production writer durably saves the completed cohort")
	boundary_spans.append({"round":index,"kind":"production_durable_checkpoint","started_usec":save_started,"finished_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames()})
	var remaining_receivers: Array[Dictionary] = []
	for actor: EnemyActor in targets:
		if not is_instance_valid(actor) or actor.current_hp <= 0: continue
		var remaining: Dictionary = _causal_enemy_snapshot(actor)
		remaining["slot"] = str(actor.get_meta("spawn_context",{}).get("spawn_slot_id",""))
		var states: Array[Dictionary] = []
		for state: Dictionary in runtime._states.values():
			if state.target.resolve(false) == actor:
				states.append({"source_handle":str(state.command.source_handle),"next_due_usec":int(state.next_due),
					"expires_usec":int(state.expires),"period_usec":int(state.period),"ticks":int(state.ticks)})
		remaining["accepted_states"] = states
		remaining_receivers.append(remaining)
	completed_rounds.append({"round":index,"elapsed_ms":Time.get_ticks_msec()-start,"world":game._world_context.capture_world(),"runtime_id":runtime.get_instance_id(),
		"cohort_deadline_started_usec":cohort_deadline_started_usec,"business_finished_usec":cohort_finished_usec,
		"business_completion_elapsed_usec":cohort_finished_usec-cohort_deadline_started_usec if cohort_finished_usec>0 else -1,
		"business_deadline_usec":35000000,"completion_scope":"death/effect/reservation/receipt/child/cue/writer/resource drains; excludes later evidence IO, explicit checkpoint and continuing potion restoration",
		"remaining_receivers_at_original_deadline":remaining_receivers,
		"simulation_start_usec":simulation_start,"simulation_end_usec":game._time_domains.simulation_usec(),"hp_before":hp,"hp_after":game.player.current_hp,"mp_before":mp,"mp_after":game.player.current_mp,
		"pending_mana_before":pending_mana_before,"pending_mana_after":game.player._pending_potion_mana,
		"actual_formal_mana_restored":restored_this_round,"actual_mana_spent":actual_mana_spent,
		"profile_cap_removed_mana":cap_removed_this_round,
		"supply_count_before":supply_count_before,"supply_count_after":PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID),
		"supply_successful_uses":supply_successes-supply_uses_before,
		"accepted_casts":accepted_casts-accepted_before,"ticks":int(metrics.ticks)-tick_before,"deaths":deaths-round_death_base,"peak_states":round_peak_states,"peak_state_evidence":round_peak_evidence,
		"sample_start":sample_start,"sample_end":samples.size(),"resource_evidence":resource_evidence.duplicate(true),"reservations":reservations,
		"memory":_memory_snapshot(),"metrics":metrics,"player_damage_evidence":damage_evidence,"cohort_damage_evidence":cohort_damage_evidence,"release_evidence":release_evidence,"initial_player_stats":initial_stats,"final_player_stats":{"computed":PlayerState.computed_stats.duplicate(true),"player_max_hp":game.player.max_hp,"player_max_mp":game.player.max_mp},
		"maximum_pending_age_frames":maximum_pending_age.duplicate(),"maximum_service_age_frames":maximum_service_age.duplicate()})
	var evidence_started := Time.get_ticks_usec()
	_write(report_path.replace("_trace.json","_progress.json"),{"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"phase":"completed cohorts only; final result remains pending","rounds":completed_rounds,"phase_failures":failures})
	boundary_spans.append({"round":index,"kind":"test_owned_progress_evidence_io","started_usec":evidence_started,"finished_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames()})

func _cohort_business_drained() -> bool:
	if runtime == null or deaths-round_death_base != 30 or runtime.has_work() or not _settlement_drained() or stream_finished_usec <= 0:
		return false
	if not runtime._receipts.is_empty() or runtime.heap_count() != 0 or runtime.child_count() != 0 or runtime.pending_count() != 0:
		return false
	if runtime.presentation().node_count() != 0 or game._streaming_coordinator.pending_request_count() != 0:
		return false
	for count: int in runtime.reservation_snapshot().values():
		if count != 0: return false
	return true

func _maybe_use_mana_supply(round_index: int, elapsed_ms: int) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player): return
	var frame := Engine.get_process_frames()
	var mp_before: int = game.player.current_mp
	var pending_before: int = game.player._pending_potion_mana
	# A declared first formal dose at the second-cohort boundary proves the
	# supply path even if cooldown-limited casts never reach the low-MP trigger.
	# It requires the real full-dose deficit, consumes the ordinary inventory,
	# and queues the existing delayed ticks. Subsequent doses keep the 250 gate.
	var first_boundary_dose: bool = (round_index == 1 and supply_successes == 0
		and game.player.max_mp - mp_before >= int(supply_catalog.restoreMana))
	if ((mp_before >= MANA_SUPPLY_TRIGGER_MP and not first_boundary_dose)
		or pending_before != 0 or frame == supply_last_use_frame): return
	supply_last_use_frame = frame
	var count_before := PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
	if count_before <= 0:
		if not supply_out_of_stock_reported:
			supply_out_of_stock_reported = true
			check(false,"the fixed baseline twenty-potion supply remains sufficient for the complete two-round workload")
		return
	var started_usec := Time.get_ticks_usec()
	var result: Dictionary = PlayerState.use_quick_item_slot(0, MANA_SUPPLY_ID)
	var count_after := PlayerState.item_count_by_entity_id(MANA_SUPPLY_ID)
	var pending_after: int = game.player._pending_potion_mana
	var mp_after: int = game.player.current_mp
	var success := bool(result.get("ok", false))
	if success: supply_successes += 1
	check(success and count_after == count_before - 1
		and pending_after == int(supply_catalog.restoreMana) and mp_after == mp_before,
		"formal quick-slot use consumes exactly one potion and queues only delayed MP")
	var row := {"round":round_index,"elapsed_ms":elapsed_ms,"process_frame":frame,
		"trigger":"first_second_cohort_full_deficit" if first_boundary_dose else "low_mp",
		"started_usec":started_usec,"finished_usec":Time.get_ticks_usec(),
		"action":"PlayerState.use_quick_item_slot","entity_id":MANA_SUPPLY_ID,
		"configuration":{"threshold_mp":MANA_SUPPLY_TRIGGER_MP,"slot":0,
			"use_effect":supply_catalog.get("useEffect"),"restore_mana":supply_catalog.get("restoreMana"),
			"restore_health":supply_catalog.get("restoreHealth")},
		"mp_before":mp_before,"mp_after":mp_after,
		"pending_mana_before":pending_before,"pending_mana_after":pending_after,
		"count_before":count_before,"count_after":count_after,
		"ok":success,"reason":str(result.get("reason",""))}
	if supply_inputs.size() < MAX_SUPPLY_INPUTS: supply_inputs.append(row)
	else: supply_input_overflowed = true
	# Queuing has no MP signal. Establish the new pending baseline so the next
	# Player.resources_changed callback measures an actual delayed tick.
	supply_last_signal_mp = mp_after
	supply_last_signal_pending = pending_after

func _observe_mana_resources(_hp: int, _max_hp: int, current_mp: int, _max_mp: int) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player): return
	var decrease := maxi(0,supply_last_signal_mp-current_mp)
	var cap_removed := 0
	if _max_mp < supply_last_signal_max_mp:
		# Player._apply_stats clamps absolute MP to the new cap before this
		# signal. Count that clipping separately from actual combat spending.
		cap_removed = mini(decrease,maxi(0,supply_last_signal_mp-_max_mp))
		if cap_removed > 0:
			observed_mp_cap_removal += cap_removed
			if mp_cap_events.size() < MAX_RESTORE_EVENTS:
				mp_cap_events.append({"round":completed_rounds.size(),"process_frame":Engine.get_process_frames(),
					"mp_before":supply_last_signal_mp,"mp_after":current_mp,
					"max_mp_before":supply_last_signal_max_mp,"max_mp_after":_max_mp,"cap_removed":cap_removed})
			else: mp_cap_observation_overflowed = true
	observed_non_cap_mp_decrease += decrease-cap_removed
	var pending_now: int = game.player._pending_potion_mana
	var restored := maxi(0, current_mp - supply_last_signal_mp)
	if pending_now < supply_last_signal_pending and restored > 0:
		supply_restored_mana += restored
		var row := {"round":completed_rounds.size(),"process_frame":Engine.get_process_frames(),
			"wall_usec":Time.get_ticks_usec(),"mp_before":supply_last_signal_mp,
			"mp_after":current_mp,"pending_before":supply_last_signal_pending,
			"pending_after":pending_now,"actual_restored":restored}
		if supply_restore_events.size() < MAX_RESTORE_EVENTS: supply_restore_events.append(row)
		else: supply_restore_overflowed = true
	supply_last_signal_mp = current_mp
	supply_last_signal_pending = pending_now
	supply_last_signal_max_mp = _max_mp

func _current_aim_target() -> EnemyActor:
	var active_targets := {}
	if runtime != null:
		for state: Dictionary in runtime._states.values():
			var receiver: Node = state.target.resolve()
			if is_instance_valid(receiver): active_targets[receiver.get_instance_id()] = true
	var chosen: EnemyActor = null; var best_score := -1
	var observer_started := Time.get_ticks_usec()
	var tail := game.observer_tail_owner.get_ref() as EnemyActor if game.observer_tail_owner != null else null
	var tail_score := -1; var tail_center := Vector2.ZERO
	var score_rows: Array[Dictionary] = []
	var observer_extra_usec := Time.get_ticks_usec()-observer_started
	for actor: EnemyActor in targets:
		if not is_instance_valid(actor) or actor.current_hp<=0: continue
		var center: Vector2 = game._canonical_screen_px_to_ground_gu(actor.global_position); var score := 0
		for receiver: EnemyActor in targets:
			if not is_instance_valid(receiver) or receiver.current_hp<=0: continue
			var offset: Vector2 = game._canonical_screen_px_to_ground_gu(receiver.global_position)-center
			if absf(offset.x)<=1.5 and absf(offset.y)<=1.5: score += 100 if not active_targets.has(receiver.get_instance_id()) else 1
		observer_started = Time.get_ticks_usec()
		if score_rows.size()<30:
			score_rows.append({"runtime_id":actor.get_instance_id(), "slot":str(actor.get_meta("spawn_context",{}).get("spawn_slot_id","")),
				"center_ground_gu":[center.x,center.y], "hp":actor.current_hp,
				"has_active_effect":active_targets.has(actor.get_instance_id()), "actual_score":score})
		if actor == tail: tail_score = score; tail_center = center
		observer_extra_usec += Time.get_ticks_usec()-observer_started
		if score>best_score: chosen = actor; best_score = score
	observer_started = Time.get_ticks_usec()
	game.observer_aim_row = {"schema":"sustained.aim_inputs.v1", "score_rows_in_original_order":score_rows,
		"chosen_runtime_id":chosen.get_instance_id() if is_instance_valid(chosen) else 0, "chosen_actual_score":best_score,
		"tail_actual_score":tail_score, "tail_center_ground_gu":[tail_center.x,tail_center.y] if tail_score>=0 else [],
		"tail_has_active_effect":active_targets.has(tail.get_instance_id()) if is_instance_valid(tail) else false,
		"selected_tail":chosen == tail and is_instance_valid(tail), "tie_rule":"strict_greater_preserves_original_order",
		"extent_per_axis_gu":1.5, "unactive_weight":100, "active_weight":1}
	observer_extra_usec += Time.get_ticks_usec()-observer_started
	game.observer_aim_row["measured_observer_block_usec"] = observer_extra_usec
	return chosen

func _causal_enemy_snapshot(enemy: EnemyActor) -> Dictionary:
	var player_ground_gu: Vector2 = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	var enemy_ground_gu: Vector2 = game._canonical_screen_px_to_ground_gu(enemy.global_position)
	return {"causal_snapshot_wall_usec":Time.get_ticks_usec(),"enemy_instance_id":enemy.get_instance_id(),
		"enemy_hp":enemy.current_hp,"enemy_max_hp":enemy.max_hp,
		"player_canonical_ground_gu":[player_ground_gu.x,player_ground_gu.y],
		"enemy_canonical_ground_gu":[enemy_ground_gu.x,enemy_ground_gu.y],
		"enemy_target_is_player":is_same(enemy.target,game.player),
		"enemy_audio_attack_sequence":int(enemy._audio_attack_sequence),
		"enemy_last_physical_hit_resolution":enemy.last_physical_hit_resolution.duplicate(true)}

func _on_target_died(enemy: EnemyActor, data: Dictionary) -> void:
	check(enemy.collision_layer == 0 and enemy.collision_mask == 0 and not enemy.is_physics_processing() and not enemy.is_in_group("enemies"),
		"actual death immediately removes collision and active physics before its notification")
	var death_row: Dictionary = {"instance_id":enemy.get_instance_id(),"slot":str(enemy.get_meta("spawn_context",{}).get("spawn_slot_id","")),
		"collision_layer":enemy.collision_layer,"collision_mask":enemy.collision_mask,"physics_processing":enemy.is_physics_processing(),"process_frame":Engine.get_process_frames(),"simulation_usec":game._time_domains.simulation_usec(),
		"death_data_monster_id":int(data.get("monster_id",-1)),"death_data_keys":data.keys(),
		"natural_regen_state_at_death":enemy._natural_regen.state_snapshot()}
	# This signal carries canonical monster data, not a fatal damage identity.
	# Child rows and the explicit damage observer carry their own real sources.
	death_row.merge(_causal_enemy_snapshot(enemy),true)
	death_collision_observations.append(death_row)
	deaths += 1
	if deaths != round_death_base+1: return
	death_started_usec = Time.get_ticks_usec()
	var coordinator: RefCounted = game._streaming_coordinator
	var visual := MonsterVisual.new()
	for id: int in [64,89,34,19]:
		var mapping: Dictionary = visual._client_mapping_for(GameData.get_monster_by_id(id))
		var key: String = visual._client_resource_cache_key(mapping)
		if not mapping.is_empty() and coordinator.client_resources(key).is_empty() and not coordinator._threaded_profile_requests.has(key):
			resource_mapping = mapping; resource_key = key; resource_monster_id = id; break
	visual.free()
	check(not resource_mapping.is_empty(),"round first-death key is genuinely uncached at actual demand")
	if resource_mapping.is_empty(): return
	coordinator.register_visual(self,get_instance_id(),game.current_map_id,game._zone_generation,resource_key,{},0)
	stream_started_usec = death_started_usec
	resource_get_before = coordinator.threaded_texture_get_count(); resource_request_before = coordinator.threaded_texture_request_count()
	var immediate: Dictionary = coordinator.request_visual_resources(self,resource_mapping,resource_monster_id)
	var job: Dictionary = coordinator._threaded_profile_requests.get(resource_key,{})
	resource_evidence = {"key":resource_key,"monster_id":resource_monster_id,"demand_death_identity":enemy.get_instance_id(),
		"cache_empty_at_demand":true,"request_kind":"cache_hit" if not immediate.is_empty() else "threaded_new_job",
		"job_state_after_request":str(job.get("state","")),"request_sequence":int(job.get("request_sequence",-1)),
		"job_map_generation":int(job.get("map_generation",-1)),"paths":job.get("paths",{}).duplicate(),
		"failure_seen":coordinator._failure_details.has(resource_key),"five_textures_available":false}
	check(immediate.is_empty() and str(job.get("state","")) in ["queued","loading"] and job.get("paths",{}).size()==5,
		"round demand owns a new five-action job, rather than an unrelated queue or cache hit")
	concurrent_queues = coordinator._threaded_profile_requests.has(resource_key) and (not game._pending_enemy_deaths.is_empty()
		or not game._prepared_enemy_death_settlement.is_empty() or PlayerState._json_persistence.pending_count()>0)

func _observe_profile_caps() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player): return
	if profile_cap_observations.size() >= 512: profile_cap_observation_overflowed = true; return
	profile_cap_observations.append({"round":completed_rounds.size(),"wall_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"hp":game.player.current_hp,"mp":game.player.current_mp,"player_max_hp":game.player.max_hp,"player_max_mp":game.player.max_mp,
		"authoritative_max_hp":int(PlayerState.computed_stats.get("max_hp",0)),"authoritative_max_mp":int(PlayerState.computed_stats.get("max_mp",0))})

func _cohort_release_evidence(round_index: int, identities: Dictionary) -> Dictionary:
	var accepted: Dictionary = {}
	for action: Dictionary in action_observations:
		if int(action.round)==round_index and str(action.result)=="accepted":
			accepted[str(action.expected_release_id)] = action
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var all_match := true
	for signal_row: Dictionary in game.skill_release_rows:
		var release_id := str(signal_row.release_id)
		if not accepted.has(release_id): continue
		var action: Dictionary = accepted[release_id]
		var row: Dictionary = signal_row.duplicate(true)
		row["input"] = action
		row["wall_input_to_signal_usec"] = int(row.wall_started_usec)-int(action.input_started_usec)
		row["simulation_input_to_signal_usec"] = int(row.simulation_usec)-int(action.input_simulation_usec)
		row["canonical"] = []
		var canonical_match := true
		for cursor in range(int(row.canonical_row_start),int(row.canonical_row_end)):
			var canonical: Dictionary = game.canonical_release_rows[cursor].duplicate(true)
			canonical["synchronous_cohort_hp_writes"] = []
			for event_index in range(int(canonical.damage_event_start),int(canonical.damage_event_end)):
				var event: Dictionary = DamageObserver.events[event_index]
				if identities.has(int(event.victim_instance_id)): canonical.synchronous_cohort_hp_writes.append(event)
			canonical_match = canonical_match and str(canonical.release_id)==release_id \
				and (str(canonical.plan_release_id).is_empty() or str(canonical.plan_release_id)==release_id)
			row.canonical.append(canonical)
		row["unique_and_ordered"] = not seen.has(release_id) and row.canonical.size()<=1 and canonical_match \
			and int(row.wall_input_to_signal_usec)>=0 and int(row.simulation_input_to_signal_usec)>=0
		all_match = all_match and bool(row.unique_and_ordered)
		seen[release_id] = true
		rows.append(row)
	var without_signal: Array[Dictionary] = []
	for release_id: String in accepted:
		if not seen.has(release_id): without_signal.append(accepted[release_id])
	return {"accepted_input_count":accepted.size(),"observed_signal_count":rows.size(),"rows":rows,
		"accepted_without_observed_signal":without_signal,"all_observed_releases_match":all_match,
		"scope":"real Player Timer signal, live release geometry, sole production canonical result, and existing HP events within that synchronous call",
		"limits":"no source identity assigned to later asynchronous HP writes; no-signal accepted inputs remain explicit, not inferred as lost or canceled"}

func _cohort_damage_evidence(first: int, identities: Dictionary) -> Dictionary:
	# Reuse the existing bounded observer after the original cohort loop. This
	# only copies committed HP writes; it adds no hot-path record or authority.
	var grouped: Dictionary = {}
	for identity: Dictionary in identities.values():
		var entry: Dictionary = identity.duplicate(true)
		entry.merge({"rows":[],"source_counts":{},"actual_hp_loss":0,"last_observed_hp":int(identity.initial_hp),
			"unobserved_hp_gaps":[],"unobserved_hp_gained":0,"terminal_regen_state":{},
			"first_physics_tick":-1,"last_physics_tick":-1,"identity_and_order_match":true,"final_hp":-1})
		grouped[int(identity.runtime_id)] = entry
	for index in range(first,DamageObserver.events.size()):
		var row: Dictionary = DamageObserver.events[index]
		var victim_id := int(row.victim_instance_id)
		if not grouped.has(victim_id): continue
		var entry: Dictionary = grouped[victim_id]
		var gain := int(row.hp_before)-int(entry.last_observed_hp)
		if gain!=0:
			entry.unobserved_hp_gaps.append({"previous_damage_after_hp":int(entry.last_observed_hp),
				"next_damage_before_hp":int(row.hp_before),"delta":gain,"next_physics_tick":int(row.physics_tick)})
			entry.unobserved_hp_gained += gain
		entry.identity_and_order_match = bool(entry.identity_and_order_match) and int(row.victim_life)==int(entry.life) \
			and int(row.victim_generation)==int(entry.generation) and gain>=0 \
			and int(row.actual_hp_delta)==int(row.hp_before)-int(row.hp_after)
		entry.rows.append(row)
		entry.actual_hp_loss += int(row.actual_hp_delta)
		entry.last_observed_hp = int(row.hp_after)
		if int(entry.first_physics_tick)<0: entry.first_physics_tick = int(row.physics_tick)
		entry.last_physics_tick = int(row.physics_tick)
		var source_key := JSON.stringify(row.source)
		entry.source_counts[source_key] = int(entry.source_counts.get(source_key,0))+1
	for actor: EnemyActor in targets:
		if is_instance_valid(actor) and grouped.has(actor.get_instance_id()):
			grouped[actor.get_instance_id()].final_hp = actor.current_hp
			grouped[actor.get_instance_id()].terminal_regen_state = actor._natural_regen.state_snapshot()
	for death: Dictionary in death_collision_observations:
		var victim_id := int(death.instance_id)
		if grouped.has(victim_id) and int(grouped[victim_id].final_hp)<0:
			grouped[victim_id].final_hp = int(death.enemy_hp)
			grouped[victim_id].terminal_regen_state = death.natural_regen_state_at_death
	var all_match := grouped.size()==30
	for entry: Dictionary in grouped.values():
		var terminal_gain := int(entry.final_hp)-int(entry.last_observed_hp)
		if terminal_gain!=0:
			entry.unobserved_hp_gaps.append({"previous_damage_after_hp":int(entry.last_observed_hp),
				"terminal_hp":int(entry.final_hp),"delta":terminal_gain,"terminal_physics_tick":Engine.get_physics_frames()})
			entry.unobserved_hp_gained += terminal_gain
		var initial_regen: Dictionary = entry.initial_regen_state
		var terminal_regen: Dictionary = entry.terminal_regen_state
		var available_ticks := int(terminal_regen.get("total_ticks",-1))-int(initial_regen.total_ticks)
		entry.regen_gain_capacity = available_ticks*int(entry.natural_regen_hp_per_tick)
		entry.gains_within_observed_regen_capacity = available_ticks>=0 \
			and int(entry.unobserved_hp_gained)>=0 and int(entry.unobserved_hp_gained)<=int(entry.regen_gain_capacity)
		entry.hp_reconciles = bool(entry.identity_and_order_match) and int(entry.final_hp)>=0 \
			and terminal_gain>=0 and bool(entry.gains_within_observed_regen_capacity) \
			and int(entry.initial_hp)+int(entry.unobserved_hp_gained)-int(entry.actual_hp_loss)==int(entry.final_hp)
		all_match = all_match and bool(entry.hp_reconciles)
	return {"targets":grouped.values(),"all_hp_writes_reconcile":all_match,"observer_overflowed":DamageObserver.overflowed,
		"scope":"existing bounded actual HP observer; exact cohort identity and ordered mutations; post-loop read-only snapshot",
		"source_limits":"source dictionaries preserved verbatim; UNKNOWN is not inferred as periodic or child",
		"gain_limits":"damage-only observer omits healing writes; positive gaps remain unobserved gains, compatible with the actual bounded natural-regen ticks, not separately measured healing"}

func _player_damage_evidence(first: int, first_admission: int, first_delivery: int, first_terminal: int) -> Dictionary:
	var rows: Array[Dictionary] = []
	var admissions: Array[Dictionary] = []
	var deliveries: Array[Dictionary] = []
	var terminals: Array[Dictionary] = []
	var actual_loss := 0
	var player_identity: int = game.player.get_instance_id()
	for index in range(first,DamageObserver.events.size()):
		var row: Dictionary = DamageObserver.events[index]
		if int(row.victim_instance_id) == player_identity:
			rows.append(row); actual_loss += int(row.actual_hp_delta)
	for index in range(first_admission,DamageObserver.admissions.size()):
		var row: Dictionary = DamageObserver.admissions[index]
		if int(row.get("target_id",row.get("target_instance_id",0))) == player_identity: admissions.append(row)
	for index in range(first_delivery,DamageObserver.deliveries.size()):
		var row: Dictionary = DamageObserver.deliveries[index]
		if int(row.get("victim_instance_id",0)) == player_identity: deliveries.append(row)
	for index in range(first_terminal,DamageObserver.terminal_events.size()):
		var row: Dictionary = DamageObserver.terminal_events[index]
		var source: Dictionary = row.get("source",{})
		if int(source.get("victim_instance_id",0)) == player_identity: terminals.append(row)
	return {"rows":rows,"actual_hp_loss":actual_loss,"admissions":admissions,"deliveries":deliveries,"terminals":terminals,
		"scope":"existing bounded read-only observer at actual admission, delivery, terminal and Player HP writes; no profile cap counted as incoming damage"}

func _memory_snapshot() -> Dictionary:
	var live := 0; var corpses := 0
	for reference: WeakRef in spawned_owners:
		var actor: EnemyActor = reference.get_ref() as EnemyActor
		if actor != null:
			live += 1
			if actor.current_hp<=0: corpses += 1
	return {"memory_static":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"samples":samples.size(),"observed_deaths":observed_deaths.size(),
		"spawned_actor_weakrefs":spawned_owners.size(),"live_spawned_nodes":live,"authored_corpse_nodes":corpses,
		"reservations":runtime.reservation_snapshot() if runtime != null else {},"receipts":runtime._receipts.size() if runtime != null else 0}

func _finish() -> void:
	observing = false
	DamageObserver.recording_enabled = original_damage_recording; DamageObserver.reset()
	if is_instance_valid(game): game.queue_free()
	var written := proof.write_receipt(_scenario()+"_test",checks,failures.size())
	print("NATURAL_SUSTAINED_",("PASS" if written and failures.is_empty() else "FAIL")," checks=",checks," failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
