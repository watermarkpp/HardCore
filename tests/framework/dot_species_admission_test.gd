extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Enemy := preload("res://scripts/enemy.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var failures: Array[String] = []
var module: Dictionary
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _bindings(source: String, layer := "") -> Array:
	var candidate: Dictionary = module.duplicate(true)
	for definition: Dictionary in candidate.mechanics:
		if definition.handler_id == "hc.ignite.v1":
			if layer.is_empty(): definition.config.erase("status_layer")
			else: definition.config["status_layer"] = layer
	var catalog := Compiler.compile_catalog([candidate], Authority.build())
	if not catalog.success: check(false,"declared compiler input: " + str(catalog.errors)); return []
	var id := "hc.ignite.ice_storm"
	var compiled := Compiler.compile_loadout(catalog.catalog,
		[{"source":{"slot":"hc.slot.rule","instance_id":source,"mechanic_id":id},"mechanic_id":id}], Authority.build())
	if not compiled.success: check(false,"declared loadout: " + str(compiled.errors)); return []
	return compiled.bundle.event_index.get("damage_committed:hc.skill.wizard.ice_storm", [])

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "original default-off module enables explicitly")
	module = ContentLayers.feature_configuration().catalog.modules["hc.ignite"]
	world = World.new(); world.configure(self, PlayerState)
	clock = Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	runtime = Runtime.new(); check(runtime.configure(world,clock,combat),"original world and consumer")
	runtime.require_reservations = true
	var target := Enemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp=10000; target.current_hp=10000
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0
	var tickets: Array = []; var prepared: Array = []
	# Each catalog has one legal binding. Concurrent accepted root promises are
	# not twenty independent layers: all replace the same certified DOT species.
	for index in range(20):
		var bindings := _bindings("ordinary:" + str(index))
		var ticket: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm", bindings, 1, "ordinary:" + str(index))
		check(ticket != null, "same ordinary species has room despite distinct source root " + str(index))
		if ticket != null: tickets.append(ticket); prepared.append(bindings)
	check(target.current_hp==10000 and runtime.pending_count()==0, "admission alone performs no HP write or synthetic occupancy")
	for index in tickets.size():
		var release := "ordinary:" + str(index)
		var made := Batch.create(world,release,"hc.skill.wizard.ice_storm",prepared[index],{},clock.simulation_usec(),tickets[index])
		check(made.success, "accepted source still claims exactly once " + str(index))
		if not made.success: tickets[index].close(); continue
		var batch: RefCounted = made.batch
		batch.begin_base_scope()
		target.take_damage(20,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
		check(batch.finish_base_scope() and runtime.submit_batch(batch), "whole real accepted fact transfers " + str(index))
		batch.finish_production(); tickets[index].close()
	await _pump()
	check(tickets.size()==20 and target.current_hp==9600 and runtime.active_count()==1, "twenty accepted real base facts reduce to one ordinary state without silent loss")
	clock.advance_simulation(4.0); await _pump()
	check(target.current_hp==9596 and runtime.active_count()==0 and runtime.reservation_snapshot().actions==0, "last replacement delivers its complete ticks then retires")

	# Explicit independent layers are a different local-slot commitment.
	var layered: Array = []
	for index in range(16):
		var bindings := _bindings("layer-source:"+str(index),"hc.validation.layer.l"+str(index))
		var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,1,"layer:"+str(index))
		check(ticket!=null,"one certified independent layer reserves local slot "+str(index))
		if ticket!=null: layered.append(ticket)
	var same_layer := _bindings("another-source:same-layer","hc.validation.layer.l0")
	var replacement: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",same_layer,1,"layer:replace-existing")
	check(replacement!=null,"new source for an already committed layer does not require a seventeenth local slot")
	var too_many := _bindings("another-source:new-layer","hc.validation.layer.l16")
	var rejected: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",too_many,1,"layer:seventeenth")
	check(rejected==null and runtime.last_admission_reason=="feature_action_target_capacity", "genuinely new seventeenth layer rejects before HP")
	if rejected!=null: rejected.close()
	if replacement!=null: replacement.close()
	for ticket: RefCounted in layered: ticket.close()
	# An identical persistent source handle can carry different independently
	# certified layers across accepted revisions. Count slots, not handles.
	var revised: Array = []
	for index in range(16):
		var bindings := _bindings("one-stable-source", "hc.validation.layer.r" + str(index))
		var ticket: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm", bindings, 1, "revision:" + str(index))
		check(ticket != null, "accepted revision holds its independent slot " + str(index))
		if ticket != null: revised.append(ticket)
	var overflow := _bindings("one-stable-source", "hc.validation.layer.r16")
	var illegal: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm", overflow, 1, "revision:overflow")
	check(illegal == null and runtime.last_admission_reason == "feature_action_target_capacity", "same source identity cannot hide a seventeenth promised independent layer")
	if illegal != null: illegal.close()
	for ticket: RefCounted in revised: ticket.close()
	check(target.current_hp==9596 and runtime.reservation_snapshot().actions==0 and runtime.errors.is_empty(), "local permission accounting leaves HP and all producer capacity intact")
	runtime.clear(); target.queue_free(); combat.queue_free()
	await get_tree().process_frame
	var written:=proof.write_receipt("dot_species_admission_test",proof.records.size(),failures.size())
	print("DOT_SPECIES_ADMISSION_","PASS" if written and failures.is_empty() else "FAIL"," checks=",proof.records.size()," failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)

func _pump() -> void:
	for iteration in range(240):
		runtime.pump()
		if runtime.pending_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded original queue consumer drains")
