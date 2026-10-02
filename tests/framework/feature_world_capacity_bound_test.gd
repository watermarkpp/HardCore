extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"formal mapped world reaches READY")
	check(game.has_method("feature_world_capacity_bound"),"formal world exposes a declared birth closure before accepting feature work")
	if not game.gameplay_input_is_enabled() or not game.has_method("feature_world_capacity_bound"):
		game.queue_free(); await get_tree().process_frame; _finish(); return
	game.set_process(false); game.set_physics_process(false)
	var initial: Dictionary = game.call("feature_world_capacity_bound")
	check(bool(initial.get("proved",false)) and int(initial.get("maximum_receivers",0)) > 0,"current formal content has a positive proved receiver bound")
	check(int(initial.get("base_slots",0)) >= game._active_enemy_cache.size(),"declared slots cover the live formal enemy population")
	var position: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5,13.5))
	var source: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(126),position,false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"fixture:world_bound:summoner"})
	check(source != null,"exact canonical summoner uses the existing production factory")
	var added: Dictionary = game.call("feature_world_capacity_bound")
	check(int(added.maximum_receivers) == int(initial.maximum_receivers)+6,"one ordinary summoner slot reserves itself and its existing five child slots")
	check(int(added.base_slots) == int(initial.base_slots)+1,"summon allowance is not miscounted as another base producer")
	if source != null:
		source.queue_free(); await get_tree().process_frame
	var dead: Dictionary = game.call("feature_world_capacity_bound")
	check(dead == added,"dead source does not erase future respawn or previous-life child allowance")
	source = game._spawn_enemy(GameData.get_monster_by_id(126),position,false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"fixture:world_bound:summoner"})
	check(source != null and game.call("feature_world_capacity_bound") == added,"replacement life reuses the exact declared slot without freezing an actor identity")
	var child: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(127),position,false,-1.0,
		{"respawn_enabled":false,"summoner_spawn_slot":"fixture:world_bound:summoner"})
	check(child != null and game.call("feature_world_capacity_bound") == added,"materialized summon transfers an existing child allowance rather than increasing the bound")
	var boss: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(160),position,true,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"fixture:world_bound:boss"})
	check(boss != null,"exact canonical stage-summoning boss uses production factory")
	var final: Dictionary = game.call("feature_world_capacity_bound")
	check(int(final.maximum_receivers) == int(added.maximum_receivers)+16,"boss allowance comes from its fifteen authored children, not an arbitrary thirty-target limit")
	check(int(final.maximum_receivers) > 30,"proof preserves worlds with more than thirty possible receivers")
	print("FEATURE_WORLD_CAPACITY_BOUND_TRACE "+JSON.stringify({"initial":initial,"summoner":added,"boss":final}))
	game.queue_free(); await get_tree().process_frame
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_world_capacity_bound_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_WORLD_CAPACITY_BOUND_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
