extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/child_execution_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func _ready() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1; proof.record(ok,label)
	if not ok: errors.append(label)

func _run() -> void:
	var probe:=Root.new()
	var script: Script=probe.get_script()
	probe.free()
	var supported := false
	while script != null:
		for method: Dictionary in script.get_script_method_list():
			if method.name=="_execute_feature_child_action": supported=true
		script=script.get_base_script()
	check(supported,"the actual Root has an admitted child execution entry using the existing planner and HP port")
	if not supported: _finish(); return
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level=50; PlayerState.learned_skills={"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/child_execution_registry.json"),"finite default-off chain uses the formal registry")
	if not errors.is_empty(): _finish(); return
	var game:=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"production mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var descriptors: Array[Dictionary] = [
		{"id": 19, "ground": Fixture.FIXTURE_GROUND_POSITION, "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:formal_skill:child_execution:19"}},
		{"id": 64, "ground": Vector2(43.1,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:chain:0"}},
		{"id": 64, "ground": Vector2(53.5,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:chain:1"}},
	]
	var published_targets := await Fixture.prepare_published_target_set(self, game, game.player, descriptors, "child_execution")
	var first: EnemyActor = published_targets[0]
	check(first!=null,"real factory, spatial index and mapped first receiver")
	if first==null: game.queue_free(); _finish(); return
	var receivers: Array[EnemyActor] = published_targets
	for i in range(2):
		var actor: EnemyActor = receivers[i+1]
		check(actor!=null and actor.projection_ready(),"production later-wave receiver "+str(i))
	if receivers.size()!=3: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in receivers:
		actor.max_hp=1000; actor.current_hp=1000
		actor.direct_spell_anti_magic_points=0; actor.direct_spell_magic_defense_min=0
		actor.direct_spell_magic_defense_max=0; actor.direct_spell_stats_valid=true
	receivers[0].current_hp=20; receivers[1].current_hp=4
	PlayerState.computed_stats.magic_min=100; PlayerState.computed_stats.magic_max=100
	game.player.current_mp=100
	game._skill_cast_target=first; game._set_magic_locked_target(first,true)
	check(ContentLayers.set_feature_module_enabled("hc.validation.child_execution",true),"real READY publication enables only this bounded test primitive")
	var lease: RefCounted=game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease!=null and lease.event_bindings_for("wizard.ice_storm").size()==1,"actual source freezes one death handler")
	print("CHILD_EXECUTION_BOUND ",JSON.stringify(game.feature_world_capacity_bound()))
	if lease==null: game.queue_free(); _finish(); return
	var dry_first: RefCounted=game._reserve_feature_bindings("wizard.ice_storm",lease.event_bindings_for("wizard.ice_storm"))
	var dry_second: RefCounted=game._reserve_feature_bindings("wizard.ice_storm",lease.event_bindings_for("wizard.ice_storm"))
	check(dry_first!=null and dry_second==null and game.player.current_mp==100 and first.current_hp==20,
		"the whole breadth-first frontier rejects a second root promise before any HP or resource change")
	if dry_first!=null: dry_first.close()
	check(game._feature_effect_runtime.reservation_snapshot().actions==0 \
		and game._feature_effect_runtime.reservation_snapshot().promised_children==0,"cancelled unaccepted root returns all frontier and storage promises")
	check(game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
		and lease.is_accepted() and lease.effect_reservation()!=null,"Player accepts the entire finite chain before MP/cooldown/HP")
	if not lease.is_accepted(): game.queue_free(); _finish(); return
	check(ContentLayers.set_feature_module_enabled("hc.validation.child_execution",false),"withdrawal preserves the admitted chain")
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and game.observed_execution.get("accepted",false),"real windup releases once into the canonical root planner")
	check(first.current_hp==0 and receivers[1].current_hp==4 and receivers[2].current_hp==1000,
		"root finishes its actual HP commit before queued children; later receivers were not root hits")
	var bound_before: Dictionary=game.feature_world_capacity_bound()
	var old_ref: RefCounted=preload("res://scripts/features/contracts/actor_ref.gd").capture(game._world_context,receivers[2])
	receivers[2].queue_free(); await get_tree().process_frame
	var born: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(64),
		game._canonical_ground_gu_to_screen_px(Vector2(53.5,13.5)),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"test:chain:1"})
	check(born!=null and old_ref.resolve(false)==null and game.feature_world_capacity_bound()==bound_before,
		"a new life uses the predeclared factory slot after acceptance; old ActorRef is invalid without increasing the promised bound")
	if born==null: game.queue_free(); _finish(); return
	born.set_physics_process(false); born.max_hp=1000; born.current_hp=1000
	born.direct_spell_anti_magic_points=0; born.direct_spell_magic_defense_min=0
	born.direct_spell_magic_defense_max=0; born.direct_spell_stats_valid=true
	born.set_combat_position(game._canonical_ground_gu_to_screen_px(Vector2(45.7,13.5)),&"test_chain_late_entry")
	receivers[2]=born
	check(born.projection_ready(),"new life moves into the later wave before its actual release query")
	var runtime: RefCounted=game._feature_effect_runtime
	check(runtime!=null,"same runtime owns admitted child work")
	if runtime==null: game.queue_free(); _finish(); return
	var root_rng: int=game._rng.state; var player_rng: int=game.player._rng.state
	var mp: int=game.player.current_mp
	for iteration in range(200):
		runtime.pump()
		if not runtime.has_work(): break
		await get_tree().process_frame
	check(receivers[1].current_hp==0 and receivers[2].current_hp==998,
		"actual release-time circle query reaches wave one and then wave two through the sole HP port")
	check(first.collision_layer==0 and receivers[1].collision_layer==0,"both deaths immediately release collision")
	check(runtime.metrics().get("child_actions",0)==2,"exactly two finite child releases execute")
	check(game.tested_child_callbacks==2 and game.forged_child_rejected and game.forged_child_quiet,
		"a syntactically valid nonexistent parent fact cannot steal either real branch ticket or mutate resources/HP/RNG")
	check(game._rng.state==root_rng and game.player._rng.state==player_rng and game.player.current_mp==mp,
		"children neither consume old random streams nor charge player resources again")
	check(runtime.errors.is_empty() and not runtime.has_work() and runtime.reservation_snapshot().actions==0
		and runtime.reservation_snapshot().receipts==0,"all child consumers retire before root capacity and receipts are reclaimed")
	check(not lease.effect_reservation().can_begin_release(str(game.observed_target_context.get("release_id",""))),"retired old root cannot re-enter after receipt reclamation")
	game.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired world restores the original default-off registry")
	_finish()

func _finish() -> void:
	var written:=proof.write_receipt("feature_child_execution_test",checks,errors.size())
	print("FEATURE_CHILD_EXECUTION_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",checks," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
