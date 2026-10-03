extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const SKILL := "hc.skill.wizard.ice_storm"
var _zone_generation := 1
var current_map_id := 910001
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var source: CharacterBody2D
var combat: Node
var release_sequence := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)

func module() -> Dictionary:
	return {"schema_version":1,"module_id":"hc.validation.lifesteal","module_version":1,"core_api_version":1,
		"requires":[],"conflicts":[],"capabilities":["combat.post_hit","combat.heal"],"handlers":["hc.lifesteal.v1"],
		"resource_dependencies":[],"cost":{"commands_per_event":1,"states_per_target":0},"default_enabled":false,
		"scope":"world","activation_boundary":"world_ready","tests":["tests/framework/feature_lifesteal_runtime_test.tscn"],
		"mechanics":[{"mechanic_id":"hc.validation.lifesteal.ice_storm","kind":"trigger","tags":["hc.numeric"],
			"event":"damage_committed","skill_id":SKILL,"handler_id":"hc.lifesteal.v1","source_classes":["direct"],
			"dedup":"per_target_per_release","lifecycle":"immediate","config":{"fraction":0.25}}]}

func contribution(index: int = 0) -> Dictionary:
	return {"mechanic_id":"hc.validation.lifesteal.ice_storm",
		"source":{"slot":"hc.slot.rule","instance_id":"hc.validation.lifesteal.source."+str(index),"mechanic_id":"hc.validation.lifesteal.ice_storm"}}

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var compiled := Compiler.compile([module()],[contribution()],Authority.build())
	check(bool(compiled.success),"trusted immediate healing handler compiles with zero persistent-state cost")
	check(FileAccess.file_exists("res://scripts/features/handlers/lifesteal_handler.gd"),"pure lifesteal handler exists")
	if not compiled.success:
		print("LIFESTEAL_COMPILER_ERRORS="+JSON.stringify(compiled.errors)); _finish(); return
	var bindings: Array = compiled.bundle.event_index["damage_committed:"+SKILL]
	var invalid := module(); invalid.capabilities.erase("combat.heal")
	check(not Compiler.compile([invalid],[contribution()],Authority.build()).success,"healing permission is mandatory")
	invalid = module(); invalid.mechanics[0].config.fraction = 1.1
	check(not Compiler.compile([invalid],[contribution()],Authority.build()).success,"fraction greater than committed loss is rejected")
	invalid = module(); invalid.mechanics[0].source_classes = ["periodic"]
	check(not Compiler.compile([invalid],[contribution()],Authority.build()).success,"periodic self-excitation is rejected")
	invalid = module(); invalid.mechanics[0].cue_id = "hc.cue.ignite.v1"
	check(not Compiler.compile([invalid],[contribution()],Authority.build()).success,"an instant healing handler cannot borrow an unrelated periodic cue")
	invalid = module(); invalid.cost.commands_per_event = 0
	check(not Compiler.compile([invalid],[contribution()],Authority.build()).success,"instant command capacity must be declared")
	world = World.new(); world.configure(self,PlayerState)
	clock = Clock.new(); clock.configure(self)
	combat = Combat.new(); add_child(combat)
	source = Player.new(); add_child(source); source.set_physics_process(false)
	source.max_hp = 100; source.current_hp = 50
	check(source.begin_combat_transition("lifesteal_fixture_start") and source.finish_combat_transition("lifesteal_fixture_start"),
		"real player transition establishes the source combat life before damage")
	runtime = Runtime.new(); check(runtime.configure(world,clock,combat),"runtime uses the existing combat mutation port")
	runtime.require_reservations = true
	await _case(bindings,1000,100,50,75,"direct","")
	await _case(bindings,20,100,50,55,"lethal","")
	await _case(bindings,20,100,50,55,"removed lethal target", "remove_target")
	await _case(bindings,1000,100,95,100,"full HP clamp", "")
	await _case(bindings,1000,100,0,0,"dead source", "")
	await _case(bindings,1000,100,50,50,"changed source life", "change_life")
	await _case(bindings,1000,100,50,50,"changed world", "change_world")
	var many: Array = []
	for index in range(17): many.append(contribution(index))
	var instant := Compiler.compile([module()],many,Authority.build())
	check(instant.success,"seventeen distinct instant sources compile")
	if instant.success:
		var ticket: RefCounted = runtime.reserve_action(SKILL,instant.bundle.event_index["damage_committed:"+SKILL],1)
		check(ticket != null,"instant sources do not consume sixteen persistent slots per target")
		check(runtime.reservation_snapshot().states == 0 and runtime.reservation_snapshot().promised_receipts == 17,"instant capacity reserves seventeen receipts and zero states")
		if ticket != null: ticket.close()
	var mixed: Array = [contribution(0),contribution(1)]
	var paired := Compiler.compile([module()],mixed,Authority.build())
	check(paired.success,"two distinct healing subscriptions are retained")
	if paired.success:
		source.stats_changed.connect(_retire_during_heal,CONNECT_ONE_SHOT)
		await _case(paired.bundle.event_index["damage_committed:"+SKILL],1000,100,50,75,"synchronous source notification retires runtime", "")
		runtime.require_reservations = false
		source.stats_changed.connect(_retire_during_heal,CONNECT_ONE_SHOT)
		await _case(paired.bundle.event_index["damage_committed:"+SKILL],1000,100,50,75,"unticketed notification retires the same runtime", "unticketed")
		runtime.require_reservations = true
	check(runtime.errors.is_empty(),"no late reservation access, unknown command or hidden capacity failure")
	runtime.clear(); source.queue_free(); combat.queue_free()
	await get_tree().process_frame
	_finish()

func _retire_during_heal(_hp: int, _max_hp: int) -> void:
	runtime.clear()

func _case(bindings: Array, hp: int, damage: int, before: int, expected: int, label: String, action: String) -> void:
	runtime.clear(); source.current_hp = before
	var target := Enemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = hp; target.current_hp = hp
	release_sequence += 1
	var id := "lifesteal:"+str(release_sequence)
	var ticket: RefCounted = null if action == "unticketed" else runtime.reserve_action(SKILL,bindings,1,id)
	check(ticket != null or action == "unticketed",label+": declared producer admission remains valid")
	if ticket == null and action != "unticketed": target.queue_free(); await get_tree().process_frame; return
	var created := Batch.create(world,id,SKILL,bindings,{},0,ticket)
	check(created.success,label+": admitted real batch owns the ticket")
	if not created.success:
		if ticket != null: ticket.close()
		target.queue_free(); await get_tree().process_frame; return
	var batch: RefCounted = created.batch
	batch.begin_base_scope()
	var rng_before: int = source._rng.state
	target.take_damage(damage,source,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	check(source.current_hp == before,label+": no healing before base release completes")
	batch.finish_base_scope()
	check(runtime.submit_batch(batch) and not runtime.submit_batch(batch),label+": batch is accepted exactly once")
	if action == "remove_target": target.queue_free(); await get_tree().process_frame
	if action == "change_life":
		check(source.begin_combat_transition("lifesteal_fixture_next_life") and source.finish_combat_transition("lifesteal_fixture_next_life"),
			"real transition invalidates the previously captured source life")
	if action == "change_world": _zone_generation += 1
	for iteration in range(120):
		runtime.pump()
		if not runtime.has_work(): break
		await get_tree().process_frame
	print("LIFESTEAL_CASE="+JSON.stringify({"label":label,"actual_hp":source.current_hp,"expected_hp":expected,
		"source_epoch":source.combat_epoch,"source_max_hp":source.max_hp,"fact":batch.facts(),"metrics":runtime.metrics()}))
	check(source.current_hp == expected,label+": actual committed loss restores only the valid source")
	check(source._rng.state == rng_before,label+": old combat RNG remains unchanged")
	check(runtime.active_count() == 0 and runtime.pending_count() == 0 and runtime.reservation_snapshot().actions == 0,label+": instant work and one-shot producer fully retire")
	if is_instance_valid(target) and not target.is_queued_for_deletion(): target.queue_free()
	await get_tree().process_frame

func _finish() -> void:
	if not proof.write_receipt("feature_lifesteal_runtime_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_LIFESTEAL_PASS" if errors.is_empty() else "FRAMEWORK_LIFESTEAL_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
