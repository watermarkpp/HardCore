extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
var proof := Proof.new()
var errors: Array[String] = []

func _ready() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _prepare(enemy: EnemyActor,hp: int) -> void:
	enemy.set_physics_process(false); enemy.max_hp=5000; enemy.current_hp=hp
	enemy.direct_spell_anti_magic_points=0
	enemy.direct_spell_magic_defense_min=0; enemy.direct_spell_magic_defense_max=0
	enemy.direct_spell_stats_valid=true

func _pump(runtime: RefCounted) -> void:
	for iteration in range(200):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded controlled production consumer finishes")

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level=50; PlayerState.learned_skills={"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/state_loan_lifetime_registry.json"),
		"formal default-off loan module uses only supported direct and child sources")
	if not errors.is_empty(): _finish(); return
	var game:=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var descriptors: Array[Dictionary] = [
		{"id": 19, "ground": Fixture.FIXTURE_GROUND_POSITION, "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:formal_skill:loan_root:19"}},
		{"id": 19, "ground": Vector2(40.8,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:loan_root:second"}},
		{"id": 19, "ground": Vector2(43.1,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:loan_root:third"}},
	]
	var published_targets := await Fixture.prepare_published_target_set(self, game, game.player, descriptors, "loan_root")
	var first: EnemyActor = published_targets[0]
	check(first!=null,"actual mapped first receiver comes from the sole Root factory")
	if first==null: game.queue_free(); _finish(); return
	var second: EnemyActor = published_targets[1]
	var third: EnemyActor = published_targets[2]
	check(second!=null and third!=null,"all later-wave slots are materialized before acceptance")
	if second==null or third==null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	_prepare(first,1); _prepare(second,5000); _prepare(third,5000)
	PlayerState.computed_stats.magic_min=100; PlayerState.computed_stats.magic_max=100
	game.player.current_mp=100
	game._skill_cast_target=first; game._set_magic_locked_target(first,true)
	check(ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime",true),"READY publication explicitly enables the test module")
	var bound: Dictionary=game.feature_world_capacity_bound()
	check(bound.proved and int(bound.maximum_receivers)>3,"full authored world bound includes every predeclared slot, rather than the three observed receivers")
	var lease: RefCounted=game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease!=null and lease.event_bindings_for("wizard.ice_storm").size()==2,"actual source freezes persistent and death subscriptions")
	if lease==null: game.queue_free(); _finish(); return
	var accepted: bool=game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
	print("STATE_LOAN_ROOT_ADMISSION ",JSON.stringify({"bound":bound,"accepted":accepted,
		"reason":game._feature_effect_runtime.last_admission_reason if game._feature_effect_runtime!=null else "runtime_missing"}))
	check(accepted and lease.is_accepted() and lease.effect_reservation()!=null,
		"real Player acceptance reserves the entire world-derived chain before MP/cooldown/HP")
	if not accepted or not lease.is_accepted(): game.queue_free(); _finish(); return
	var runtime: RefCounted=game._feature_effect_runtime
	check(runtime.reservation_snapshot().states==int(bound.maximum_receivers),
		"real accepted root promises one resident loan per legal world receiver")
	check(first.current_hp==1 and second.current_hp==5000 and third.current_hp==5000,"windup has not committed premature HP")
	check(ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime",false),"source withdrawal cannot discard the accepted chain")
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and game.observed_execution.get("accepted",false),"real timer releases once into Root planner and mapped geometry")
	check(first.current_hp==0 and second.current_hp<5000 and third.current_hp==5000,
		"base HP commits before child service and the later receiver is outside the initial hit")
	await _consume_root_facts(runtime)
	check(runtime.active_count()==1 and runtime.child_count()==1,"origin state and sealed death child coexist before life replacement")
	var old_ref: RefCounted=Actor.capture(game._world_context,second)
	second.take_damage(second.current_hp,game.player,{"source_class":"direct","damage_channel":"magic_defense"})
	check(second.collision_layer==0 and old_ref.resolve()==null,"real independent death immediately removes collision and old mutation qualification")
	var first_slot: String=str(first.get_meta("spawn_slot_id"))
	first.queue_free(); second.queue_free()
	var replacement_a: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(19),
		game._canonical_ground_gu_to_screen_px(Vector2(40.5,13.5)),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":first_slot})
	var replacement_b: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(19),
		game._canonical_ground_gu_to_screen_px(Vector2(40.8,13.5)),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"test:loan_root:second"})
	check(replacement_a!=null and replacement_b!=null and game.feature_world_capacity_bound()==bound,
		"same queued factory slots admit new lives without increasing the accepted world bound")
	if replacement_a==null or replacement_b==null: game.queue_free(); _finish(); return
	_prepare(replacement_a,5000); _prepare(replacement_b,5000)
	var mp: int=game.player.current_mp
	var root_rng: int=game._rng.state; var player_rng: int=game.player._rng.state
	await _pump(runtime)
	check(replacement_a.current_hp==4999 and replacement_b.current_hp==4999 and third.current_hp==4999,
		"real child planner queries all three current lives and commits exact-once HP through the sole port")
	check(runtime.metrics().child_actions==1,"one committed root fatal fact performs exactly one child release")
	check(runtime.active_count()==4 and runtime.reservation_snapshot().states==int(bound.maximum_receivers)-4,
		"old invalid tail and three new states remain covered by the original resident loan pool")
	check(game._rng.state==root_rng and game.player._rng.state==player_rng and game.player.current_mp==mp,
		"children consume neither old RNG streams nor player resources again")
	game._time_domains.advance_simulation(1.0); await _pump(runtime)
	check(runtime.active_count()==3 and runtime.metrics().invalidated==1
		and replacement_a.current_hp==4998 and replacement_b.current_hp==4998 and third.current_hp==4998,
		"first real service boundary retires the old tail once while all three new lives receive their accepted tick")
	game._time_domains.advance_simulation(3.0); await _pump(runtime)
	check(not runtime.has_work() and runtime.heap_count()==0 and runtime.errors.is_empty(),"original four-tick lifetime completes without dropped state promises")
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty,"all accepted branches, origin loans, owners and receipts retire together")
	game.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired controlled world restores the formal default registry")
	_finish()

func _consume_root_facts(runtime: RefCounted) -> void:
	# Explicit test observation boundary, not a new public scheduling authority.
	# Root's real base damage and actual fact capture have already completed.
	while runtime.pending_count()>0: runtime._dispatch_one_fact()

func _finish() -> void:
	var written:=proof.write_receipt("feature_state_loan_root_test",proof.records.size(),errors.size())
	print("FEATURE_STATE_LOAN_ROOT_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
