extends Node
const Formal := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var actor: EnemyActor
var victim: PlayerCharacter
var samples: Array = []
var errors: Array[String] = []
var collecting := false
var finished := false
var first_game_s := 0.0
var last_clock := -1.0
var last_tick := -1
var hp_before := 0
var rows: Array = []
func _ready() -> void:
	process_physics_priority = 10000
	run.call_deferred()
func _physics_process(delta: float) -> void:
	if not collecting:
		return
	var source := actor._screen_position_px_to_ground_position_gu(actor.global_position)
	var target_position := actor._screen_position_px_to_ground_position_gu(victim.global_position)
	if source.distance_to(target_position)<actor.combat_radius_gu+actor._target_combat_radius_gu(victim)-.001:
		errors.append("published map body overlap")
	if last_tick>=0 and (Engine.get_physics_frames()!=last_tick+1 or absf(actor._combat_action_time_s-last_clock-delta)>.00001):
		errors.append("published map sampling is not consecutive native owner time")
	last_clock = actor._combat_action_time_s
	last_tick = Engine.get_physics_frames()
	samples.append({"tick":last_tick,"game_s":last_clock,"source":[source.x,source.y],"target":[target_position.x,target_position.y],"starts":actor._hc_starts,"settlements":actor._hc_settlements,"hp":victim.current_hp})
	if actor._hc_starts>=2 and actor._hc_settlements>=2 and victim.current_hp<hp_before:
		finished = true
	if last_clock-first_game_s>20.0 or not errors.is_empty():
		finished = true
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	# Cold published-world loading is asynchronous. Keep its own bounded
	# readiness observation before invoking the shared five-second hot gate.
	var ready_deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<ready_deadline:
		await get_tree().process_frame
	await Formal.wait_for_formal_world(self,game,"R3 published map")
	victim = game.player
	victim.set_physics_process(false)
	for id: int in [64,89,81]:
		actor = await Formal.prepare_target(self,game,victim,id,"R3 published approach")
		actor.control_time = 0.0
		var target_ground: Vector2 = game._canonical_screen_px_to_ground_gu(victim.global_position)
		var candidate := Vector2.INF
		for offset: Vector2 in [Vector2(5,0),Vector2(0,5),Vector2(-5,0),Vector2(0,-5)]:
			if actor._locomotion_segment_clear(target_ground+offset,target_ground):
				candidate = target_ground+offset
				break
		if not candidate.is_finite():
			errors.append("published fixture has no legal 5GU segment")
			break
		actor.set_combat_position(game._canonical_ground_gu_to_screen_px(candidate),&"r3_published_setup")
		actor.target = victim
		actor.take_damage(1,victim)
		victim.max_hp = 1000000
		victim.current_hp = victim.max_hp
		hp_before = victim.current_hp
		samples = []
		last_tick = -1
		last_clock = -1.0
		finished = false
		first_game_s = actor._combat_action_time_s
		collecting = true
		actor.set_physics_process(true)
		for n in range(1500):
			await get_tree().physics_frame
			if finished:
				break
		collecting = false
		actor.set_physics_process(false)
		if actor._hc_starts<2 or actor._hc_settlements<2 or victim.current_hp>=hp_before:
			errors.append("published approach lacks real attacks/damage: "+str(id))
		rows.append({"monster_id":id,"display_name":actor.display_name,"runtime_map_id":actor.runtime_map_id,"terrain_build_sha256":actor._terrain_navigation_context.get("build_sha256",""),"samples":samples})
		actor.queue_free()
		await get_tree().process_frame
	game.queue_free()
	await get_tree().process_frame
	F.write_evidence("published_map_approach",{"errors":errors,"rows":rows,"scope":"real GameRoot published map, exact mapped spawns; isolated from unrelated actors"})
	print(("R3_PUBLISHED_APPROACH_PASS" if errors.is_empty() else "R3_PUBLISHED_APPROACH_FAIL")+" cases="+str(rows.size())+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
