extends Node

const Root := preload("res://scripts/game_root.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const ContextTokens := preload("res://scripts/monster_ai_package/m30/context_token.gd")
const PolygonRuntime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const REPORT := "res://outputs/test_logs/framework/natural_effect_recovery_cycles_trace.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var rounds: Array[Dictionary] = []

class TransitionProbe extends Root:
	var transitions := 0
	func _perform_character_select_transition() -> void:
		# Replace only the final scene navigation. The original logout/save and
		# Root exit run; no HP, input, planner, AI or queue consumer is replaced.
		transitions += 1

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"recovery cycles own isolated production account")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("持续恢复","hc.profession.wizard").is_empty(),"production startup and character creation")
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.equipment["hc.slot.weapon"] = Drop.create_instance(GameData.get_item_record({"item_id":85}),"recovery:weapon")
	PlayerState.recalculate_stats(false)
	check(PlayerState.save_game(true,true,true),"initial equipment and skill saved")
	var profile: String = PlayerState.active_profile_id
	var bindings: Array = ContentLayers.feature_configuration().bindings.duplicate(true)
	bindings.append({"module_id":"hc.ignite","kind":"item","item_id":"hc.item.000085","mechanic_id":"hc.ignite.ice_storm"})
	bindings.append({"module_id":"hc.ignite","kind":"skill","skill_id":"hc.skill.wizard.ice_storm","mechanic_id":"hc.ignite.ice_storm"})
	ContentLayers._feature_bindings = Graph.capture(bindings).value
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"three qualified sources use existing module service")
	for cycle in 4:
		await _cycle(profile,cycle)
		if rounds.size() != cycle+1: break
	check(rounds.size() == 4,"four complete same-process moving combat and saved recovery lifecycles")
	if rounds.size() == 4:
		check(int(rounds[3].objects) <= int(rounds[1].objects),"post-warmup ObjectDB count does not accumulate across recovered worlds")
		check(int(rounds[3].resources) <= int(rounds[1].resources),"post-warmup resource count does not accumulate across recovered worlds")
	var file := FileAccess.open(REPORT,FileAccess.WRITE)
	check(file != null,"open owned bounded cycle evidence")
	if file != null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"rounds":rounds,
			"scope":"PC headless four same-process real input/AI worlds; 30 receivers each, 1500 initial HP; original cooldown/geometry; intentional live-effect world retirement and real logout/save/reload, not four full kill cohorts or unlimited-duration memory proof",
			"memory_scope":"static allocation includes bounded receipt/trace growth and shared caches; exact owner weakrefs plus ObjectDB/resource counts are separate gates",
			"phase_status":"PASS" if failures.is_empty() else "FAIL"})); file.flush()
		check(file.get_error() == OK,"cycle evidence write completes"); file.close()
	if not proof.write_receipt("natural_effect_recovery_cycles_test",checks,failures.size()): failures.append("receipt")
	print("NATURAL_EFFECT_RECOVERY_CYCLES_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _cycle(profile: String,cycle: int) -> void:
	var label := "cycle "+str(cycle)+": "
	check(PlayerState.select_character(profile),label+"official saved profile selected")
	var game := TransitionProbe.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+15000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),label+"real authored world READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); await get_tree().process_frame; return
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5,13.5)))
	PlayerState.computed_stats.magic_min = 180; PlayerState.computed_stats.magic_max = 180
	game.player.max_hp = 100000; game.player.current_hp = 100000
	game.player.max_mp = 5000; game.player.current_mp = 5000
	var targets: Array[EnemyActor] = []
	for index in 30:
		var point := Vector2(40.5+float(index%6)*0.72+(0.36 if int(index/6)%2 else 0.0),12.2+float(index/6)*0.64)
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(point),false,-1.0,
			{"respawn_enabled":false,"spawn_slot_id":"test:recovery:"+str(cycle)+":"+str(index)})
		if actor != null: actor.max_hp = 1500; actor.current_hp = 1500; targets.append(actor)
	check(targets.size() == 30,label+"thirty active AI receivers spawned")
	if targets.size() != 30: game.queue_free(); await get_tree().process_frame; return
	var start := Time.get_ticks_msec()
	var next_input := start
	var accepted := 0
	var previous: Vector2 = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	var motion := 0.0
	while Time.get_ticks_msec()-start < 4000:
		var now := Time.get_ticks_msec()
		game._on_gameplay_movement(Vector2(0.5,-0.25).normalized() if int((now-start)/1200)%2 == 0 else Vector2(-0.5,0.25).normalized())
		if now >= next_input:
			next_input = now+250
			var target: EnemyActor = targets[14]
			if is_instance_valid(target) and target.current_hp > 0:
				game._set_magic_locked_target(target,true)
				if game._try_release_skill("hc.skill.wizard.ice_storm",false) == &"accepted": accepted += 1
		await get_tree().process_frame
		var current: Vector2 = game._canonical_screen_px_to_ground_gu(game.player.global_position)
		motion += current.distance_to(previous); previous = current
	game._on_gameplay_movement(Vector2.ZERO)
	var runtime: RefCounted = game._feature_effect_runtime
	check(runtime != null and accepted >= 2 and motion > 1.0,label+"multiple actual accepted casts and Player movement")
	if runtime == null: game.queue_free(); await get_tree().process_frame; return
	var metrics: Dictionary = runtime.metrics()
	check(int(metrics.ticks)>0 and runtime.active_count()>0 and runtime.errors.is_empty(),label+"live recurring work exists at legitimate world retirement")
	check(int(metrics.maximum_tick_delivery_lateness_usec)<1000000,label+"actual delivered ticks below original period")
	var owners := {"root":weakref(game),"effects":weakref(runtime),"world":weakref(game._world_context),"clock":weakref(game._time_domains),"streaming":weakref(game._streaming_coordinator)}
	var owned_category: String = runtime._category
	game._return_to_character_select()
	check(game.transitions == 1 and bool(PlayerState.last_save_result.get("success",false)),label+"real guarded logout saves before visual transition")
	game.queue_free(); await get_tree().process_frame
	check(not runtime.has_work() and runtime._receipts.is_empty() and runtime.heap_count() == 0,label+"Root exit retires all effects, producers, facts and receipts")
	runtime = null; targets.clear()
	for frame in 4: await get_tree().process_frame
	var recovery_samples: Array[Dictionary] = []
	var recovery_start := Time.get_ticks_msec()
	for sample in 3:
		while Time.get_ticks_msec()-recovery_start < sample*500: await get_tree().process_frame
		recovery_samples.append({"elapsed_ms":Time.get_ticks_msec()-recovery_start,
			"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"tweens":get_tree().get_processed_tweens().size(),"memory_static":int(Performance.get_monitor(Performance.MEMORY_STATIC))})
	var all_released := true
	for owner: WeakRef in owners.values(): all_released = all_released and owner.get_ref() == null
	var owner_state := _owner_state(owners)
	check(all_released,label+"old Root/runtime/world/clock/streaming owners are released")
	check(not Budget.snapshot().pending.has(owned_category),label+"no retired effect category remains runnable")
	check(PlayerState.select_character(profile) and PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,label+"actual saved profile reload and both writer queues drained")
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphan_count == 0,label+"no orphan scene nodes")
	var ui_refs := _ui_registrations()
	var no_dead_ui_refs := true
	for counts: Dictionary in ui_refs.values(): no_dead_ui_refs = no_dead_ui_refs and int(counts.dead) == 0
	check(no_dead_ui_refs,label+"persistent UI observers contain no destroyed-control registrations")
	var map_cache_objects := {}
	for context: Dictionary in ContextTokens._contexts: _collect_map_objects(context,map_cache_objects)
	for entry: Dictionary in PolygonRuntime._loaded: _collect_map_objects(entry.get("snapshot",{}),map_cache_objects)
	_collect_map_objects(PolygonRuntime._pending.get("snapshot",{}),map_cache_objects)
	check(ContextTokens.retained_count() <= ContextTokens.MAX_CONTEXTS and PolygonRuntime._loaded.size() <= PolygonRuntime.MAX_LOADED_RELEASES,label+"existing monotonic context-token and loaded-map caches keep their declared bounds")
	rounds.append({"cycle":cycle,"accepted":accepted,"motion_gu":motion,"ticks":metrics.ticks,"peak_states":metrics.peak_states,
		"maximum_tick_delivery_lateness_usec":metrics.maximum_tick_delivery_lateness_usec,"all_owners_released":all_released,"owner_state":owner_state,"recovery_samples":recovery_samples,
		"memory_static":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphans":orphan_count,"ui_refs":ui_refs,
		"map_cache_objects":map_cache_objects,"context_cache_count":ContextTokens.retained_count(),"context_cache_limit":ContextTokens.MAX_CONTEXTS,
		"persistent_observers":_persistent_observers()})

func _persistent_observers() -> Dictionary:
	var pending := {}
	for key: String in Budget._pending:
		var entry: Dictionary = Budget._pending[key]
		pending[key] = {"runnable":entry.get("runnable",false),"has_owner":entry.has("process_owner"),
			"owner_alive":entry.process_owner.get_ref() != null if entry.has("process_owner") else false}
	var context_fields := {}
	if not ContextTokens._contexts.is_empty():
		for key: Variant in ContextTokens._contexts[-1]:
			var value: Variant = ContextTokens._contexts[-1][key]
			context_fields[str(key)] = value.get_class() if value is Object else type_string(typeof(value))
	return {"budget_pending":pending,"audio_refs":AudioPreferences._sfx_services.size(),"profile_owners":PlayerState._profile_gameplay_owners.size(),
		"layout_token_owner":"individual Control metadata","context_fields":context_fields,
		"process_frame_connections":get_tree().get_signal_connection_list("process_frame").size(),"physics_frame_connections":get_tree().get_signal_connection_list("physics_frame").size()}

func _collect_map_objects(context: Dictionary, output: Dictionary) -> void:
	if context.get("poly_index") is RefCounted:
		var index: RefCounted = context.poly_index
		output[str(index.get_instance_id())] = index.get_script().resource_path
	for graph: RefCounted in context.get("poly_graphs",{}).values():
		output[str(graph.get_instance_id())] = graph.get_script().resource_path

func _ui_registrations() -> Dictionary:
	var result := {}
	for name: String in ["UISelectionDismissGuard","TouchScrollSupport"]:
		var owner := get_tree().root.get_node_or_null(name)
		if owner == null: continue
		var fields: Array = ["_scopes","_functional","_modals"] if name == "UISelectionDismissGuard" else ["_registered_controls"]
		for field: String in fields:
			var refs: Array = owner.get(field)
			var dead := 0
			for reference: WeakRef in refs:
				if reference.get_ref() == null: dead += 1
			result[name+field] = {"total":refs.size(),"dead":dead}
	return result

func _owner_state(owners: Dictionary) -> Dictionary:
	var result := {}
	for key: String in owners:
		var object: Object = owners[key].get_ref()
		result[key] = {"released":object == null}
		if object != null:
			result[key]["instance_id"] = object.get_instance_id()
			result[key]["references_in_probe"] = object.get_reference_count() if object is RefCounted else -1
			result[key]["script"] = object.get_script().resource_path if object.get_script() != null else ""
	return result
