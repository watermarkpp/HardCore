extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Player := preload("res://scripts/player.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var _zone_generation := 1
var current_map_id := 910003
var proof := Proof.new()
var errors: Array[String] = []
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var bindings: Array = []
var target: EnemyActor
var source_a: PlayerCharacter
var source_b: PlayerCharacter

class ObservedEnemy extends Enemy:
	var periodic_calls := 0
	var last_credit: Dictionary = {}
	var periodic_release_ids: Dictionary = {}
	func take_feature_periodic_damage(amount: int, attacker: Node2D, credit: Dictionary, receipt: Dictionary) -> void:
		periodic_calls+=1; last_credit=credit.duplicate(true)
		super.take_feature_periodic_damage(amount,attacker,credit,receipt)
	func take_feature_periodic_chain_damage(amount: int, attacker: Node2D, credit: Dictionary,
		receipt: Dictionary, batch: RefCounted) -> void:
		periodic_calls+=1; last_credit=credit.duplicate(true)
		periodic_release_ids[batch.chain_context().release_id]=true
		super.take_feature_periodic_chain_damage(amount,attacker,credit,receipt,batch)

func _ready() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)
func _ground_to_screen(value: Vector2) -> Vector2: return value*10.0
func _screen_to_ground(value: Vector2) -> Vector2: return value/10.0

func _unexpected_child(_request: Dictionary, _ticket: RefCounted, _bindings: Array,
	_source: Node2D, _resources: RefCounted) -> Dictionary:
	check(false,"nonfatal refresh horizon creates no child work")
	return {"success":false,"reason":"horizon_test_has_no_fatal_child"}

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="periodic-refresh-horizon"
	await _case(false)
	await _case(true)
	_finish()

func _case(periodic_chain: bool) -> void:
	_zone_generation+=1
	var module_id: String="hc.validation.periodic_chain" if periodic_chain else "hc.validation.state_loan_lifetime"
	var path: String="res://assets/data/features/validation/periodic_chain_registry.json" if periodic_chain \
		else "res://assets/data/features/validation/state_loan_lifetime_registry.json"
	check(ContentLayers.reload_feature_catalog(path) and ContentLayers.set_feature_module_enabled(module_id,true),
		"formal module preserves the original four-second period contract: "+module_id)
	bindings=PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size()==2,"horizon unit uses actual compiled bindings rather than a fabricated periodic producer")
	if bindings.size()!=2: return
	world=World.new(); world.configure(self,PlayerState)
	clock=Clock.new(); clock.configure(self)
	var combat:=Combat.new(); add_child(combat)
	source_a=Player.new(); add_child(source_a); source_a.set_physics_process(false)
	source_b=Player.new(); add_child(source_b); source_b.set_physics_process(false)
	check(source_a.begin_combat_transition("horizon:A") and source_a.finish_combat_transition("horizon:A")
		and source_b.begin_combat_transition("horizon:B") and source_b.finish_combat_transition("horizon:B"),
		"actual source lifetimes are entered by the existing transition service")
	target=ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false)
	target.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	target.set_combat_position(_ground_to_screen(Vector2(1,0)),&"periodic_horizon_unit_position")
	target.max_hp=5000; target.current_hp=5000
	target.direct_spell_anti_magic_points=0
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0
	target.direct_spell_stats_valid=true
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_unexpected_child),
		"existing runtime and real Combat HP port own the diagnostic")
	check(_submit("horizon:A",10,source_a,"A"),"first accepted root creates its real ten-point periodic state")
	await _pump()
	var state: Dictionary=runtime._states.values()[0]
	check(state.next_due==1000000 and state.expires==4000000 and target.current_hp==4990,
		"original phase and expiry begin at one and four simulation seconds")
	check(clock.advance_simulation(100.0),"test-owned simulation advance exposes a controlled overdue state")
	check(_submit("horizon:B",1,source_b,"B"),"later accepted root commits a weaker replacement through the same real HP chain")
	# Observe the committed replacement before the existing pump can consume old
	# due work. This is an explicit unit observation, not another scheduler.
	# 2026-10-05 user ruling: the later accepted same-species application
	# atomically replaces the original incarnation — its uncommitted overdue
	# ticks are cancelled with it, and the fresh incarnation restarts strength,
	# phase and the full duration from its own application time.
	runtime._dispatch_one_fact()
	# Replacement publishes a fresh incarnation Dictionary: re-observe the live
	# head instead of the retired old incarnation captured before the ruling.
	var replaced_state: Dictionary = {}
	for live_state: Dictionary in runtime._states.values():
		if live_state.target.resolve() == target: replaced_state = live_state
	check(runtime.active_count()==1 and runtime.heap_count()==1 and replaced_state.next_due==101000000
		and replaced_state.expires==104000000 and replaced_state.raw_per_tick==1 and replaced_state.chain_owners.size()==2,
		"same-species replacement cancels overdue original ticks and restarts phase, strength and horizon at the application time")
	if periodic_chain:
		check(ContentLayers.set_feature_module_enabled(module_id,false),"accepted periodic horizon survives formal source withdrawal")
		source_a.queue_free(); await get_tree().process_frame
	await _pump()
	check(target.periodic_calls==0 and target.current_hp==4989,
		"the replaced incarnation commits no owed original ticks; only the two accepted base damage applications landed")
	check(replaced_state.next_due==101000000 and replaced_state.expires==104000000,
		"the fresh incarnation waits for its own application-anchored phase")
	for tick_index in range(4):
		check(clock.advance_simulation(1.0),"simulation reaches replacement tick second "+str(tick_index+1))
		await _pump()
	check(target.periodic_calls==4 and target.current_hp==4985,
		"exactly the four replacement ticks commit one point each within the new full duration")
	check(target.last_credit.get("marker")=="B", "the replacement's own historical credit owns the delivered ticks")
	if periodic_chain:
		check(target.periodic_release_ids.size()==4 and runtime.metrics().admitted_facts==6,
			"the four distinct replacement periodic facts reuse the resident promise without spending the direct/child cumulative quota")
		check(runtime.metrics().peak_receipts<=4,"replacement periodic identities keep dedup receipt residency within the accepted four-slot root pool")
	check(runtime.metrics().tick_delivery_count==4 and runtime.metrics().maximum_tick_delivery_lateness_usec==0,
		"cancelled overdue work is not re-delivered and the fresh phase runs without artificial lateness")
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work() and runtime.errors.is_empty(),"all original and refresh owners retire only after the shared work horizon ends")
	print("PERIODIC_REFRESH_HORIZON_OBSERVATION ",JSON.stringify({"authored_ticks_per_application":4,
		"accepted_applications":2,"actual_tick_deliveries":runtime.metrics().tick_delivery_count,
		"actual_hp":target.current_hp,"maximum_actual_lateness_usec":runtime.metrics().maximum_tick_delivery_lateness_usec,
		"periodic_chain":periodic_chain,"scope":"controlled real-HP overdue unit; not natural cadence or Root admission acceptance"}))
	check(ContentLayers.reload_feature_catalog(),"diagnostic owner restores the formal default registry")
	target.queue_free()
	if is_instance_valid(source_a): source_a.queue_free()
	source_b.queue_free(); combat.queue_free(); await get_tree().process_frame

func _submit(release: String,amount: int,source: Node2D,marker: String) -> bool:
	var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,1,release,1)
	if ticket==null: return false
	var made:=Batch.create(world,release,"hc.skill.wizard.ice_storm",bindings,
		{"profile_id":PlayerState.active_profile_id,"marker":marker},clock.simulation_usec(),ticket,null,ticket.chain_context(release))
	if not made.success: ticket.close(); return false
	var batch: RefCounted=made.batch
	if not batch.begin_base_scope(): batch.finish_production(); return false
	target.take_damage(amount,source,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	var success: bool=batch.finish_base_scope() and runtime.submit_batch(batch)
	batch.finish_production()
	return success

func _pump() -> void:
	for iteration in range(200):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded real consumer completes the diagnostic")

func _finish() -> void:
	var written:=proof.write_receipt("periodic_refresh_horizon_test",proof.records.size(),errors.size())
	print("PERIODIC_REFRESH_HORIZON_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
