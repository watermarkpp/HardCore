extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Audio := preload("res://scripts/audio_runtime_service.gd")
const FIRE := "res://assets/audio/sfx/client/137__M26-3.wav"
const ICE := "res://assets/audio/sfx/client/10332__M33-3.wav"
var _zone_generation := 1
var current_map_id := 910001
var _audio_runtime_service: Node
var proof := Proof.new()
var failures: Array[String] = []
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var target: EnemyActor
var played: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _binding(catalog: Dictionary, mechanic: String) -> Array:
	var source := {"slot":"hc.slot.rule", "instance_id":"cue-replacement:" + mechanic, "mechanic_id":mechanic}
	var compiled := Compiler.compile_loadout(catalog, [{"source":source, "mechanic_id":mechanic}], Authority.build())
	check(compiled.success, "real immutable compiler accepts registered mechanic " + mechanic)
	return compiled.bundle.event_index.values()[0] if compiled.success else []

func _submit(id: String, skill: String, bindings: Array, resources: RefCounted) -> bool:
	var ticket: RefCounted = runtime.reserve_action(skill, bindings, 1, id)
	if ticket == null: return false
	var made := Batch.create(world, id, skill, bindings, {"profile_id":PlayerState.active_profile_id,"marker":id}, clock.simulation_usec(), ticket, resources)
	if not made.success: ticket.close(); return false
	var batch: RefCounted = made.batch
	if not batch.begin_base_scope(): batch.finish_production(); ticket.close(); return false
	target.take_damage(100, null, {"feature_damage_batch":batch, "source_class":"direct", "damage_channel":"magic_defense"})
	var success: bool = batch.finish_base_scope() and runtime.submit_batch(batch)
	batch.finish_production(); ticket.close()
	return success

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	check(await ContentLayers.reload_feature_catalog_async("res://assets/data/features/validation/resource_natural_registry.json"), "actual async preparation owns both original primary sounds")
	if not failures.is_empty(): _finish(); return
	var configuration := ContentLayers.feature_configuration()
	var plan := Lease.requirements(configuration.catalog, configuration.enabled_modules)
	var resources := {FIRE:configuration.resource_lease.resource_at(FIRE), ICE:configuration.resource_lease.resource_at(ICE)}
	var first: RefCounted = Lease.issue(plan, resources, ContentLayers._feature_resource_service, {})
	var second: RefCounted = Lease.issue(plan, resources, ContentLayers._feature_resource_service, {})
	var third: RefCounted = Lease.issue(plan, resources, ContentLayers._feature_resource_service, {})
	check(first != null and second != null and third != null and not is_same(first, second), "three distinct legitimate leases retain real prepared streams")
	var fourth: RefCounted = Lease.issue(plan, resources, ContentLayers._feature_resource_service, {})
	var first_weak: WeakRef = weakref(first)
	var second_weak: WeakRef = weakref(second)
	var fire := _binding(configuration.catalog, "hc.ignite.fire_sword")
	var ice := _binding(configuration.catalog, "hc.ignite.ice_storm")
	if not failures.is_empty(): _finish(); return
	world = World.new(); world.configure(self, PlayerState)
	clock = Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	_audio_runtime_service = Audio.new(); add_child(_audio_runtime_service)
	_audio_runtime_service.event_started.connect(func(event: Dictionary) -> void:
		if event.context.has("feature_effect_handle"): played.append(event))
	target = Enemy.new(); target.setup(GameData.get_monster_by_id(19), null); add_child(target)
	target.set_physics_process(false); target.max_hp = 1000; target.current_hp = 1000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	runtime = Runtime.new(); check(runtime.configure(world, clock, combat), "one runtime owns real HP and audio")
	runtime.require_reservations = true
	check(_submit("cue:fire:A", "hc.skill.warrior.fire_sword", fire, first), "first real accepted base batch transfers")
	await _pump()
	var port: RefCounted = runtime.presentation()
	check(runtime.active_count() == 1 and port.node_count() == 1 and played.size() == 1, "first required cue and native onset actually exist")
	var handle: String = runtime._states.keys()[0]
	var initial_cue: Node = port._nodes[handle].get_ref()
	check(is_same(initial_cue.resource_lease, first), "first cue owns its accepted resource lease")
	var old_request: Dictionary = played[0] if not played.is_empty() else {}
	var old_player: AudioStreamPlayer = _audio_runtime_service._event_players[int(old_request.pool_index)] if not old_request.is_empty() else null
	var hp_before: int = target.current_hp
	check(_submit("cue:ice:B", "hc.skill.wizard.ice_storm", ice, second), "different accepted cue of the same DOT species replaces through real HP")
	await _pump()
	check(runtime.active_count() == 1 and port.node_count() == 1 and is_same(initial_cue, port._nodes[handle].get_ref()), "replacement retains only one reusable procedural CanvasItem")
	check(is_same(runtime._states[handle].resource_lease, second) and is_same(initial_cue.resource_lease, second), "logical and visual owners both transfer to the new accepted lease")
	check(runtime._states[handle].command.cue_id == "hc.cue.ignite.ice_storm.v1", "new actual command owns the selected cue identity")
	check(played.size() == 2 and played.back().runtime_path == ICE, "changed cue consumes the new exact native stream once")
	check(old_player != null and not old_player.playing and old_player.stream == null, "old native onset is explicitly retired rather than inheriting its ownership")
	first = null
	await get_tree().process_frame
	check(first_weak.get_ref() == null, "replaced visual cannot pin the obsolete lease until the new DOT expires")
	check(target.current_hp == hp_before - 100 and runtime.metrics().ticks == 0, "resource handoff creates no extra HP or periodic tick")
	check(_submit("cue:ice:C", "hc.skill.wizard.ice_storm", ice, third), "same-cue later incarnation is accepted")
	await _pump()
	check(is_same(initial_cue.resource_lease, third) and port.node_count() == 1, "same-cue replacement also transfers lease without allocating retired nodes")
	check(played.size() == 2, "same cue keeps the original no-duplicate-onset presentation policy")
	second = null
	await get_tree().process_frame
	check(second_weak.get_ref() == null, "same-cue replacement drops obsolete lease ownership")
	check(_submit("cue:fire:D", "hc.skill.warrior.fire_sword", fire, fourth), "return to the original cue is a new accepted onset")
	await _pump()
	check(played.size() == 3 and played.back().runtime_path == FIRE, "same CanvasItem identity does not deduplicate a later distinct fire onset")
	check(is_same(initial_cue.resource_lease, fourth) and port.node_count() == 1, "repeated cue-kind changes keep bounded physical nodes and current ownership")
	clock.advance_simulation(4.0); await _pump()
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and port.node_count() == 0, "replacement state and cue retire on the new complete horizon")
	check(runtime.metrics().ticks == 4 and runtime.metrics().actual_loss == 20 and target.current_hp == 580, "four real base hits and four real ticks are conserved")
	check(runtime.errors.is_empty(), "no hidden resource or required-cue failure")
	runtime.clear(); target.queue_free(); combat.queue_free(); _audio_runtime_service.queue_free()
	await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(), "default source configuration restored")
	_finish()

func _pump() -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false, "original effect consumer drains available work")

func _finish() -> void:
	var written := proof.write_receipt("dot_cue_replacement_test", proof.records.size(), failures.size())
	print("DOT_CUE_REPLACEMENT_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
