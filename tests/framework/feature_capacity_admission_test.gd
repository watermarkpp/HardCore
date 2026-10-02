extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real mapped world READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var first := await Fixture.prepare_target(self,game,game.player,19,"feature_capacity_admission")
	check(first != null,"formal first AOE receiver")
	if first == null: _finish(); return
	var targets: Array[EnemyActor] = [first]
	var positions := [Vector2(41.2,13.5),Vector2(40.5,14.2)]
	for index in range(2):
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id([64,89][index]),game._canonical_ground_gu_to_screen_px(positions[index]),false,-1.0,{"respawn_enabled":false,"spawn_slot_id":"fixture:capacity:"+str(index)})
		check(actor != null and actor.projection_ready(),"formal AOE receiver "+str(index+1))
		if actor != null: targets.append(actor)
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in targets:
		actor.max_hp = 10000; actor.current_hp = 10000
		actor.direct_spell_anti_magic_points = 0; actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
		actor.direct_spell_stats_valid = true
	PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	game.player.current_mp = 100
	game._skill_cast_target = first; game._set_magic_locked_target(first,true)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"actual declared module enabled only for test")
	var original: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	var prior: Array = []
	# Historical accepted sources can remain until expiry after their equipment
	# is withdrawn. Each copied binding has an exact, separately validated
	# instance identity; no HP, handler, queue or state counter is mocked.
	for index in range(16):
		var binding: Dictionary = original[0].duplicate(true)
		binding.source.instance_id = "capacity:historical:"+str(index)
		binding.handle = Compiler.source_handle(binding.source)
		prior.append(binding)
	var created := Batch.create(game._world_context,"capacity:historical:accepted","hc.skill.wizard.ice_storm",prior,{"profile_id":PlayerState.active_profile_id})
	check(bool(created.success),"all sixteen retained historical sources satisfy production binding validation")
	if not bool(created.success): game.queue_free(); _finish(); return
	var runtime := Runtime.new(); runtime.configure(game._world_context,game._time_domains,game._combat_runtime)
	game._feature_effect_runtime = runtime
	var batch: RefCounted = created.batch; batch.begin_base_scope()
	for actor: EnemyActor in targets:
		actor.take_damage(100,game.player,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope(); check(runtime.submit_batch(batch),"complete prior AOE batch admitted")
	await _drain(runtime)
	check(runtime.active_count() == targets.size()*16,"actual accepted states fill each receiver's sixteen state slots")
	check(runtime.errors.is_empty(),"prior legal states were admitted without capacity failures")
	var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
	var hp: Array[int] = []
	for actor: EnemyActor in targets: hp.append(actor.current_hp)
	var mp: int = game.player.current_mp
	var player_rng: int = game.player._rng.state
	var root_rng: int = game._rng.state
	var accepted: bool = game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
	check(not accepted and not lease.is_accepted(),"state capacity refuses a new distinct source before action acceptance")
	check(game.player.current_mp == mp and game.player.skill_cooldown_remaining_ms("wizard.ice_storm") == 0,"capacity rejection leaves MP and cooldown untouched")
	check(game.player._rng.state == player_rng and game._rng.state == root_rng,"capacity rejection happens before old RNG consumption")
	if accepted:
		deadline = Time.get_ticks_msec()+3000
		while game.observed_releases == 0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		check(game.observed_releases == 1,"diagnostic counterexample traversed the real accepted planner")
		for index in range(targets.size()): check(targets[index].current_hp < hp[index],"counterexample committed real base HP on AOE receiver "+str(index))
		await _drain(runtime)
	check(runtime.errors.is_empty(),"no capacity refusal remains after an already accepted damage commit")
	check(runtime.pending_count() == 0,"necessary queues terminate")
	runtime.clear(); game.queue_free(); await get_tree().process_frame
	_finish()

func _drain(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: return
		await get_tree().process_frame
	check(false,"command queue terminates")

func _finish() -> void:
	if not proof.write_receipt("feature_capacity_admission_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_CAPACITY_ADMISSION_PASS" if errors.is_empty() else "FRAMEWORK_CAPACITY_ADMISSION_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
