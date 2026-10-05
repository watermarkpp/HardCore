extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
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
	var source_context := {"respawn_enabled":false,"spawn_slot_id":"fixture:world_bound:summoner"}
	var plan: Array[Dictionary] = [
		{"id":126,"position":position,"respawn":-1.0,"context":source_context},
		{"id":160,"position":position,"respawn":-1.0,
			"context":{"respawn_enabled":false,"spawn_slot_id":"fixture:world_bound:boss"}},
	]
	var published: Array[EnemyActor] = await Fixture.publish_targets(self,game,plan,"world_capacity_bound")
	var source: EnemyActor = published[0] if published.size() == 2 else null
	var boss: EnemyActor = published[1] if published.size() == 2 else null
	check(source != null and boss != null,"exact canonical summoner and boss use one complete published production plan")
	if source == null or boss == null:
		game.queue_free(); await get_tree().process_frame; _finish(); return
	game.player.set_physics_process(false)
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(
		Fixture.FIXTURE_GROUND_POSITION+Fixture.CASTER_GROUND_OFFSET))
	for value: Variant in game._active_enemy_cache.values():
		var actor := value as EnemyActor
		actor.set_physics_process(false)
		if actor != source and actor != boss:
			actor.set_combat_position(game.player.global_position+Vector2(3000,3000),&"world_bound_clear")
	var added: Dictionary = game.call("feature_world_capacity_bound")
	check(added.proved and added.sealed and int(added.maximum_receivers) == int(initial.maximum_receivers)+6+16,
		"one publication reserves both full closures: ordinary one plus five and boss one plus fifteen")
	check(int(added.base_slots) == int(initial.base_slots)+2,"child allowances do not become extra base producers")
	source.queue_free(); await get_tree().process_frame
	var dead: Dictionary = game.call("feature_world_capacity_bound")
	check(dead == added,"dead source does not erase future respawn or previous-life child allowance")
	source = game._spawn_enemy(GameData.get_monster_by_id(126),position,false,-1.0,source_context)
	check(source != null and game.call("feature_world_capacity_bound") == added,
		"replacement life reuses the exact published slot without freezing an actor identity")
	if source == null:
		game.queue_free(); await get_tree().process_frame; _finish(); return
	source.set_physics_process(false); source.dormant=false; source.control_time=0; source.target=game.player
	var serial: int = game._runtime_spawn_serial
	var fake: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(127),position,false,-1.0,
		{"respawn_enabled":false,"summoner_spawn_slot":"fixture:world_bound:summoner"})
	check(fake == null and game._runtime_spawn_serial == serial and game.feature_world_capacity_bound() == added,
		"copied owner labels cannot consume an original summon job or mutate the frozen bound")
	if fake != null: fake.queue_free()
	var queue: HCM30SummonQueue = game._hc_m30_get_summon_queue()
	await get_tree().physics_frame
	source._summon_cooldown=0
	source._update_behavior_summon(0.0)
	source._update_behavior_summon(0.5)
	check(int(source.get_meta("m30_summon_release_serial",0))>0 and not queue._jobs.is_empty(),
		"actual126 behavior producer issues its original accepted queue job")
	for _tick in range(120):
		if queue._jobs.is_empty(): break
		await get_tree().physics_frame
	var children: Dictionary = queue._children.get("fixture:world_bound:summoner",{})
	var child: EnemyActor
	for ref: WeakRef in children.values():
		var candidate := ref.get_ref() as EnemyActor
		if is_instance_valid(candidate) and candidate.monster_id==127:
			candidate.set_physics_process(false); child=candidate
	check(child != null and queue._jobs.is_empty() and game.call("feature_world_capacity_bound") == added,
		"real child materialization consumes the published allowance through its original one-shot job")
	check(boss.monster_id==160,"exact canonical stage-summoning boss was included before the plan sealed")
	var final: Dictionary = game.call("feature_world_capacity_bound")
	check(final == added,"all actual births preserve the one complete sealed proof")
	check(int(final.maximum_receivers) > 30,"proof preserves worlds with more than thirty possible receivers")
	print("FEATURE_WORLD_CAPACITY_BOUND_TRACE "+JSON.stringify({"initial":initial,"published":added,"dead":dead,"final":final}))
	game.queue_free(); await get_tree().process_frame
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_world_capacity_bound_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_WORLD_CAPACITY_BOUND_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
