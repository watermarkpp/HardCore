extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func _ready() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1; proof.record(ok,label)
	if not ok: errors.append(label)

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level=50; PlayerState.learned_skills={"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_child_chain_registry.json"),
		"formal registry accepts the finite direct/periodic/child death chain without allowing periodic ignite")
	print("PERIODIC_CHILD_CATALOG ",JSON.stringify(ContentLayers.feature_load_errors))
	if not errors.is_empty(): _finish(); return
	var game:=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var descriptors: Array[Dictionary] = [
		{"id": 19, "ground": Fixture.FIXTURE_GROUND_POSITION, "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:formal_skill:periodic_child_chain:19"}},
		{"id": 64, "ground": Vector2(43.1,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:periodic_chain:second"}},
		{"id": 64, "ground": Vector2(45.7,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:periodic_chain:third"}},
	]
	var published_targets := await Fixture.prepare_published_target_set(self, game, game.player, descriptors, "periodic_child_chain")
	var first: EnemyActor = published_targets[0]
	check(first!=null,"real factory/index/projection supplies the initial receiver")
	if first==null: game.queue_free(); _finish(); return
	var second: EnemyActor = published_targets[1]
	var third: EnemyActor = published_targets[2]
	check(second!=null and third!=null,"later mapped receivers use declared factory slots")
	if second==null or third==null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in [first,second,third]:
		actor.max_hp=1000; actor.current_hp=1000
		actor.direct_spell_anti_magic_points=0; actor.direct_spell_magic_defense_min=0
		actor.direct_spell_magic_defense_max=0; actor.direct_spell_stats_valid=true
	# The second receiver must survive its first child hit so the next death
	# wave originates from a child-created periodic state, not an immediate hit.
	first.current_hp=200; second.current_hp=120
	game.player.current_mp=100; game._skill_cast_target=first; game._set_magic_locked_target(first,true)
	check(ContentLayers.set_feature_module_enabled("hc.validation.periodic_child_chain",true),"READY enables only the default-off test module")
	var lease: RefCounted=game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease!=null and lease.event_bindings_for("hc.skill.wizard.ice_storm").size()==2,"one accepted snapshot freezes ignite and death subscriptions")
	if lease==null: game.queue_free(); _finish(); return
	var accepted: bool=game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
	print("PERIODIC_CHILD_ADMISSION ",JSON.stringify(game._feature_effect_runtime.reservation_snapshot() if game._feature_effect_runtime!=null else {}),
		" reason=",game._feature_effect_runtime.last_admission_reason if game._feature_effect_runtime!=null else "no_runtime")
	check(accepted and lease.is_accepted() and lease.effect_reservation()!=null,
		"real 85-slot world accepts the full state and finite child promise before MP/cooldown/HP")
	if not accepted: game.queue_free(); await get_tree().process_frame; _finish(); return
	check(ContentLayers.set_feature_module_enabled("hc.validation.periodic_child_chain",false),"source withdrawal preserves accepted periodic producers")
	# This trigger-only module retains release-time primary stats. Publication
	# rebuilds them; supply the controlled input after the last publication.
	PlayerState.computed_stats.magic_min=50; PlayerState.computed_stats.magic_max=50
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	var root_loss:=200-int(first.current_hp)
	check(game.observed_releases==1 and first.current_hp>0 and root_loss>0,"root hit survives; this chain must start with a real periodic death")
	var runtime: RefCounted=game._feature_effect_runtime
	if runtime==null or first.current_hp<=0: game.queue_free(); await get_tree().process_frame; _finish(); return
	var root_rng: int=game._rng.state; var player_rng: int=game.player._rng.state; var mp: int=game.player.current_mp
	await _settle(runtime)
	check(runtime.active_count()==1 and runtime.reservation_snapshot().actions==1,
		"root batch is gone while its accepted state still retains future child capacity")
	for second_index in range(1,10):
		game._time_domains.advance_simulation(1.0)
		await _settle(runtime)
	print("PERIODIC_CHILD_RESULT ",JSON.stringify({"root_loss":root_loss,"first":first.current_hp,"second":second.current_hp,
		"third":third.current_hp,"metrics":runtime.metrics(),"reservations":runtime.reservation_snapshot(),"errors":runtime.errors}))
	check(first.current_hp==0 and second.current_hp==0 and third.current_hp<1000 and third.current_hp>0,
		"periodic HP commits cause the two real death waves and child HP creates later ignite")
	check(first.collision_layer==0 and second.collision_layer==0,"periodic deaths immediately remove collisions")
	check(runtime.metrics().child_actions==2,"two finite periodic death branches execute exactly once")
	check(runtime.metrics().ticks>2 and runtime.metrics().started>=3,"child hits feed real later periodic states instead of being discarded")
	check(runtime.errors.is_empty() and not runtime.has_work() and runtime.reservation_snapshot().receipts==0,
		"all periodic producers/child consumers/receipts/capacity retire at the complete terminal boundary")
	check(game._rng.state==root_rng and game.player._rng.state==player_rng and game.player.current_mp==mp,
		"periodic and child work preserve old RNG streams and never charge MP again")
	game.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired world restores the original default registry")
	_finish()

func _settle(runtime: RefCounted) -> void:
	for iteration in range(240):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"shared-budget work settles without an unbounded forced pump")

func _finish() -> void:
	var written:=proof.write_receipt("feature_periodic_child_chain_test",checks,errors.size())
	print("FEATURE_PERIODIC_CHILD_CHAIN_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",checks," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
