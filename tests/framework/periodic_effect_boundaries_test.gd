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
var _zone_generation := 1
var current_map_id := 910001
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var target: EnemyActor
var source: PlayerCharacter
var bindings: Array = []
class ObservedEnemy extends Enemy:
	var credits: Array[Dictionary] = []
	func take_feature_periodic_damage(amount: int, attacker: Node2D, credit: Dictionary, receipt: Dictionary) -> void:
		credits.append(credit.duplicate(true))
		super.take_feature_periodic_damage(amount,attacker,credit,receipt)
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "periodic-boundary-owner"
	world = World.new(); world.configure(self,PlayerState)
	clock = Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	target = ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = 5000; target.current_hp = 5000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	source = Player.new(); add_child(source); source.set_physics_process(false)
	var visual := Presentation.new(); visual.configure(world,true)
	runtime = Runtime.new(); runtime.configure(world,clock,combat,visual)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"qualified effect source enabled")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	await _submit("boundaries:first",100)
	check(runtime.active_count() == 1 and visual.node_count() == 1,"logic starts one state and explicit cue handle")
	clock.advance_simulation(0.5)
	await _submit("boundaries:weak",40)
	check(runtime.active_count() == 1 and runtime.heap_count() == 1 and visual.node_count() == 1,"weaker refresh preserves one state, one heap node and one visual")
	clock.advance_simulation(0.5)
	var before: int = target.current_hp
	await _pump()
	check(target.current_hp == before-5,"weak refresh retains stronger five damage and original first tick phase")
	clock.advance_simulation(0.5)
	await _submit("boundaries:strong",200)
	get_tree().paused = true
	var stopped: int = clock.simulation_usec()
	check(not clock.advance_simulation(2.0) and runtime.pump() == 0 and clock.simulation_usec() == stopped,"pause advances neither simulation nor tick debt")
	get_tree().paused = false
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"source is actually withdrawn")
	source.queue_free(); await get_tree().process_frame
	clock.advance_simulation(0.5)
	target.direct_spell_magic_defense_min = 3; target.direct_spell_magic_defense_max = 3
	before = target.current_hp
	await _pump()
	check(target.current_hp == before-7,"source death and withdrawal retain stronger ten damage, using current MAC three")
	check(target.credits.back().profile_id == "periodic-boundary-owner","real HP port retains historical kill credit after source node destruction")
	check(target.replace_actor_capability_source("hc.source.fixture.immunity",["hc.immune.periodic"]),"known target immunity registers through its sole capability set")
	clock.advance_simulation(1.0); before = target.current_hp; await _pump()
	check(target.current_hp == before,"current immunity suppresses periodic HP write without a minimum-one fallback")
	check(target.replace_actor_capability_source("hc.source.fixture.immunity",[]),"immunity source can be removed independently")
	clock.advance_simulation(1.0); before = target.current_hp; await _pump()
	check(target.current_hp == before-7,"later ticks recheck immunity and retain locked stronger raw damage")
	clock.advance_simulation(1.0); await _pump()
	check(runtime.metrics().ticks == 5 and runtime.active_count() == 0 and visual.node_count() == 0,"refreshed lifetime includes final phase tick then stops the same cue")
	check(visual.events[0].kind == "start" and visual.events[1].kind == "refresh" and visual.events.back().kind == "stop","presentation lifecycle is explicit start refresh stop")
	var headless_view := Presentation.new(); headless_view.configure(world,false)
	runtime.configure(world,clock,combat,headless_view)
	await _submit("boundaries:missing-cue",100)
	check(runtime.active_count() == 1 and headless_view.node_count() == 0 and int(runtime.metrics().optional_cue_missing) == 1,"declared optional missing presentation does not reject damage state")
	clock.advance_simulation(1.0); before = target.current_hp; await _pump()
	check(target.current_hp == before-2,"missing presentation retains actual damage timing and current defense")
	_zone_generation += 1; runtime.pump()
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and runtime.pending_count() == 0,"world replacement invalidates all mutation handles and drains old queues")
	check(runtime.errors.is_empty(),"all boundaries execute without hidden command or lifecycle failure")
	target.queue_free(); combat.queue_free(); await get_tree().process_frame
	_finish()
func _submit(release_id: String, amount: int) -> void:
	var batch: RefCounted = Batch.create(world,release_id,"hc.skill.wizard.ice_storm",bindings,
		{"profile_id":PlayerState.active_profile_id},clock.simulation_usec()).batch
	batch.begin_base_scope()
	var current_source: Node2D = source if is_instance_valid(source) else null
	target.take_damage(amount,current_source,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope(); check(runtime.submit_batch(batch),"confirmed base receipt "+release_id)
	await _pump()
func _pump() -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded queues terminate")
func _finish() -> void:
	if not proof.write_receipt("periodic_effect_boundaries_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_PERIODIC_BOUNDARIES_PASS" if errors.is_empty() else "FRAMEWORK_PERIODIC_BOUNDARIES_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
