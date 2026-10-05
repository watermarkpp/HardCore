extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Overhead := preload("res://scripts/monster_overhead.gd")
const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
@export var retire_after_first_child := true
@export var miss_child_receivers := false
var proof := Proof.new()
var errors: Array[String] = []
var game: Node
var first: EnemyActor
var receiver_a: EnemyActor
var receiver_b: EnemyActor
var observation: Dictionary = {}

class ObservedRoot extends Root:
	var child_invocations := 0
	var child_result: Dictionary = {}
	var held_request: Dictionary = {}
	var held_ticket: RefCounted
	var held_bindings: Array = []
	func _execute_feature_child_action(request: Dictionary, ticket: RefCounted, bindings: Array,
		source: Node2D, resources: RefCounted) -> Dictionary:
		child_invocations += 1
		held_request = request; held_ticket = ticket; held_bindings = bindings
		child_result = super._execute_feature_child_action(request,ticket,bindings,source,resources)
		return child_result

class ObservedOverhead extends Overhead:
	var armed := false
	var after_health := Callable()
	func set_health(hp: int, hp_max: int) -> void:
		super.set_health(hp,hp_max)
		if armed:
			armed = false
			if after_health.is_valid(): after_health.call()

func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _prepare(target: EnemyActor, hp: int) -> void:
	target.set_physics_process(false); target.max_hp=5000; target.current_hp=hp
	target.direct_spell_anti_magic_points=0
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0
	target.direct_spell_stats_valid=true

func _observe_first_health() -> void:
	var runtime: RefCounted=game._feature_effect_runtime
	observation={"hp_a":receiver_a.current_hp,"hp_b":receiver_b.current_hp,
		"world":game._world_context.capture_world(),"generation_before":runtime._delivery_generation,
		"root_rng":game._rng.state,"player_rng":game.player._rng.state}
	if retire_after_first_child: runtime.clear()
	observation["generation_after"]=runtime._delivery_generation
	observation["same_world"]=observation.world==game._world_context.capture_world()

func _pump(runtime: RefCounted) -> void:
	for iteration in range(150):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded existing consumer completes the controlled probe")

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level=50; PlayerState.learned_skills={"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_chain_registry.json"),
		"existing default-off formal periodic child package loads at the retired world boundary")
	if not errors.is_empty(): _finish(); return
	game=ObservedRoot.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual mapped Root reaches READY")
	if not game.gameplay_input_is_enabled(): await _cleanup(); _finish(); return
	first=await Fixture.prepare_target(self,game,game.player,19,"child_batch_retirement")
	receiver_a=game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(Vector2(43.1,13.5)),
		false,-1.0,{"respawn_enabled":false,"spawn_slot_id":"test:child_batch_retirement:a"})
	receiver_b=game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(Vector2(43.25,13.5)),
		false,-1.0,{"respawn_enabled":false,"spawn_slot_id":"test:child_batch_retirement:b"})
	check(first!=null and receiver_a!=null and receiver_b!=null,"three exact-ID receivers come from the sole mapped factory")
	if first==null or receiver_a==null or receiver_b==null: await _cleanup(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for target: Node in get_tree().get_nodes_in_group("enemies"): target.set_physics_process(false)
	_prepare(first,200); _prepare(receiver_a,5000); _prepare(receiver_b,5000)
	check(receiver_a.get_instance_id()<receiver_b.get_instance_id(),"actual Root stable traversal reaches the observed receiver first")
	var view:=ObservedOverhead.new()
	view.setup(receiver_a.display_name,receiver_a.is_boss,receiver_a.current_hp,receiver_a.max_hp)
	view.position=receiver_a.overhead.position; view.visible=receiver_a.overhead.visible
	receiver_a.overhead.queue_free(); receiver_a.add_child(view)
	receiver_a.overhead=view; receiver_a.name_label=view.name_label
	view.after_health=_observe_first_health
	check(ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",true),"READY publication enables the explicit existing module")
	game.player.current_mp=100; game._skill_cast_target=first; game._set_magic_locked_target(first,true)
	var lease: RefCounted=game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease!=null and lease.event_bindings_for("wizard.ice_storm").size()==2,"actual lease freezes both root and periodic-child subscriptions")
	if lease==null: await _cleanup(); _finish(); return
	check(game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
		and lease.effect_reservation()!=null,"real Player accepts a nonempty complete promise before windup")
	check(ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",false),"source withdrawal preserves already accepted work")
	PlayerState.computed_stats.magic_min=50; PlayerState.computed_stats.magic_max=50
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and game.observed_execution.get("accepted",false),"real timer releases the admitted root exactly once")
	var base_loss:=200-first.current_hp
	check(base_loss>=40 and base_loss<100 and receiver_a.current_hp==5000 and receiver_b.current_hp==5000,
		"initial real geometry misses both later child receivers and does not kill the parent")
	if base_loss<40 or base_loss>=100: await _cleanup(); _finish(); return
	var runtime: RefCounted=game._feature_effect_runtime
	await _pump(runtime)
	check(runtime.active_count()==1 and runtime.child_count()==0,"real base fact starts its status without premature child work")
	var mp: int=game.player.current_mp; var root_rng: int=game._rng.state; var player_rng: int=game.player._rng.state
	var identities: Array=[Actor.capture(game._world_context,receiver_a).identity(),Actor.capture(game._world_context,receiver_b).identity()]
	if miss_child_receivers:
		# Move through the actual actor/index transaction after root acceptance.
		# The child still queries its real release geometry, never an early list.
		receiver_a.set_combat_position(game._canonical_ground_gu_to_screen_px(Vector2(47.1,13.5)),&"test_child_empty_geometry")
		receiver_b.set_combat_position(game._canonical_ground_gu_to_screen_px(Vector2(48.1,13.5)),&"test_child_empty_geometry")
	view.armed=true
	var fatal_remaining:=first.current_hp
	for tick in range(4):
		fatal_remaining=first.current_hp
		game._time_domains.advance_simulation(1.0); await _pump(runtime)
		if first.current_hp==0: break
	check(first.current_hp==0 and first.collision_layer==0 and first.collision_mask==0,"the true periodic fatal commit immediately retires parent collision")
	if miss_child_receivers:
		check(game.child_invocations==1 and observation.is_empty(),"one admitted child queries current empty geometry and never reaches a receiver HP notification")
		check(game.child_result.success and game.child_result.batch_outcome=="empty","the legitimate empty base batch has an explicit successful empty outcome")
		check(runtime.metrics().child_actions==1,"one successful empty child is counted even when its root closes during batch finish")
		var empty_result: Dictionary=game.child_result.duplicate(true)
		check(receiver_a.current_hp==5000 and receiver_b.current_hp==5000 and game.player.current_mp==mp
			and game._rng.state==root_rng and game.player._rng.state==player_rng,"empty child consumes no target HP, extra Player MP or original RNG streams")
		check(not runtime.has_work() and int(runtime.reservation_snapshot().actions)==0 and runtime.errors.is_empty(),
			"successful empty finish retires its producer, receipts, states and queue without an artificial error")
		var retried_empty: Dictionary=game._execute_feature_child_action(game.held_request,game.held_ticket,game.held_bindings,game.player,null)
		check(not retried_empty.success and retried_empty.reason=="child_owner_rejected" and runtime.metrics().child_actions==1,
			"retired empty branch replay cannot receive a second completion count")
		print("CHILD_BATCH_EMPTY_TRACE ",JSON.stringify({"identities":identities,"result":empty_result,"replay_result":retried_empty,
			"metrics":runtime.metrics(),"final_hp":[receiver_a.current_hp,receiver_b.current_hp]}))
		game.held_request={}; game.held_ticket=null; game.held_bindings=[]; lease=null
		await _cleanup(); _finish(); return
	check(game.child_invocations==1 and not observation.is_empty(),"one real child enters Root and its actual health display synchronously observes the first committed HP")
	if observation.is_empty(): await _cleanup(); _finish(); return
	check(observation.hp_a==5000-fatal_remaining and observation.hp_b==5000,
		"notification occurs after the first child HP commit and before the second, without writing either HP")
	check(observation.same_world,"the controlled retirement does not change world identity")
	check(receiver_a.current_hp==5000-fatal_remaining and receiver_b.current_hp==5000-fatal_remaining,
		"the admitted synchronous base batch completes both targets under RFC section 10.2 without rolling back the first")
	check(game.player.current_mp==mp and game._rng.state==root_rng and game.player._rng.state==player_rng,
		"child and retirement consume no additional Player resources or old RNG streams")
	var initial_result: Dictionary=game.child_result.duplicate(true)
	if retire_after_first_child:
		check(observation.generation_after==observation.generation_before+1,"clear retires exactly the original effect delivery generation")
		check(not initial_result.success and initial_result.batch_outcome=="owner_retired"
			and initial_result.reason=="feature_batch_owner_retired","retired derived transfer reports owner_retired rather than a false success")
		check(runtime.metrics().child_actions==0 and runtime.active_count()==0 and not runtime.has_work(),
			"old child does not receive a success count or publish post-retirement effects")
		var retried: Dictionary=game._execute_feature_child_action(game.held_request,game.held_ticket,game.held_bindings,game.player,null)
		check(not retried.success and retried.reason=="child_owner_rejected","an old retired branch is rejected before rebuilding another child plan")
		check(receiver_a.current_hp==5000-fatal_remaining and receiver_b.current_hp==5000-fatal_remaining
			and game.player.current_mp==mp and game._rng.state==root_rng and game.player._rng.state==player_rng,
			"old branch replay cannot add HP, MP or original RNG mutations")
	else:
		check(observation.generation_after==observation.generation_before,"control health observation never retires its owner")
		check(initial_result.success and initial_result.batch_outcome=="transferred" and runtime.metrics().child_actions==1,
			"control publishes both post-hit facts and counts the one successful child")
		check(runtime.active_count()==2,"control starts one status on each real child receiver")
		game._time_domains.advance_simulation(4.0); await _pump(runtime)
		check(not runtime.has_work() and runtime.active_count()==0,"control statuses finish their authored horizon and drain")
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and runtime.errors.is_empty(),"every producer/state/fact/receipt promise closes without delivery errors")
	print("CHILD_BATCH_RETIREMENT_TRACE ",JSON.stringify({"retire":retire_after_first_child,"identities":identities,
		"fatal_actual_loss":fatal_remaining,"observation":observation,"final_hp":[receiver_a.current_hp,receiver_b.current_hp],
		"child_result":initial_result,"metrics":runtime.metrics(),"scope":"controlled real Root/HP/health view; not a natural UI reproduction"}))
	game.held_request={}; game.held_ticket=null; game.held_bindings=[]; lease=null
	await _cleanup(); _finish()

func _cleanup() -> void:
	if is_instance_valid(game): game.queue_free()
	await get_tree().process_frame; await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired world restores the existing formal default registry")

func _finish() -> void:
	var id: String="child_batch_retirement_boundary_test" if retire_after_first_child else "child_batch_atomic_control_test"
	if miss_child_receivers: id="child_batch_empty_completion_test"
	var written:=proof.write_receipt(id,proof.records.size(),errors.size())
	print("CHILD_BATCH_RETIREMENT_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
