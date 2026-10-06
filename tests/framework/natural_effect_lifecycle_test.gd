extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Child := preload("res://scripts/features/contracts/child_action_lease.gd")
const REPORT := "res://outputs/test_logs/framework/natural_effect_lifecycle_trace.json"
const EXPECTED := "res://outputs/test_logs/framework/natural_effect_lifecycle_expected.json"
@export var resource_backed := false
@export var periodic_children := false
var report_path := REPORT
var expected_path := EXPECTED
var resource_owner: WeakRef
var audio_cue_starts := 0
var exact_prepared_streams := 0
var peak_cue_nodes := 0
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
var resource_evidence: Dictionary = {}
var concurrent_queues := false
var observing := false
var previous_frame_usec := 0
var samples: Array[Dictionary] = []
var category_scopes: Dictionary = {}
var maximum_pending_age: Dictionary = {}
var maximum_service_age: Dictionary = {}
var scopes_closed := true
var peak_states := 0
var peak_state_evidence: Dictionary = {}
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

class ObservedChildRoot extends Root:
	var child_rows: Array[Dictionary] = []
	var child_observation_overflowed := false
	func _execute_feature_child_action(request: Dictionary, ticket: RefCounted, bindings: Array,
		source: Node2D, resources: RefCounted) -> Dictionary:
		var lease: RefCounted = Child.from_request(request)
		var command: Dictionary = lease.command() if lease != null else {}
		var started := Time.get_ticks_usec()
		var generation_before: int = _feature_effect_runtime._delivery_generation
		var root_before: bool = _feature_effect_runtime._reservations.has(ticket.sequence())
		var result := super._execute_feature_child_action(request,ticket,bindings,source,resources)
		if child_rows.size() < 512:
			child_rows.append({"root_release_id":command.get("root_release_id",""),
				"parent_release_id":command.get("parent_release_id",""),"parent_fact_id":command.get("parent_fact_id",""),
				"parent_source_class":command.get("parent_source_class","direct_or_child"),
				"parent_target":command.get("parent_target",{}),"generation":command.get("generation",-1),
				"delivery_generation_before":generation_before,"delivery_generation_after":_feature_effect_runtime._delivery_generation,
				"root_active_before":root_before,"root_active_after":_feature_effect_runtime._reservations.has(ticket.sequence()),
				"wall_usec":Time.get_ticks_usec()-started,"simulation_usec":_time_domains.simulation_usec(),
				"result":result.duplicate(true)})
		else: child_observation_overflowed = true
		return result

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	if resource_backed:
		report_path = "res://outputs/test_logs/framework/feature_resource_natural_trace.json"
		expected_path = "res://outputs/test_logs/framework/feature_resource_natural_expected.json"
	if periodic_children:
		report_path = "res://outputs/test_logs/framework/natural_periodic_chain_trace.json"
		expected_path = "res://outputs/test_logs/framework/natural_periodic_chain_expected.json"
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
	if resource_backed: peak_cue_nodes = maxi(peak_cue_nodes,runtime.presentation().node_count())
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
	if runtime.active_count() > peak_states:
		peak_states = runtime.active_count()
		peak_state_evidence = _capture_state_cohort()
	peak_deaths = maxi(peak_deaths,game._pending_enemy_deaths.size())
	peak_persistence = maxi(peak_persistence,PlayerState._json_persistence.pending_count()+PlayerState._world_json_persistence.pending_count())
	if runtime.has_due():
		maximum_remaining_due_backlog_usec = maxi(maximum_remaining_due_backlog_usec,game._time_domains.simulation_usec()-runtime._heap.due_usec())
	if stream_started_usec > 0 and stream_finished_usec == 0:
		_observe_resource_completion(now)
	if deaths == 30 and death_finished_usec == 0 and _settlement_drained(): death_finished_usec = now

func _run() -> void:
	# The runner exports APPDATA without a trailing separator; matching the
	# sandbox path itself preserves the full isolation intent.
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata"),"natural production run owns an isolated account")
	if periodic_children: check(resource_backed,"periodic-child natural variant retains the full existing required resource workload")
	PlayerState.begin_startup_save_upgrade()
	var startup_ready: bool = PlayerState.finish_startup_save_upgrade()
	var profile_name := "周期连锁实战" if periodic_children else ("资源协同战斗" if resource_backed else "自然战斗压力")
	var creation_error: String = PlayerState.create_character(profile_name,"hc.profession.wizard") if startup_ready else "startup not ready"
	check(startup_ready and creation_error.is_empty(),"real startup and profile creation: " + creation_error)
	if not startup_ready or not creation_error.is_empty(): _finish(); return
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.equipment["hc.slot.weapon"] = Drop.create_instance(GameData.get_item_record({"item_id":85}),"natural:weapon")
	PlayerState.recalculate_stats(false)
	check(PlayerState.save_game(true,true,true),"production profile and equipment baseline saved")
	var profile: String = PlayerState.active_profile_id
	var xp_before: int = PlayerState.experience
	if resource_backed:
		var registry: String = "res://assets/data/features/validation/natural_periodic_chain_registry.json" if periodic_children else "res://assets/data/features/validation/resource_natural_registry.json"
		check(await ContentLayers.reload_feature_catalog_async(registry),"resource-backed natural sources prepare all parent and child cues before world entry")
		resource_owner = weakref(ContentLayers.feature_configuration().resource_lease)
		check(resource_owner.get_ref() != null,"natural source has a nonempty accepted resource closure")
		if resource_owner.get_ref() == null: _finish(); return
	get_tree().node_added.connect(_observe_spawn)
	game = ObservedChildRoot.new() if periodic_children else Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	if resource_backed: game._audio_runtime_service.event_started.connect(_observe_feature_audio)
	# Test-owned source authoring input goes through real qualification and
	# compiler. The mechanic, period, geometry and action timing are unchanged.
	var bindings: Array = ContentLayers.feature_configuration().bindings.duplicate(true)
	bindings.append({"module_id":"hc.ignite","kind":"item","item_id":"hc.item.000085","mechanic_id":"hc.ignite.ice_storm"})
	bindings.append({"module_id":"hc.ignite","kind":"skill","skill_id":"hc.skill.wizard.ice_storm","mechanic_id":"hc.ignite.ice_storm"})
	var captured := Graph.capture(bindings)
	check(bool(captured.success),"three legal sources are plain authoring inputs")
	if not bool(captured.success): _finish(); return
	if not resource_backed:
		ContentLayers._feature_bindings = captured.value
		check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"default-off module enabled through real service")
	else:
		check(ContentLayers.feature_configuration().bindings.size() == (4 if periodic_children else 3) and "hc.ignite" in ContentLayers.feature_configuration().enabled_modules,"formal resource registry alone publishes three legal natural ignition sources")
	if periodic_children:
		check(await ContentLayers.set_feature_module_enabled_async("hc.validation.natural_periodic_chain",true),"READY publication enables the default-off real periodic-death child subscription")
	var event: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(PlayerState.feature_errors.is_empty() and event.size() == (4 if periodic_children else 3),"equipment, learned skill and rule compile to three ignition sources plus only the declared child subscription")
	if event.size() != (4 if periodic_children else 3): _finish(); return
	# Publish all thirty receivers through the real map-transition staged plan
	# collection window (shared formal fixture) AFTER the feature bindings are
	# enabled, so the receivers are born into the exact feature environment the
	# combat loop exercises. The authored grid points, slots and respawn rules
	# are unchanged; the player pre-state below is recaptured afterwards
	# because the republication rebuilds the zone.
	var descriptors: Array[Dictionary] = []
	for index in 30:
		var point := Vector2(40.5+float(index%6)*0.72+(0.36 if int(index/6)%2 else 0.0),12.2+float(index/6)*0.64)
		descriptors.append({
			"id": 19,
			"position": game._canonical_ground_gu_to_screen_px(point),
			"respawn": -1.0,
			"context": {"respawn_enabled": false, "spawn_slot_id": "test:natural:"+str(index)},
		})
	var published: Array[EnemyActor] = await Fixture.publish_targets(self,game,descriptors,"natural effect lifecycle fixture")
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
		var actor: EnemyActor = published[index]
		if actor != null:
			actor.max_hp = 1500+(index*7 if periodic_children else 0); actor.current_hp = actor.max_hp
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
	# Select/inspect the requested key at the first actual death demand below,
	# not before combat when another visual could populate it in the meantime.
	# Capture/accept happens only inside the normal skill input entry below.
	var start := Time.get_ticks_msec()
	var next_input := start
	var next_memory := start
	previous_player = game._canonical_screen_px_to_ground_gu(game.player.global_position)
	deadline = start+35000
	while Time.get_ticks_msec()<deadline:
		var now := Time.get_ticks_msec()
		# Kite instead of the old two-way shuffle: a slow circle keeps the
		# caster at AOE lock range while the pursuing pack trails behind and
		# clusters, so real struck-lock downtime stops stalling every cast
		# after the pack closes in. Monster count, 35s budget and AI unchanged.
		game._on_gameplay_movement(Vector2(cos(float(now-start)*0.0006), sin(float(now-start)*0.0006)))
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
				# Damage-budget aiming (best measured variant): the 35s cadence
				# admits ~23 casts, and thirty 1500+HP receivers need dense
				# clusters — score pure neighbour density inside the 1.5GU box.
				var score := 0
				for receiver: EnemyActor in targets:
					if not is_instance_valid(receiver) or receiver.current_hp <= 0: continue
					var offset: Vector2 = game._canonical_screen_px_to_ground_gu(receiver.global_position)-center
					if absf(offset.x) <= 1.5 and absf(offset.y) <= 1.5:
						score += 100
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
	check(peak_states == 90 and int(runtime.metrics().started) >= 90,"whole runtime reaches ninety concurrent states; named fixture coverage is recorded separately")
	check(int(peak_state_evidence.get("state_count",0)) == peak_states and bool(peak_state_evidence.get("identities_match",false)),"peak observation binds every state to its actual ActorRef identity and source")
	check(bool(peak_state_evidence.get("all_named_thirty_fixture_targets_have_three_sources",false)),"peak identity snapshot proves all thirty named fixture targets simultaneously have three distinct sources")
	check(int(runtime.metrics().ticks) >= 360 and int(runtime.metrics().tick_delivery_count) == int(runtime.metrics().ticks),"at least360 actual periodic deliveries complete without a rejected damage-port attempt")
	check(int(runtime.metrics().maximum_tick_delivery_lateness_usec) < 1000000,"actual consumption latency stays strictly below one existing period: "+str(runtime.metrics().maximum_tick_delivery_lateness_usec))
	check(deaths == 30 and not runtime.has_work() and runtime.heap_count() == 0 and runtime.errors.is_empty(),"all thirty real deaths finish and effect work drains without capacity refusal")
	check(_settlement_drained() and int(runtime.reservation_snapshot().actions) == 0 and runtime._receipts.is_empty(),"death/persistence queues, accepted producers and managed receipts drain")
	check(concurrent_queues and stream_finished_usec > 0 and bool(resource_evidence.get("five_textures_available",false)),"specified runtime-demand key completes five usable textures while settlement work overlaps")
	check(str(resource_evidence.get("request_kind","")) == "threaded_new_job" and int(resource_evidence.get("request_delta",0)) >= 5 and int(resource_evidence.get("get_delta",0)) >= 5,"chosen key was uncached at demand and finished its queued threaded profile; aggregate counts are supplementary")
	check(game._streaming_coordinator.pending_request_count() == 0,"global resource backlog also drains independently of per-key completion")
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
	var child_rows: Array = []
	if periodic_children:
		child_rows = game.child_rows
		var periodic_count := 0
		var child_results_valid := true
		for row: Dictionary in child_rows:
			periodic_count += 1 if row.parent_source_class == "periodic" else 0
			child_results_valid = child_results_valid and bool(row.result.success) and int(row.generation) == 1
		check(not game.child_observation_overflowed and not child_rows.is_empty() and child_results_valid,
			"natural child requests remain bounded observations of successful real Root plans and exact finite generations")
		check(periodic_count > 0,"at least one real periodic fatal fact naturally releases a child without direct Batch injection or a test-owned clock")
		check(int(runtime.metrics().child_actions) == child_rows.size(),"actual successful child completion count matches every observed Root request exactly")
		# 2026-10-05 user ruling: repeated accepted same-species input now
		# publishes atomic replacements instead of cumulative refreshes.
		check(int(runtime.metrics().replaced) > 0,"natural repeated accepted input exercises atomic replacement before terminal drain")
	if resource_backed:
		check(peak_cue_nodes >= 90 and audio_cue_starts > 0 and exact_prepared_streams == audio_cue_starts,"natural workload actually creates required cues and consumes only exact accepted streams")
		check(runtime.presentation().node_count() == 0 and ContentLayers._feature_resource_service.pending_count() == 0,"natural effects and resource work reach terminal drain")
	_write(report_path,{"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope":"PC headless natural Player/Root input, original cooldown/geometry, moving AI and formal world; declared initial stress HP/stats; single sustained cohort; not Android/GPU or infinite-memory proof",
		"phase":"before final save and cold handoff","phase_status":"PASS" if failures.is_empty() else "FAIL","phase_failures":failures,
		"accepted_casts":accepted_casts,"rejected_inputs":rejected_inputs,"player_movement_gu":movement_gu,"monster_movement_gu":monster_movement_gu,
		"deaths":deaths,"peak_states":peak_states,"peak_state_evidence":peak_state_evidence,"resource_evidence":resource_evidence,"peak_deaths":peak_deaths,"peak_persistence":peak_persistence,"metrics":runtime.metrics(),
		"xp_before":xp_before,"xp_after":PlayerState.experience,"expected_xp":expected_xp,"fixture_only_xp":minimum_xp,"observed_deaths":observed_deaths.values(),
		"terminal_death_jobs":game._enemy_death_terminal_jobs,
		"resource_backed":resource_backed,"peak_cue_nodes":peak_cue_nodes,"audio_cue_starts":audio_cue_starts,"exact_prepared_streams":exact_prepared_streams,
		"periodic_children":periodic_children,"child_rows":child_rows,
		"wall_frame_usec":_percentiles("wall_usec"),"samples":samples,"memory_checkpoints":memory_checkpoints,
		"maximum_pending_age_frames":maximum_pending_age,"maximum_service_age_frames":maximum_service_age})
	game._streaming_coordinator.unregister_visual(get_instance_id())
	var xp: int = PlayerState.experience
	check(PlayerState.save_game(true,true,true),"natural workload final save uses the real writer")
	var generation: String = PlayerState._world_clock_generation
	game.queue_free(); await get_tree().process_frame
	check(not runtime.has_work() and runtime._receipts.is_empty(),"world teardown drops final owners")
	if resource_backed:
		check(ContentLayers.reload_feature_catalog(),"retired world withdraws prepared authoring source through original lifecycle")
		for frame in 180:
			if resource_owner.get_ref() == null and ContentLayers._feature_resource_service.pending_count() == 0: break
			await get_tree().process_frame
		check(resource_owner.get_ref() == null and ContentLayers._feature_resource_service.pending_count() == 0,"natural closure leases and budgeted retirement drain after source withdrawal")
	check(PlayerState.select_character(profile) and PlayerState.experience == xp,"production reload retains exact final rewards")
	if failures.is_empty(): _write(expected_path,{"profile_id":profile,"experience":xp,"generation":generation,"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")})
	var cleanup := {"sample_count":samples.size(),"memory_before_observation_clear":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"objects_before_clear":int(Performance.get_monitor(Performance.OBJECT_COUNT))}
	samples.clear(); targets.clear(); previous_actors.clear(); cast_targets.clear(); runtime = null
	for frame in 4: await get_tree().process_frame
	cleanup["memory_after_observation_clear"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	cleanup["objects_after_clear"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	cleanup["orphan_nodes_after_clear"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	# Measure after releasing bounded observation arrays. Reopen the already
	# saved phase trace only after measurement; its allocation is not gameplay.
	var phase_trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	phase_trace["cleanup"] = cleanup
	phase_trace["final_checks_before_trace_write"] = checks
	phase_trace["final_status_before_trace_write"] = "PASS" if failures.is_empty() else "FAIL"
	_write(report_path,phase_trace)
	_finish()

func _observe_feature_audio(event: Dictionary) -> void:
	var handle: String = event.context.get("feature_effect_handle","")
	if handle.is_empty(): return
	audio_cue_starts += 1
	var effects: RefCounted = game._feature_effect_runtime
	var state: Dictionary = effects._states.get(handle,{})
	var lease: RefCounted = state.get("resource_lease")
	var player: AudioStreamPlayer = game._audio_runtime_service._event_players[int(event.pool_index)]
	if lease != null and is_same(player.stream,lease.resource_at(event.runtime_path)): exact_prepared_streams += 1

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
	var coordinator: RefCounted = game._streaming_coordinator
	var visual := MonsterVisual.new()
	for id: int in [64,89,34,19]:
		var mapping: Dictionary = visual._client_mapping_for(GameData.get_monster_by_id(id))
		var key: String = visual._client_resource_cache_key(mapping)
		if not mapping.is_empty() and coordinator.client_resources(key).is_empty() and not coordinator._threaded_profile_requests.has(key):
			resource_mapping = mapping; resource_key = key; resource_monster_id = id; break
	visual.free()
	check(not resource_mapping.is_empty(),"resource key is genuinely uncached at the actual first-death demand")
	if resource_mapping.is_empty(): return
	coordinator.register_visual(self,get_instance_id(),game.current_map_id,game._zone_generation,resource_key,{},0)
	stream_started_usec = death_started_usec
	resource_get_before = coordinator.threaded_texture_get_count()
	resource_request_before = coordinator.threaded_texture_request_count()
	var immediate: Dictionary = coordinator.request_visual_resources(self,resource_mapping,resource_monster_id)
	var job: Dictionary = coordinator._threaded_profile_requests.get(resource_key,{})
	resource_evidence = {"key":resource_key,"monster_id":resource_monster_id,"demand_death_identity":_enemy.get_instance_id(),
		"cache_empty_at_demand":true,"request_kind":"cache_hit" if not immediate.is_empty() else "threaded_new_job",
		"job_state_after_request":str(job.get("state","")),"request_sequence":int(job.get("request_sequence",-1)),
		"job_map_generation":int(job.get("map_generation",-1)),"paths":job.get("paths",{}).duplicate(),
		"failure_seen":coordinator._failure_details.has(resource_key),"five_textures_available":false}
	check(immediate.is_empty() and str(job.get("state","")) in ["queued","loading"] and job.get("paths",{}).size() == 5,"specified key owns a new five-action threaded request, rather than an unrelated queue or cache hit")
	concurrent_queues = coordinator._threaded_profile_requests.has(resource_key) and (not game._pending_enemy_deaths.is_empty()
		or not game._prepared_enemy_death_settlement.is_empty() or PlayerState._json_persistence.pending_count() > 0)

func _observe_resource_completion(now: int) -> void:
	var coordinator: RefCounted = game._streaming_coordinator
	resource_evidence.failure_seen = bool(resource_evidence.failure_seen) or coordinator._failure_details.has(resource_key)
	var profile: Dictionary = coordinator.client_resources(resource_key)
	if profile.is_empty(): return
	var textures := {}
	var valid: bool = not bool(resource_evidence.failure_seen) and not coordinator._threaded_profile_requests.has(resource_key)
	var dimensions: Array = resource_mapping.get("frameSize",[])
	for action: String in ["idle","walk","attack","hit","death"]:
		var texture: Texture2D = profile.get(action) as Texture2D
		var definition: Dictionary = resource_mapping.actions.get(action,{})
		var expected := Vector2i(int(dimensions[0])*int(definition.get("framesPerDirection",1)),int(dimensions[1])*8)
		var actual := Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
		var path := texture.resource_path if texture != null else ""
		var available := texture != null and actual == expected and path == str(resource_evidence.paths.get(action,""))
		valid = valid and available
		textures[action] = {"available":available,"path":path,"expected_size":[expected.x,expected.y],"actual_size":[actual.x,actual.y]}
	resource_evidence["textures"] = textures
	resource_evidence["five_textures_available"] = valid
	resource_evidence["request_delta"] = coordinator.threaded_texture_request_count()-resource_request_before
	resource_evidence["get_delta"] = coordinator.threaded_texture_get_count()-resource_get_before
	resource_evidence["completion_usec"] = now
	resource_evidence["latency_usec"] = now-stream_started_usec
	resource_evidence["global_pending_at_completion"] = coordinator.pending_request_count()
	stream_finished_usec = now

func _capture_state_cohort() -> Dictionary:
	var grouped := {}
	var identity_ok := true
	var fixture_slots := {}
	for actor: EnemyActor in targets:
		if is_instance_valid(actor): fixture_slots[actor.get_instance_id()] = str(actor.get_meta("spawn_context",{}).get("spawn_slot_id",""))
	for state: Dictionary in runtime._states.values():
		var identity: Dictionary = state.target.identity()
		var receiver: Node = state.target.resolve(false)
		var key := JSON.stringify(identity)
		var command: Dictionary = state.command
		identity_ok = identity_ok and identity == command.target and is_instance_valid(receiver) and receiver.get_instance_id() == int(identity.runtime_id)
		if not grouped.has(key):
			grouped[key] = {"identity":identity.duplicate(true),"fixture":fixture_slots.has(int(identity.runtime_id)),
				"slot":str(receiver.get_meta("spawn_context",{}).get("spawn_slot_id","")) if is_instance_valid(receiver) else "", "sources":{},"state_count":0}
		grouped[key].sources[str(command.source_handle)] = true
		grouped[key].state_count += 1
	var fixture_complete := 0
	var world_complete := 0
	var observed_slots := {}
	for entry: Dictionary in grouped.values():
		entry.sources = entry.sources.keys()
		if entry.sources.size() == 3 and int(entry.state_count) == 3:
			if bool(entry.fixture): fixture_complete += 1; observed_slots[entry.slot] = true
			else: world_complete += 1
	var missing_slots: Array = []
	for slot: String in fixture_slots.values():
		if not observed_slots.has(slot): missing_slots.append(slot)
	missing_slots.sort()
	return {"state_count":runtime._states.size(),"identities_match":identity_ok,"target_count":grouped.size(),
		"fixture_three_source_targets":fixture_complete,"world_three_source_targets":world_complete,
		"all_named_thirty_fixture_targets_have_three_sources":fixture_complete == 30,
		"missing_three_source_fixture_slots":missing_slots,"targets":grouped.values()}

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
	var scene_id: String = "natural_periodic_chain_test" if periodic_children else ("feature_resource_natural_test" if resource_backed else "natural_effect_lifecycle_test")
	if not proof.write_receipt(scene_id,checks,failures.size()): failures.append("receipt")
	print("NATURAL_EFFECT_LIFECYCLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
