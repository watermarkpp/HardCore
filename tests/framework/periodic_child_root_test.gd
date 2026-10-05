extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
@export var chain_depth := 1
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
	check(false,"bounded production consumer completes")

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level=50; PlayerState.learned_skills={"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	var module_id: String="hc.validation.periodic_chain_g2" if chain_depth==2 else "hc.validation.periodic_chain"
	var registry: String="res://assets/data/features/validation/periodic_chain_g2_registry.json" if chain_depth==2 \
		else "res://assets/data/features/validation/periodic_chain_registry.json"
	check(ContentLayers.reload_feature_catalog(registry),
		"formal default-off package admits direct/periodic/child death and direct/child ignition without self-excitation")
	print("PERIODIC_CHILD_CATALOG ",JSON.stringify(ContentLayers.feature_load_errors))
	if not errors.is_empty(): _finish(); return
	var game:=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var descriptors: Array[Dictionary] = [
		{"id": 19, "ground": Fixture.FIXTURE_GROUND_POSITION, "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:formal_skill:periodic_child:19"}},
		{"id": 19, "ground": Vector2(43.1,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:periodic_child:later"}},
	]
	if chain_depth == 2:
		descriptors.append({"id": 19, "ground": Vector2(45.7,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:periodic_child:g2_later"}})
	var published_targets := await Fixture.prepare_published_target_set(self, game, game.player, descriptors, "periodic_child")
	var first: EnemyActor = published_targets[0]
	check(first!=null,"initial receiver comes from the sole mapped Root factory")
	if first==null: game.queue_free(); _finish(); return
	var later: EnemyActor = published_targets[1]
	check(later!=null,"later receiver is declared before acceptance and starts outside the direct hit")
	if later==null: game.queue_free(); _finish(); return
	var third: EnemyActor=null
	if chain_depth==2:
		third = published_targets[2]
		check(third!=null,"generation-two receiver is declared before acceptance and outside the initial and first child hits")
		if third==null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	_prepare(first,200); _prepare(later,200 if chain_depth==2 else 5000)
	if third!=null: _prepare(third,5000)
	game.player.current_mp=100
	game._skill_cast_target=first; game._set_magic_locked_target(first,true)
	check(ContentLayers.set_feature_module_enabled(module_id,true),"READY publication enables only the explicit test module")
	var bound: Dictionary=game.feature_world_capacity_bound()
	check(bound.proved and int(bound.maximum_receivers)>(3 if chain_depth==2 else 2),"complete declared world bound exceeds the observed fixture receivers")
	var lease: RefCounted=game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease!=null and lease.event_bindings_for("wizard.ice_storm").size()==2,"actual source freezes both complete subscriptions")
	if lease==null: game.queue_free(); _finish(); return
	var accepted: bool=game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
	check(accepted and lease.is_accepted() and lease.effect_reservation()!=null,
		"real Player acceptance reserves the complete root before MP/cooldown/HP")
	if not accepted: game.queue_free(); _finish(); return
	var runtime: RefCounted=game._feature_effect_runtime
	check(first.current_hp==200 and later.current_hp==(200 if chain_depth==2 else 5000),"real windup has committed no premature HP")
	check(ContentLayers.set_feature_module_enabled(module_id,false),"source withdrawal retains the accepted periodic and child obligations")
	# Publication rebuilds stats. This trigger-only module keeps the formal
	# release-time primary-stat policy, so set the controlled input afterwards.
	PlayerState.computed_stats.magic_min=50; PlayerState.computed_stats.magic_max=50
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and game.observed_execution.get("accepted",false),"real timer releases once through the existing Root planner")
	var base_loss: int=200-first.current_hp
	print("PERIODIC_CHILD_BASE ",JSON.stringify({"loss":base_loss,"hp":first.current_hp,"bound":bound}))
	check(base_loss>=40 and base_loss<100 and later.current_hp==(200 if chain_depth==2 else 5000),
		"controlled fixed-power base hit survives and needs a later fatal tick rather than an immediate death")
	if base_loss<40 or base_loss>=100: game.queue_free(); await get_tree().process_frame; _finish(); return
	await _pump(runtime)
	check(runtime.active_count()==1 and runtime.child_count()==0,"base fact creates one status and no premature death child")
	var mp: int=game.player.current_mp; var root_rng: int=game._rng.state; var player_rng: int=game.player._rng.state
	game._time_domains.advance_simulation(1.0); await _pump(runtime)
	check(first.current_hp==200-2*base_loss and first.current_hp>0 and runtime.metrics().child_actions==0,
		"first nonfatal periodic release cannot spend the later fatal release identity")
	for tick in range(3): game._time_domains.advance_simulation(1.0); await _pump(runtime)
	check(first.current_hp==0 and first.collision_layer==0 and first.collision_mask==0,
		"real periodic first death immediately removes collision")
	check(runtime.metrics().child_actions==1 and later.current_hp<5000,
		"one later fatal periodic fact releases exactly one child through real Root geometry and HP")
	check(runtime.active_count()==1 and runtime.heap_count()==1,"real child hit ignites the previously untouched receiver without recursive periodic ignition")
	if chain_depth==2:
		check(third.current_hp==5000 and later.current_hp>0,"first child leaves a living second receiver and cannot prematurely hit the third")
		var remaining: int=later.current_hp
		game._time_domains.advance_simulation(1.0); await _pump(runtime)
		check(later.current_hp==0 and later.collision_layer==0 and later.collision_mask==0,
			"the child-created status has its own later periodic first death and immediate collision retirement")
		check(runtime.metrics().child_actions==2 and third.current_hp==5000-remaining,
			"generation-one periodic death releases one generation-two Root child using actual remaining HP loss")
		check(runtime.active_count()==1 and runtime.heap_count()==1,"second child creates one final generation-two status rather than a recursive heap chain")
	check(game.player.current_mp==mp and game._rng.state==root_rng and game.player._rng.state==player_rng,
		"periodic and child work consume no extra player resources or old RNG streams")
	if chain_depth==2:
		for tick in range(4): game._time_domains.advance_simulation(1.0); await _pump(runtime)
		check(runtime.metrics().child_actions==2,"the authored finite generation bound prevents additional child releases")
	else: game._time_domains.advance_simulation(4.0); await _pump(runtime)
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work() and runtime.errors.is_empty(),"every direct/tick/child/state/receipt promise reaches terminal without truncation")
	game.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired controlled world restores the formal default registry")
	_finish()

func _finish() -> void:
	var scene_id: String="periodic_child_g2_root_test" if chain_depth==2 else "periodic_child_root_test"
	var written:=proof.write_receipt(scene_id,proof.records.size(),errors.size())
	print("PERIODIC_CHILD_ROOT_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
