extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REPORT := "res://outputs/test_logs/framework/natural_effect_lifecycle_trace.json"
const EXPECTED := "res://outputs/test_logs/framework/natural_effect_lifecycle_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var game: Node
var runtime: RefCounted
var targets: Array[EnemyActor] = []
var deaths := 0
var death_started_usec := 0
var death_finished_usec := 0
var stream_started_usec := 0
var stream_finished_usec := 0
var resource_mapping: Dictionary = {}
var resource_key := ""
var resource_monster_id := -1
var resource_get_before := 0
var resource_request_before := 0
var concurrent_queues := false
var observing := false
var previous_frame_usec := 0
var samples: Array[Dictionary] = []
var category_scopes: Dictionary = {}
var maximum_pending_age: Dictionary = {}
var maximum_service_age: Dictionary = {}
var scopes_closed := true
var peak_states := 0
var peak_deaths := 0
var peak_persistence := 0
var maximum_remaining_due_backlog_usec := 0
var movement_gu := 0.0
var monster_movement_gu := 0.0
var previous_player := Vector2.ZERO
var previous_actors: Dictionary = {}
var accepted_casts := 0
var rejected_inputs: Dictionary = {}
var memory_checkpoints: Array = []
var cast_targets: Dictionary = {}
var observed_deaths: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	process_priority = 10000
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not observing or not is_instance_valid(game): return
	var ground: Vector2 = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	movement_gu += ground.distance_to(previous_player); previous_player = ground
	for actor: EnemyActor in targets:
		if not is_instance_valid(actor): continue
		var id := actor.get_instance_id()
		var location: Vector2 = game._canonical_screen_px_to_ground_gu(actor.global_position)
		monster_movement_gu += location.distance_to(previous_actors.get(id,location))
		previous_actors[id] = location
	var now := Time.get_ticks_usec()
	if previous_frame_usec > 0 and samples.size() < 12000:
		samples.append({"wall_usec":now-previous_frame_usec,"memory_static":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"object_count":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"simulation_usec":game._time_domains.simulation_usec(),"ticks":runtime.metrics().ticks,
			"effects":runtime.active_count(),"deaths":game._pending_enemy_deaths.size(),
			"persistence":PlayerState._json_persistence.pending_count()+PlayerState._world_json_persistence.pending_count(),
			"resources":game._streaming_coordinator.pending_request_count()})
	previous_frame_usec = now
	var ledger := Budget.snapshot()
	scopes_closed = scopes_closed and int(ledger.open_scopes) == 0
	for category: String in ledger.categories:
		category_scopes[category] = int(category_scopes.get(category,0))+int(ledger.categories[category].scopes)
	for category: String in ledger.pending:
		maximum_pending_age[category] = maxi(int(maximum_pending_age.get(category,0)),int(ledger.pending[category].oldest_age_frames))
		if bool(ledger.pending[category].runnable):
			maximum_service_age[category] = maxi(int(maximum_service_age.get(category,0)),int(ledger.pending[category].service_age_frames))
	peak_states = maxi(peak_states,runtime.active_count())
	peak_deaths = maxi(peak_deaths,game._pending_enemy_deaths.size())
	peak_persistence = maxi(peak_persistence,PlayerState._json_persistence.pending_count()+PlayerState._world_json_persistence.pending_count())
	if runtime.has_due():
		maximum_remaining_due_backlog_usec = maxi(maximum_remaining_due_backlog_usec,game._time_domains.simulation_usec()-runtime._heap.due_usec())
	if stream_started_usec > 0 and stream_finished_usec == 0 and game._streaming_coordinator.pending_request_count() == 0:
		stream_finished_usec = now
	if deaths == 30 and death_finished_usec == 0 and _settlement_drained(): death_finished_usec = now

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"natural production run owns an isolated account")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("自然战斗压力","hc.profession.wizard").is_empty(),"real startup and profile creation")
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.equipment["hc.slot.weapon"] = Drop.create_instance(GameData.get_item_record({"item_id":85}),"natural:weapon")
	PlayerState.recalculate_stats(false)
	check(PlayerState.save_game(true,true,true),"production profile and equipment baseline saved")
	var profile: String = PlayerState.active_profile_id
	var xp_before: int = PlayerState.experience
	get_tree().node_added.connect(_observe_spawn)
	game = Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	# Test-owned source authoring input goes through real qualification and
	# compiler. The mechanic, period, geometry and action timing are unchanged.
	var bindings: Array = ContentLayers.feature_configuration().bindings.duplicate(true)
	bindings.append({"module_id":"hc.ignite","kind":"item","item_id":"hc.item.000085","mechanic_id":"hc.ignite.ice_storm"})
	bindings.append({"module_id":"hc.ignite","kind":"skill","skill_id":"hc.skill.wizard.ice_storm","mechanic_id":"hc.ignite.ice_storm"})
	var captured := Graph.capture(bindings)
	check(bool(captured.success),"three legal sources are plain authoring inputs")
	if not bool(captured.success): _finish(); return
	ContentLayers._feature_bindings = captured.value
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"default-off module enabled through real service")
	var event: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(PlayerState.feature_errors.is_empty() and event.size() == 3,"equipment, learned skill and rule compile to three actual qualified sources")
	if event.size() != 3: _finish(); return
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5,13.5)))
	# Declared stress-health/stat inputs keep actual AI, damage and death paths
	# active long enough to exercise recurring work. No per-frame heal/refund.
	PlayerState.computed_stats.magic_min = 180; PlayerState.computed_stats.magic_max = 180
	game.player.max_hp = 100000; game.player.current_hp = 100000
	game.player.max_mp = 5000; game.player.current_mp = 5000
	var mp_before: int = game.player.current_mp
	var hp_before: int = game.player.current_hp
	for index in 30:
		var point := Vector2(40.5+float(index%6)*0.72+(0.36 if int(index/6)%2 else 0.0),12.2+float(index/6)*0.64)
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(point),false,-1.0,
			{"respawn_enabled":false,"spawn_slot_id":"test:natural:"+str(index)})
		if actor != null:
			actor.max_hp = 1500; actor.current_hp = 1500
			actor.died.connect(_on_target_died); targets.append(actor)
			check(actor._hc_point_walkable(point) and actor.is_physics_processing(),"natural receiver born on walkable authored ground with AI active: "+str(index))
	check(targets.size() == 30,"all thirty real receivers exist without a gameplay cap")
	var nonoverlap := true
	for i in targets.size():
		for j in range(i):
			var a: Vector2 = game._canonical_screen_px_to_ground_gu(targets[i].global_position)
			var b: Vector2 = game._canonical_screen_px_to_ground_gu(targets[j].global_position)
			nonoverlap = nonoverlap and a.distance_to(b) >= targets[i].combat_radius_gu+targets[j].combat_radius_gu
	check(nonoverlap,"all initial receiver footprints are disjoint under the real body policy")
	if targets.size() != 30 or not nonoverlap: _finish(); return
	var visual := MonsterVisual.new()
	for id: int in [64,89,34,19]:
		var mapping: Dictionary = visual._client_mapping_for(GameData.get_monster_by_id(id))
		var key: String = visual._client_resource_cache_key(mapping)
		if not mapping.is_empty() and game._streaming_coordinator.client_resources(key).is_empty() and not game._streaming_coordinator._threaded_profile_requests.has(key):
			resource_mapping = mapping; resource_key = key; resource_monster_id = id; break
	visual.free()
	check(not resource_mapping.is_empty(),"actual uncached resource work selected")
	if resource_mapping.is_empty(): _finish(); return
	game._streaming_coordinator.register_visual(self,get_instance_id(),game.current_map_id,game._zone_generation,resource_key,{},0)
	# Capture/accept happens only inside the normal skill input entry below.
	var start := Time.get_ticks_msec()
	var next_input := start
	var next_memory := start
	previous_player = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	deadline = start+35000
	while Time.get_ticks_msec()<deadline:
		var now := Time.get_ticks_msec()
		game._on_gameplay_movement(Vector2(0.5,-0.25).normalized() if int((now-start)/1200)%2 == 0 else Vector2(-0.5,0.25).normalized())
		if now >= next_input and deaths < 30:
			next_input = now+250
			# Scripted aiming uses current visible positions and coverage. It does
			# not supply a target list to the release planner, alter its geometry,
			# or freeze receivers while the normal cast animation runs.
			var active_targets := {}
			if runtime != null:
				for state: Dictionary in runtime._states.values():
					var receiver: Node = state.target.resolve()
					if is_instance_valid(receiver): active_targets[receiver.get_instance_id()] = true
			var chosen: EnemyActor = null
			var best_score := -1
			for actor: EnemyActor in targets:
				if not is_instance_valid(actor) or actor.current_hp <= 0: continue
				var center: Vector2 = game._canonical_screen_px_to_ground_gu(actor.global_position)
				var score := 0
				for receiver: EnemyActor in targets:
					if not is_instance_valid(receiver) or receiver.current_hp <= 0: continue
					var offset: Vector2 = game._canonical_screen_px_to_ground_gu(receiver.global_position)-center
					if absf(offset.x) <= 1.5 and absf(offset.y) <= 1.5:
						score += 100 if peak_states < 90 and not active_targets.has(receiver.get_instance_id()) else 1
				if score > best_score: chosen = actor; best_score = score
			if chosen != null:
				game._set_magic_locked_target(chosen,true)
				var result: StringName = game._try_release_skill("hc.skill.wizard.ice_storm",false)
				if result == &"accepted":
					accepted_casts += 1; cast_targets[chosen.get_instance_id()] = int(cast_targets.get(chosen.get_instance_id(),0))+1
				else: rejected_inputs[str(result)] = int(rejected_inputs.get(str(result),0))+1
		if runtime == null and game._feature_effect_runtime != null:
			runtime = game._feature_effect_runtime; observing = true
		if now >= next_memory:
			next_memory = now+5000
			memory_checkpoints.append({"elapsed_ms":now-start,"memory_static":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"states":runtime.active_count() if runtime != null else 0,"samples":samples.size()})
		await get_tree().process_frame
		if runtime != null and deaths == 30 and not runtime.has_work() and _settlement_drained() and stream_finished_usec > 0: break
	game._on_gameplay_movement(Vector2.ZERO)
	observing = false
	check(runtime != null,"natural input created the real admitted effect runtime")
	if runtime == null: _finish(); return
	check(accepted_casts > 1 and movement_gu > 1.0 and monster_movement_gu > 1.0,"actual repeated skill input, Player motion and monster pursuit all ran")
	check(game.player.current_mp < mp_before and game.player.current_hp < hp_before,"natural casts spend MP and live monsters attack the Player")
	check(peak_states == 90 and int(runtime.metrics().started) >= 90,"all thirty moving receivers participate in ninety concurrent qualified states")
	check(int(runtime.metrics().ticks) >= 360 and int(runtime.metrics().tick_delivery_count) == int(runtime.metrics().ticks),"at least360 actual periodic deliveries complete without a rejected damage-port attempt")
	check(int(runtime.metrics().maximum_tick_delivery_lateness_usec) < 1000000,"actual consumption latency stays strictly below one existing period: "+str(runtime.metrics().maximum_tick_delivery_lateness_usec))
	check(deaths == 30 and not runtime.has_work() and runtime.heap_count() == 0 and runtime.errors.is_empty(),"all thirty real deaths finish and effect work drains without capacity refusal")
	check(_settlement_drained() and int(runtime.reservation_snapshot().actions) == 0 and runtime._receipts.is_empty(),"death/persistence queues, accepted producers and managed receipts drain")
	check(concurrent_queues and stream_finished_usec > 0,"real resource completion overlaps necessary settlement work and drains")
	var minimum_xp := xp_before+30*int(game._build_enemy_death_runtime_snapshot(GameData.get_monster_by_id(19)).experience)
	var expected_xp := xp_before
	var fixture_deaths := 0
	for death: Dictionary in observed_deaths.values():
		expected_xp += int(death.experience)
		if str(death.spawn_slot_id).begins_with("test:natural:"): fixture_deaths += 1
	check(fixture_deaths == 30 and expected_xp >= minimum_xp,"independent death signals contain all thirty fixture identities plus any unmodified world victims")
	check(game._enemy_death_terminal_total_count == observed_deaths.size(),"every observed death has exactly one completed production job")
	check(PlayerState.experience == expected_xp,"canonical rewards equal the exact sum of unique observed world and fixture deaths: actual=%d expected=%d fixture_only=%d" % [PlayerState.experience,expected_xp,minimum_xp])
	check(scopes_closed and samples.size() >= 120 and samples.size()<12000,"bounded raw frame observation includes no open budget scopes")
	_write(REPORT,{"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope":"PC headless natural Player/Root input, original cooldown/geometry, moving AI and formal world; declared initial stress HP/stats; single sustained cohort; not Android/GPU or infinite-memory proof",
		"phase":"before final save and cold handoff","phase_status":"PASS" if failures.is_empty() else "FAIL","phase_failures":failures,
		"accepted_casts":accepted_casts,"rejected_inputs":rejected_inputs,"player_movement_gu":movement_gu,"monster_movement_gu":monster_movement_gu,
		"deaths":deaths,"peak_states":peak_states,"peak_deaths":peak_deaths,"peak_persistence":peak_persistence,"metrics":runtime.metrics(),
		"xp_before":xp_before,"xp_after":PlayerState.experience,"expected_xp":expected_xp,"fixture_only_xp":minimum_xp,"observed_deaths":observed_deaths.values(),
		"terminal_death_jobs":game._enemy_death_terminal_jobs,
		"wall_frame_usec":_percentiles("wall_usec"),"samples":samples,"memory_checkpoints":memory_checkpoints,
		"maximum_pending_age_frames":maximum_pending_age,"maximum_service_age_frames":maximum_service_age})
	game._streaming_coordinator.unregister_visual(get_instance_id())
	var xp: int = PlayerState.experience
	check(PlayerState.save_game(true,true,true),"natural workload final save uses the real writer")
	var generation: String = PlayerState._world_clock_generation
	game.queue_free(); await get_tree().process_frame
	check(not runtime.has_work() and runtime._receipts.is_empty(),"world teardown drops final owners")
	check(PlayerState.select_character(profile) and PlayerState.experience == xp,"production reload retains exact final rewards")
	if failures.is_empty(): _write(EXPECTED,{"profile_id":profile,"experience":xp,"generation":generation,"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")})
	var cleanup := {"sample_count":samples.size(),"memory_before_observation_clear":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"objects_before_clear":int(Performance.get_monitor(Performance.OBJECT_COUNT))}
	samples.clear(); targets.clear(); previous_actors.clear(); cast_targets.clear(); runtime = null
	for frame in 4: await get_tree().process_frame
	cleanup["memory_after_observation_clear"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	cleanup["objects_after_clear"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	cleanup["orphan_nodes_after_clear"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	# Measure after releasing bounded observation arrays. Reopen the already
	# saved phase trace only after measurement; its allocation is not gameplay.
	var phase_trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	phase_trace["cleanup"] = cleanup
	phase_trace["final_checks_before_trace_write"] = checks
	phase_trace["final_status_before_trace_write"] = "PASS" if failures.is_empty() else "FAIL"
	_write(REPORT,phase_trace)
	_finish()

func _observe_spawn(node: Node) -> void:
	if node is EnemyActor:
		node.died.connect(_on_world_died)

func _on_world_died(enemy: EnemyActor, data: Dictionary) -> void:
	var identity := enemy.get_instance_id()
	check(not observed_deaths.has(identity),"world death signal is unique: "+str(identity))
	check(observed_deaths.size() < 512,"test death observation stays within its explicit bound")
	if observed_deaths.has(identity) or observed_deaths.size() >= 512: return
	var monster_id := int(data.get("monster_id",-1))
	var canonical: Dictionary = game._build_enemy_death_runtime_snapshot(GameData.get_monster_by_id(monster_id))
	observed_deaths[identity] = {"instance_id":identity,"monster_id":monster_id,
		"spawn_slot_id":str(enemy.get_meta("spawn_context",{}).get("spawn_slot_id","")),
		"experience":int(canonical.get("experience",0)),"position":str(enemy.global_position)}

func _on_target_died(_enemy: EnemyActor, _data: Dictionary) -> void:
	deaths += 1
	if deaths != 1: return
	death_started_usec = Time.get_ticks_usec()
	stream_started_usec = death_started_usec
	resource_get_before = game._streaming_coordinator.threaded_texture_get_count()
	resource_request_before = game._streaming_coordinator.threaded_texture_request_count()
	game._streaming_coordinator.request_visual_resources(self,resource_mapping,resource_monster_id)
	concurrent_queues = game._streaming_coordinator.pending_request_count() > 0 and (not game._pending_enemy_deaths.is_empty()
		or not game._prepared_enemy_death_settlement.is_empty() or PlayerState._json_persistence.pending_count() > 0)

func _settlement_drained() -> bool:
	return game._pending_enemy_deaths.is_empty() and game._prepared_enemy_death_settlement.is_empty() \
		and PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0

func _percentiles(field: String) -> Dictionary:
	var values: Array[int] = []
	for sample: Dictionary in samples: values.append(int(sample[field]))
	values.sort()
	if values.is_empty(): return {}
	return {"p50":values[ceili(values.size()*0.50)-1],"p95":values[ceili(values.size()*0.95)-1],
		"p99":values[ceili(values.size()*0.99)-1],"max":values.back()}

func _write(path: String, value: Dictionary) -> void:
	var output := FileAccess.open(path,FileAccess.WRITE)
	check(output != null,"write owned evidence "+path.get_file())
	if output != null:
		output.store_string(JSON.stringify(value)); output.flush()
		check(output.get_error() == OK,"owned evidence write completed "+path.get_file())
		output.close()

func _finish() -> void:
	observing = false
	if is_instance_valid(game): game.queue_free()
	if not proof.write_receipt("natural_effect_lifecycle_test",checks,failures.size()): failures.append("receipt")
	print("NATURAL_EFFECT_LIFECYCLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
