extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Player := preload("res://scripts/player.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Presentation := preload("res://scripts/features/presentation/presentation_port.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")

var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var errors: Array[String] = []
var clock: RefCounted
var runtime: RefCounted
var visual: RefCounted
var source: PlayerCharacter
var target: EnemyActor
var bindings: Array = []

class ObservedEnemy extends Enemy:
	var retiring_runtime: RefCounted
	var armed := false
	var calls := 0
	var nested_served := -1
	var callback_hp := -1
	var callback_scopes := -1
	func take_feature_periodic_damage(amount: int, attacker: Node2D, credit: Dictionary, receipt: Dictionary) -> void:
		calls += 1
		super.take_feature_periodic_damage(amount,attacker,credit,receipt)
		if not armed: return
		armed = false
		callback_hp = current_hp
		callback_scopes = Budget.snapshot().open_scopes
		retiring_runtime.clear()
		nested_served = retiring_runtime.pump()

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "periodic-callback-retirement"
	var world := World.new(); world.configure(self,PlayerState)
	clock = Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	source = Player.new(); add_child(source); source.set_physics_process(false)
	target = ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = 5000; target.current_hp = 5000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	visual = Presentation.new(); visual.configure(world,true)
	runtime = Runtime.new()
	check(runtime.configure(world,clock,combat,visual),"runtime has the real world, clock, HP port and cue owner")
	target.retiring_runtime = runtime
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"normal production ignite is enabled explicitly")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size() == 1 and bindings[0].definition.handler_id == "hc.ignite.v1","fixture uses the normal single ignite binding")
	for reserved: bool in [false,true]:
		var prefix := "reserved" if reserved else "unreserved"
		var release := "periodic-retirement:"+prefix
		var ticket: RefCounted
		if reserved:
			ticket = runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,1,release)
			check(ticket != null,"reserved action obtains a real admission ticket")
		var made := Batch.create(world,release,"hc.skill.wizard.ice_storm",bindings,
			{"profile_id":PlayerState.active_profile_id},clock.simulation_usec(),ticket)
		check(made.success,prefix+" creates the real damage batch")
		if not made.success: break
		var batch: RefCounted = made.batch
		check(batch.begin_base_scope(),prefix+" begins its actual base HP scope")
		target.take_damage(100,source,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
		check(batch.finish_base_scope() and runtime.submit_batch(batch),prefix+" transfers the committed HP fact")
		if ticket != null: ticket.close()
		await _pump()
		check(runtime.active_count() == 1 and runtime.heap_count() == 1 and visual.node_count() == 1,
			prefix+" owns exactly one scheduled state and actual cue before the callback")
		var before: int = target.current_hp
		var ticks_before: int = runtime.metrics().ticks
		var losses_before: int = runtime.metrics().actual_loss
		var deliveries_before: int = runtime.metrics().tick_delivery_count
		var invalidated_before: int = runtime.metrics().invalidated
		var calls_before: int = target.calls
		target.armed = true
		clock.advance_simulation(1.0)
		await _pump()
		check(target.current_hp == before-5 and target.callback_hp == before-5,
			prefix+" preserves the already committed five HP loss")
		check(target.calls == calls_before+1 and target.nested_served == 0 and target.callback_scopes == 1,
			prefix+" callback retires inside one outer consumer and cannot reenter pump")
		check(runtime.metrics().ticks == ticks_before+1 and runtime.metrics().actual_loss == losses_before+5
			and runtime.metrics().tick_delivery_count == deliveries_before+1,
			prefix+" retains exactly one successful damage delivery in the existing metrics")
		check(runtime.active_count() == 0 and runtime.heap_count() == 0 and runtime.pending_count() == 0
			and runtime.child_count() == 0 and not runtime.has_work(),
			prefix+" cannot reinsert the retired tick into the heap")
		check(visual.node_count() == 0 and visual.events.back().kind == "stop",
			prefix+" retires the original cue")
		check(_promises_empty() and Budget.snapshot().open_scopes == 0 and not runtime._pumping,
			prefix+" drains all promises and closes the original consumer and budget scope")
		clock.advance_simulation(1.0)
		await _pump()
		check(target.current_hp == before-5 and target.calls == calls_before+1
			and runtime.metrics().ticks == ticks_before+1 and runtime.metrics().tick_delivery_count == deliveries_before+1,
			prefix+" a later original period cannot write HP or count another delivery")
		check(runtime.heap_count() == 0 and runtime.errors.is_empty(),
			prefix+" a later pump has no orphan heap or state mismatch")
		check(runtime.metrics().invalidated == invalidated_before+1 and runtime.metrics().expired == 0,
			prefix+" cancelled state reports one terminal outcome")
		check(runtime.configure(world,clock,combat,visual),prefix+" fully retired runtime can be configured again")
	target.retiring_runtime = null
	runtime.clear()
	target.queue_free(); source.queue_free(); combat.queue_free()
	await get_tree().process_frame
	if not proof.write_receipt("periodic_callback_retirement_test",proof.records.size(),errors.size()): errors.append("receipt")
	print(("FRAMEWORK_PERIODIC_CALLBACK_RETIREMENT_PASS" if errors.is_empty() else "FRAMEWORK_PERIODIC_CALLBACK_RETIREMENT_FAIL")
		+" checks="+str(proof.records.size())+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _promises_empty() -> bool:
	for count: int in runtime.reservation_snapshot().values():
		if count != 0: return false
	return true

func _pump() -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded public pump completes without replacing the production scheduler")
