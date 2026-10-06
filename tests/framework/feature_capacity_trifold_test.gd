extends Node
## S2 capacity trifold proof (fixed baseline 272430b36+, ruling 2026-10-05 in force).
## One real runtime, three positive proofs on the SAME live queues:
##   1. SIMULTANEOUS RESIDENCY: sixteen explicitly registered independent layers
##      of the accepted species hold one head per target each (480 heads) while
##      the seventeenth layer is refused BEFORE any action happens.
##   2. CUMULATIVE LEGAL WORK: repeated retired rounds keep admitting fresh work
##      after every full drain (retire tail bookkeeping returns every slot), so
##      accumulated accepted work exceeds any single-round bound without leaks.
##   3. SERVICE TIMELINESS: the full residency delivers every configured due
##      tick inside its own period (bounded lateness), then retires to zero.
## This is a structural capacity proof, not a performance benchmark: no frame or
## wall-clock acceptance is claimed (see CLOSEOUT_LEDGER row 6 scope note).
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Player := preload("res://scripts/player.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Presentation := preload("res://scripts/features/presentation/presentation_port.gd")
const SKILL := "hc.skill.wizard.ice_storm"
const RECEIVERS := 30
const LAYERS := 16
var _zone_generation := 1
var current_map_id := 910001
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var targets: Array[EnemyActor] = []
var source: PlayerCharacter

class ObservedEnemy extends Enemy:
	func take_feature_periodic_damage(_amount: int, _attacker: Node2D, _credit: Dictionary, _receipt: Dictionary) -> void:
		pass
func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1; proof.record(value, label)
	if not value: errors.append(label)
func _ground_to_screen(value: Vector2) -> Vector2: return value*10.0
func _screen_to_ground(value: Vector2) -> Vector2: return value/10.0

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "capacity-trifold"
	world = World.new(); world.configure(self, PlayerState)
	clock = Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	for index in RECEIVERS:
		var actor: ObservedEnemy = ObservedEnemy.new()
		actor.setup(GameData.get_monster_by_id(19), null); add_child(actor)
		actor.set_physics_process(false)
		actor.configure_runtime_map_projection(current_map_id, _ground_to_screen, _screen_to_ground)
		actor.set_combat_position(_ground_to_screen(Vector2(1.0+float(index%6)*0.72, 12.2+float(index/6)*0.64)), &"capacity_trifold_unit_position")
		actor.max_hp = 100000; actor.current_hp = 100000
		actor.direct_spell_anti_magic_points = 0
		actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
		actor.direct_spell_stats_valid = true
		targets.append(actor)
	source = Player.new(); add_child(source); source.set_physics_process(false)
	var visual := Presentation.new(); visual.configure(world, true)
	runtime = Runtime.new(); runtime.configure(world, clock, combat, visual)
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "default-off verification module enabled through the real service")
	var base: Array = PlayerState.feature_bundle().event_index.get("damage_committed:"+SKILL, [])
	check(base.size() == 1, "one real compiled ignite binding feeds every layer copy")
	if base.is_empty(): _finish(); return
	# --- Proof 1: simultaneous residency + pre-action refusal of the next layer.
	var layered: Array = _layered_bindings(base, LAYERS)
	check(layered.size() == LAYERS, "sixteen legal layer bindings compile through the same handler species")
	var ticket: RefCounted = runtime.reserve_action(SKILL, layered, RECEIVERS, "trifold:resident")
	check(ticket != null and runtime.last_admission_reason == "", "sixteen layers x thirty receivers reserve simultaneously")
	if ticket == null: _finish(); return
	var resident_states := LAYERS*RECEIVERS
	check(int(runtime.reservation_snapshot().states) == resident_states and int(runtime.reservation_snapshot().facts) == RECEIVERS,
		"the accepted reservation owns exactly its promised state and fact space")
	var over: Array = _layered_bindings(base, LAYERS+1)
	var refused: RefCounted = runtime.reserve_action(SKILL, over, RECEIVERS, "trifold:over")
	check(refused == null and runtime.last_admission_reason == "feature_action_target_capacity",
		"the seventeenth layer is refused through the per-target source bound before any action happens")
	var untouched := true
	for actor: EnemyActor in targets: untouched = untouched and actor.current_hp == 100000
	check(untouched and int(runtime.reservation_snapshot().states) == resident_states,
		"the refused action leaves every target HP and the accepted reservation untouched")
	var created: Dictionary = Batch.create(world, "trifold:resident", SKILL, layered, {"profile_id":PlayerState.active_profile_id}, 0, ticket)
	check(bool(created.success), "the accepted reservation accepts its exact layered batch")
	if not bool(created.success): _finish(); return
	var batch: RefCounted = created.batch; batch.begin_base_scope()
	for actor: EnemyActor in targets:
		actor.take_damage(100, source, {"feature_damage_batch":batch, "source_class":"direct", "damage_channel":"magic_defense"})
	batch.finish_base_scope()
	check(batch.facts().size() == RECEIVERS, "thirty real HP writes were captured before the one-shot transfer")
	check(runtime.submit_batch(batch), "the layered batch transfers through the accepted reservation")
	check(runtime.pending_count() == RECEIVERS, "thirty real HP writes enter the queue once each")
	check(ContentLayers.set_feature_module_enabled("hc.ignite", false), "source withdrawal keeps accepted states and restores default-off")
	while runtime.pending_count() > 0: runtime._dispatch_one_fact()
	check(runtime.active_count() == resident_states and runtime.heap_count() == resident_states,
		"all 480 layered heads hold simultaneously with one heap node each")
	check(int(runtime.metrics().started) == resident_states and int(runtime.metrics().replaced) == 0,
		"every layer head started exactly once and none was replaced inside one release")
	# --- Proof 3: service timeliness of the full residency.
	for tick_index in range(4):
		check(clock.advance_simulation(1.0), "simulation reaches resident tick second "+str(tick_index+1))
		await _pump()
	check(int(runtime.metrics().ticks) == resident_states*4 and runtime.active_count() == 0 and runtime.heap_count() == 0,
		"the full residency delivers exactly 1920 due ticks and retires every head at its own full duration")
	check(int(runtime.metrics().tick_delivery_count) == resident_states*4
		and int(runtime.metrics().maximum_tick_delivery_lateness_usec) < 1000000,
		"every due tick is served inside its own one-second period without hidden truncation")
	var drained: bool = _tail_drained()
	check(drained and visual.node_count() == 0 and runtime._batches.is_empty(),
		"retire tail bookkeeping returns every reservation, fact, state, receipt-promise, child and cue slot")
	# --- Proof 2: cumulative legal work across retired rounds.
	var single: Array = _layered_bindings(base, 1)
	var rounds := 20
	for round_index in range(rounds):
		var round_ticket: RefCounted = runtime.reserve_action(SKILL, single, RECEIVERS, "trifold:round:"+str(round_index))
		if round_ticket == null:
			check(false, "round "+str(round_index)+" keeps full admission rights after every prior retire: "+runtime.last_admission_reason)
			break
		var round_batch: Dictionary = Batch.create(world, "trifold:round:"+str(round_index), SKILL, single, {"profile_id":PlayerState.active_profile_id}, 0, round_ticket)
		check(bool(round_batch.success), "round "+str(round_index)+" accepts its batch")
		if not bool(round_batch.success): break
		var rb: RefCounted = round_batch.batch; rb.begin_base_scope()
		for actor: EnemyActor in targets:
			actor.take_damage(10, source, {"feature_damage_batch":rb, "source_class":"direct", "damage_channel":"magic_defense"})
		rb.finish_base_scope()
		check(runtime.submit_batch(rb), "round "+str(round_index)+" transfers its facts")
		round_ticket.close()
		while runtime.pending_count() > 0: runtime._dispatch_one_fact()
		check(_tail_drained(), "round "+str(round_index)+" retires its whole producer tail before the next round")
	check(int(runtime.metrics().admitted_facts) == RECEIVERS*(1+rounds),
		"cumulative accepted work reaches "+str(RECEIVERS*(1+rounds))+" facts, many times any single-round bound")
	check(int(runtime.reservation_snapshot().receipts) == 0 and int(runtime.metrics().peak_receipts) == resident_states,
		"dedup receipt residency stays bounded by active work and returns to zero at the tail")
	check(int(runtime.metrics().retired_receipts) == resident_states+RECEIVERS*rounds,
		"the full legal receipt history retires through the write boundary")
	check(int(runtime.metrics().replaced) == (rounds-1)*RECEIVERS and int(runtime.metrics().started) == resident_states+RECEIVERS,
		"repeated single-layer rounds converge onto the same species head through atomic replacement")
	check(runtime.errors.is_empty(), "all three proofs complete without hidden capacity or identity errors")
	runtime.clear()
	targets.map(func(actor: Node) -> void: actor.queue_free()); combat.queue_free(); source.queue_free()
	await get_tree().process_frame
	_finish()
func _layered_bindings(base: Array, count: int) -> Array:
	var out: Array = []
	for index in count:
		var binding: Dictionary = base[0].duplicate(true)
		binding.source.instance_id = "capacity:layer:"+str(index)
		binding.handle = Compiler.source_handle(binding.source)
		binding.definition.config["status_layer"] = "capacity.layer."+str(index)
		out.append(binding)
	return out
func _tail_drained() -> bool:
	# Dedup receipts legitimately accumulate the full legal history (their own
	# bound is separate); every RESIDENCY slot must return to zero at the tail.
	var tail: Dictionary = runtime.reservation_snapshot()
	return int(tail.actions) == 0 and int(tail.facts) == 0 and int(tail.states) == 0 \
		and int(tail.promised_receipts) == 0 and int(tail.children) == 0 and int(tail.promised_children) == 0
func _pump() -> void:
	for iteration in range(400):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false, "bounded queues terminate")
func _finish() -> void:
	if not proof.write_receipt("feature_capacity_trifold_test", checks, errors.size()): errors.append("receipt")
	print(("CAPACITY_TRIFOLD_PASS" if errors.is_empty() else "CAPACITY_TRIFOLD_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
