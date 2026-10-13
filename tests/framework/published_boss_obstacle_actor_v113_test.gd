extends Node

## Actual published 236, GameRoot travel, direct damage reception, production
## observation/path scheduler, native movement/collision and attack settlement.
## Direct received damage is not a claim that a player spell can cross WORLD.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const InitialReady := preload("res://tests/helpers/formal_initial_ready.gd")
const PolyRuntime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const SCENE_ID := "published_boss_obstacle_actor_v113_test"
const MAP_ID := 918005
const MONSTER_ID := 236
const SLOT := "mse.group.v1.hidden_abyss_domain.boss_spawn.000001:0"
const START := Vector2(10,13)
const VISIBLE_PLAYER := Vector2(10,17)
const HIDDEN_PLAYER := Vector2(18,13)
const TOTAL_LIMIT_MS := 54000
const CHASE_LIMIT_MS := 18000

var proof := Proof.new()
var failures: Array[String] = []
var trace: Array = []
var positions: Array = []
var hit_events: Array = []
var invalid_segments: Array = []
var game: Node
var boss: EnemyActor
var player: PlayerCharacter
var context: Dictionary = {}
var started_ms := 0
var total_deadline_ms := 0
var stage := "boot"
var chase_summary: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	proof.record(ok,label)
	if not ok:
		failures.append(label)

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	total_deadline_ms = started_ms + TOTAL_LIMIT_MS
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 38
	PlayerState.recalculate_stats()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := mini(total_deadline_ms,Time.get_ticks_msec()+22000)
	while Time.get_ticks_msec() < deadline and not InitialReady.initial_ready_reached(game):
		await get_tree().process_frame
	check(InitialReady.initial_ready_reached(game),"formal initial home reaches complete READY within fixture budget")
	if not InitialReady.initial_ready_reached(game):
		await _finish()
		return
	stage = "travel"
	var accepted: bool = game._begin_map_transition(Callable(game,"_travel_to_map_immediate").bind(MAP_ID),MAP_ID)
	check(accepted,"actual GameRoot travel to published map918005 admitted")
	if not accepted:
		await _finish()
		return
	deadline = mini(total_deadline_ms,Time.get_ticks_msec()+12000)
	while Time.get_ticks_msec() < deadline and not _map_ready():
		await get_tree().process_frame
	check(_map_ready(),"918005 transition completes and gameplay input is enabled")
	if not _map_ready():
		await _finish()
		return
	player = game.player
	var matches: Array[EnemyActor] = []
	var live_enemy_count := 0
	for raw: Variant in game._active_enemy_cache.values():
		if not is_instance_valid(raw) or not raw is EnemyActor or raw.is_queued_for_deletion():
			continue
		var candidate := raw as EnemyActor
		if candidate.runtime_map_id != MAP_ID:
			continue
		live_enemy_count += 1
		if candidate.monster_id == MONSTER_ID and str(candidate.get_meta("spawn_slot_id","")) == SLOT:
			matches.append(candidate)
	check(matches.size() == 1,"unique existing canonical236 published slot materialized")
	check(live_enemy_count == 1,"actual918005 contains only the published boss; no unrelated AI disabled")
	if matches.size() != 1 or live_enemy_count != 1:
		await _finish()
		return
	boss = matches[0]
	context = boss._terrain_navigation_context
	check(boss.runtime_map_id == MAP_ID and boss.is_boss and boss.combat_enabled,"formal236 identity and combat admission retained")
	check(is_equal_approx(boss.combat_radius_gu,0.5),"canonical236 has real large0.5GU body")
	check(bool(context.get("valid",false)) and context.has("poly_index"),"boss consumes published polygon navigation context")
	check(not boss.stationary and boss.move_speed_gu_per_sec > 0.0,"published236 supports locomotion")
	check((boss.collision_mask & WorldSpatialRules.WORLD_MASK) != 0 and boss.collision_layer != 0,"native boss WORLD collision remains enabled")
	check(PolyRuntime.point_walkable(context,START,boss.combat_radius_gu),"full boss footprint legal at authored fixture start")
	check(PolyRuntime.point_walkable(context,VISIBLE_PLAYER,boss._target_combat_radius_gu(player)),"player visible fixture footprint legal")
	check(PolyRuntime.point_walkable(context,HIDDEN_PLAYER,boss._target_combat_radius_gu(player)),"player hidden fixture footprint legal")
	check(not PolyRuntime.segment_walkable(context,START,HIDDEN_PLAYER,boss.combat_radius_gu),"real central stone blocks direct full-body chord")
	if not failures.is_empty():
		await _finish()
		return
	stage = "aggression"
	# Sanctioned position transactions only; no target/clock/path/goal writes.
	boss.set_combat_position(game._canonical_ground_gu_to_screen_px(START),&"published_boss_fixture_setup")
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(VISIBLE_PLAYER))
	check(player.is_physics_processing(),"actual player physics remains active")
	check(boss.current_hp > 2,"both one-HP formal aggression events are nonlethal")
	_received_hit("visible",VISIBLE_PLAYER)
	check(boss.target == player,"formal received hit admits current player target")
	var event_point: Variant = boss._hc_damage_observations.get(player.get_instance_id())
	check(event_point is Vector2 and event_point.is_equal_approx(VISIBLE_PLAYER),"received hit stores attacker position at event time")
	check(boss.is_physics_processing(),"formal damage wakes actual boss physics")
	if not failures.is_empty():
		await _finish()
		return
	_snapshot("first_hit")
	# A hidden move alone must not become omniscient tracking. Observe the real
	# service's next result before delivering a second authoritative hit event.
	var prior_observation: int = boss._hc_next_observation_ms
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(HIDDEN_PLAYER))
	deadline = mini(total_deadline_ms,Time.get_ticks_msec()+1800)
	var blocked_observation := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if boss._hc_next_observation_ms != prior_observation and not boss._hc_observed:
			blocked_observation = true
			break
	check(blocked_observation,"actual observation service reports target hidden behind central stone")
	check(boss._hc_known_ground.is_equal_approx(VISIBLE_PLAYER),"hidden movement alone preserves old reliable position")
	check(not PolyRuntime.segment_walkable(context,boss.spatial_index_position(),HIDDEN_PLAYER,0.0),"published WORLD still blocks actor-to-hidden-player line")
	_snapshot("hidden_without_new_event")
	if not failures.is_empty():
		await _finish()
		return
	_received_hit("hidden_event",HIDDEN_PLAYER)
	check(boss.target == player and boss._hc_known_ground.is_equal_approx(HIDDEN_PLAYER),"second formal received hit supplies new reliable hidden position")
	check(boss.is_physics_processing() and player.is_physics_processing(),"both actors retain real physics for pursuit")
	if not failures.is_empty():
		await _finish()
		return
	await _observe_pursuit()
	await _finish()

func _map_ready() -> bool:
	return is_instance_valid(game) and int(game.current_map_id) == MAP_ID and not game._map_transition_in_progress and game.gameplay_input_is_enabled()

func _received_hit(label: String, point: Vector2) -> void:
	var hp_before := boss.current_hp
	boss.take_damage(1,player,{"source_class":"direct","damage_channel":"magic_defense"})
	var actual_loss := hp_before-boss.current_hp
	hit_events.append({"stage":label,"attacker_ground":_vec(point),"hp_before":hp_before,
		"hp_after":boss.current_hp,"actual_loss":actual_loss,"target_is_player":boss.target == player,
		"known_ground":_vec(boss._hc_known_ground),"physics_frame":Engine.get_physics_frames()})
	check(actual_loss == 1 and boss.current_hp > 0,label+": public take_damage commits exactly one nonlethal HP loss")

func _observe_pursuit() -> void:
	stage = "pursuit"
	var begin := Time.get_ticks_msec()
	var deadline := mini(total_deadline_ms,begin+CHASE_LIMIT_MS)
	var first := boss.spatial_index_position()
	var previous := first
	var player_hp_before := player.current_hp
	var starts_before := boss._hc_starts
	var settlements_before := boss._hc_settlements
	var route_found := false
	var detoured := false
	var reached_contact := false
	var movement := 0.0
	var frames := 0
	var physics_preserved := true
	var last_status := ""
	_snapshot("pursuit_start")
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(boss) or boss.is_queued_for_deletion() or not is_instance_valid(player):
			break
		var current := boss.spatial_index_position()
		var player_ground: Vector2 = game._canonical_screen_px_to_ground_gu(player.global_position)
		movement += current.distance_to(previous)
		physics_preserved = physics_preserved and boss.is_physics_processing() and player.is_physics_processing() and (boss.collision_mask & WorldSpatialRules.WORLD_MASK) != 0
		var segment_clear := PolyRuntime.segment_walkable(context,previous,current,boss.combat_radius_gu)
		if not segment_clear and invalid_segments.size() < 8:
			invalid_segments.append({"frame":frames,"a":_vec(previous),"b":_vec(current),"radius":boss.combat_radius_gu})
		positions.append([frames,current.x,current.y,player_ground.x,player_ground.y])
		route_found = route_found or boss._hc_path_status == "FOUND"
		# At x=14 the stone occupies y=[11,15]. A real 0.5-radius traversal
		# must cross that midline above10.5 or below15.5, not through the stone.
		if previous.x < 14.0 and current.x >= 14.0 and current.x > previous.x:
			var crossing_y := lerpf(previous.y,current.y,(14.0-previous.x)/(current.x-previous.x))
			detoured = detoured or crossing_y <= 10.5 or crossing_y >= 15.5
		if current.x > 16.5 and current.distance_to(player_ground) <= boss.HCPolicy.START_GU + 0.00001 and PolyRuntime.segment_walkable(context,current,player_ground,0.0):
			reached_contact = true
		if frames % 15 == 0 or boss._hc_path_status != last_status:
			_snapshot("pursuit")
			last_status = boss._hc_path_status
		previous = current
		if reached_contact and boss._hc_starts > starts_before and boss._hc_settlements > settlements_before and player.current_hp < player_hp_before:
			break
		if player.current_hp <= 0:
			break
	chase_summary = {"elapsed_ms":Time.get_ticks_msec()-begin,"physics_samples":frames,
		"start":_vec(first),"end":_vec(previous),"movement_gu":movement,"found":route_found,
		"crossed_stone_midline_by_detour":detoured,"reached_contact":reached_contact,
		"starts":boss._hc_starts-starts_before,"settlements":boss._hc_settlements-settlements_before,
		"player_hp_before":player_hp_before,"player_hp_after":player.current_hp,
		"physics_collision_preserved":physics_preserved,"invalid_segments":invalid_segments}
	_snapshot("pursuit_end")
	check(frames > 0 and movement > 4.0,"real boss physics makes substantial position progress")
	check(route_found,"actual actor scheduler completes FOUND around published central stone")
	check(detoured,"actual boss crosses stone midline on a legal lateral detour")
	check(invalid_segments.is_empty(),"every observed native movement segment preserves full0.5GU WORLD collision")
	check(physics_preserved,"boss/player physics and boss WORLD collision stay active")
	check(reached_contact,"boss reaches real player contact with unobstructed WORLD line")
	check(boss._hc_starts > starts_before and boss._hc_settlements > settlements_before,"real attack admission and settlement occur after detour")
	check(player.current_hp < player_hp_before,"published boss causes actual player HP loss after detour")

func _snapshot(label: String) -> void:
	if not is_instance_valid(boss):
		return
	var scheduler: Dictionary = {}
	if is_instance_valid(boss._hc_scheduler):
		scheduler = boss._hc_scheduler.work_snapshot()
		scheduler["expansions"] = boss._hc_scheduler.expansions_count
		scheduler["cancelled"] = boss._hc_scheduler.cancelled_count
		var job: Dictionary = boss._hc_scheduler.jobs.get(boss.get_instance_id(),{})
		if not job.is_empty():
			scheduler["actor_search_state"] = job.search.state
			scheduler["actor_search_expansions"] = job.search.expansions
	var route: Array = []
	for point: Vector2 in boss._hc_route:
		route.append(_vec(point))
	trace.append({"label":label,"elapsed_ms":Time.get_ticks_msec()-started_ms,"frame":Engine.get_physics_frames(),
		"ground":_vec(boss.spatial_index_position()),"player_ground":_vec(game._canonical_screen_px_to_ground_gu(player.global_position)),
		"known":_vec(boss._hc_known_ground),"observed":boss._hc_observed,"target_is_player":boss.target == player,
		"reason":boss._hc_last_reason,"path_status":boss._hc_path_status,"pending":boss._hc_path_pending,
		"token":boss._hc_path_token,"anchor":_vec(boss._hc_path_anchor),"route":route,"route_index":boss._hc_route_index,
		"step_active":boss._movement_step_active,"step_target":_vec(boss._movement_step_target_ground_gu),
		"starts":boss._hc_starts,"settlements":boss._hc_settlements,"player_hp":player.current_hp,
		"scheduler":scheduler})

static func _vec(point: Vector2) -> Array:
	return [point.x,point.y] if point.is_finite() else []

func _finish() -> void:
	var evidence := {"scene_id":SCENE_ID,"scope":"actual_published_boss_received_damage_pursuit_not_player_spell_cast",
		"map_id":MAP_ID,"monster_id":MONSTER_ID,"slot":SLOT,"stage":stage,
		"elapsed_ms":Time.get_ticks_msec()-started_ms,"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"build_sha256":context.get("build_sha256",""),"actual_radius_gu":boss.combat_radius_gu if is_instance_valid(boss) else -1.0,
		"exact_radius_profile_present":context.get("poly_graphs",{}).has(Graph.key_for_radius(boss.combat_radius_gu)) if is_instance_valid(boss) else false,
		"hit_events":hit_events,"chase":chase_summary,"trace":trace,"positions":positions,
		"failures":failures,"device_test":"NOT_RUN"}
	var file := FileAccess.open("user://published_boss_obstacle_actor_v113.json",FileAccess.WRITE)
	check(file != null,"actor pursuit evidence file opens in isolated user data")
	if file != null:
		file.store_string(JSON.stringify(evidence,"  "))
		file.close()
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	var written := proof.write_receipt(SCENE_ID,proof.records.size(),failures.size())
	print("PUBLISHED_BOSS_OBSTACLE_ACTOR_", "PASS" if failures.is_empty() and written else "FAIL",
		" ",JSON.stringify({"checks":proof.records.size(),"failures":failures,"chase":chase_summary,"stage":stage}))
	get_tree().quit(0 if failures.is_empty() and written else 1)
