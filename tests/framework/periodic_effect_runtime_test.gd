extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var _zone_generation := 1
var current_map_id := 910001
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()
func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var path := "res://scripts/features/runtime/effect_runtime.gd"
	check(FileAccess.file_exists(path), "periodic runtime exists behind the production damage port")
	if not FileAccess.file_exists(path):
		_finish(); return
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var world := World.new(); world.configure(self, PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	var target := Enemy.new(); target.setup(GameData.get_monster_by_id(19), null); add_child(target)
	target.set_physics_process(false)
	target.max_hp = 1000; target.current_hp = 1000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "actual default-off declared module can be enabled")
	var bindings: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm", [])
	check(bindings.size() == 1, "production qualification compiles one declared source")
	var runtime_type: Variant = load(path)
	var runtime: RefCounted = runtime_type.new()
	runtime.configure(world, clock, combat)
	var batch: RefCounted = Batch.create(world,"periodic:base:1","hc.skill.wizard.ice_storm",bindings,{"profile_id":PlayerState.active_profile_id}).batch
	batch.begin_base_scope()
	target.take_damage(100, null, {"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope()
	check(runtime.submit_batch(batch) and not runtime.submit_batch(batch), "post-base receipt is accepted exactly once")
	await _drain_commands(runtime)
	check(runtime.active_count() == 1 and runtime.heap_count() == 1 and target.current_hp == 900, "one active effect has one due node and no immediate tick")
	check(ContentLayers.set_feature_module_enabled("hc.ignite", false), "source withdrawal uses content owner")
	var actor_rng: int = target._rng.state
	var attack_deadline: float = target._attack_timer
	for index in range(4):
		clock.advance_simulation(1.0)
		await _pump_due(runtime)
		check(target.current_hp == 900 - 5 * (index + 1), "accepted 100 actual loss produces five damage at second " + str(index+1))
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and runtime.metrics().ticks == 4, "final due tick executes before expiry and queues drain")
	check(target._rng.state == actor_rng and target._attack_timer == attack_deadline, "real actor RNG and direct-struck attack deadline remain unchanged across periodic ticks")
	check(runtime.errors.is_empty(), "closed handler, command and runtime report no hidden failure")
	target.queue_free(); combat.queue_free()
	await get_tree().process_frame
	_finish()
func _drain_commands(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: return
		await get_tree().process_frame
	check(false,"command queue terminates")
func _pump_due(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"due queue terminates")
func _finish() -> void:
	if not proof.write_receipt("periodic_effect_runtime_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_PERIODIC_EFFECT_PASS" if errors.is_empty() else "FRAMEWORK_PERIODIC_EFFECT_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
