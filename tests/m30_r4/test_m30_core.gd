extends Node

# Run ONLY via the project's isolated headless runner. This uses lightweight
# EnemyActor-derived fixtures, not a real map/performance/Android substitute.
const Phase := preload("res://scripts/monster_ai_package/m30/walk_phase.gd")
const Token := preload("res://scripts/monster_ai_package/m30/context_token.gd")
const Queue := preload("res://scripts/monster_ai_package/m30/summon_queue.gd")
var failures: int = 0
var checks: int = 0

class DummyEnemy:
	extends EnemyActor
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

class DummyHost:
	extends Node
	var current_map_id: int = 4
	var _zone_generation: int = 1
	var _active_enemy_cache: Dictionary = {}
	var _map_transition_in_progress: bool = false
	var _world_bootstrap_in_progress: bool = false
	var blocked: bool = true
	var spawn_failure: bool = false
	var births: int = 0
	var probes: int = 0
	var children_born: Array[EnemyActor] = []
	func _hc_m30_probe_landing(_origin: Vector2) -> Vector2:
		probes += 1
		return Vector2.INF if blocked else Vector2(float(probes), 0.0)
	func _hc_m30_resolve_monster(raw_id: Variant) -> Dictionary:
		return {"monster_id": int(raw_id)} if int(raw_id) > 0 else {}
	func _hc_m30_materialize(_monster: Dictionary, point: Vector2, context: Dictionary) -> EnemyActor:
		if spawn_failure:
			return null
		var child: DummyEnemy = DummyEnemy.new()
		child.current_hp = 1
		child.runtime_map_id = current_map_id
		child.set_meta("zone_generation", _zone_generation)
		child.set_meta("summoner_spawn_slot", str(context["summoner_spawn_slot"]))
		child.position = point
		add_child(child)
		_active_enemy_cache[child.get_instance_id()] = child
		children_born.append(child)
		births += 1
		return child

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("M30 FAIL: " + label)

func _fixture() -> Array:
	var host: DummyHost = DummyHost.new()
	add_child(host)
	var source: DummyEnemy = _source(host, "slot:A")
	var queue: HCM30SummonQueue = Queue.new()
	queue.configure(host)
	host.add_child(queue)
	queue.set_physics_process(false) # deterministic manual pump once per real tick
	return [host, source, queue]

func _source(host: DummyHost, slot: String) -> DummyEnemy:
	var source: DummyEnemy = DummyEnemy.new()
	source.current_hp = 1
	source.runtime_map_id = host.current_map_id
	source.summon_rule = {"enabled": true}
	source.set_meta("zone_generation", host._zone_generation)
	source.set_meta("hc_combat_life_epoch", 1)
	source.set_meta("spawn_slot_id", slot)
	host.add_child(source)
	return source

func _drain(queue: HCM30SummonQueue, maximum_ticks: int = 300) -> void:
	queue.set_physics_process(false)
	for _index: int in range(maximum_ticks):
		if int(queue.snapshot()["pending_batches"]) == 0:
			return
		await get_tree().physics_frame
		queue.pump()
	check(false, "queue did not drain within bounded fixture ticks")

func _run() -> void:
	var gait: HCM30WalkPhase = Phase.new()
	gait.accept_distance(0.5, 10)
	check(is_equal_approx(gait.phase, 0.5), "half GU advances half cycle")
	check(gait.frame_index(6) == 3, "six-frame atlas selects half-cycle frame")
	for _read: int in range(120):
		gait.frame_index(6)
	check(is_equal_approx(gait.phase, 0.5), "render sampling never advances phase")
	gait.accept_distance(0.0, 11)
	gait.accept_distance(-1.0, 11)
	gait.accept_distance(INF, 11)
	check(is_equal_approx(gait.total_ground_distance_gu, 0.5), "invalid/zero movement cannot advance gait")
	check(not gait.moving_on(11), "no walk-in-place when physics does not move")
	gait.interrupt_pose()
	check(not gait.moving_on(10) and is_equal_approx(gait.phase, 0.5), "attack overrides pose without resetting phase")
	gait.accept_distance(0.25, 12)
	check(is_equal_approx(gait.phase, 0.75), "next short step continues prior foot phase")
	var calibrated: HCM30WalkPhase = Phase.new()
	calibrated.configure_cycle(2.0 * 6.0 / 8.0)
	calibrated.accept_distance(2.0 / 8.0, 1)
	check(calibrated.frame_index(6) == 1, "nominal full speed preserves original 8 FPS")
	check(is_equal_approx(Phase.attack_clip_seconds(0.46, 1.55, 0.0), 0.62), "zero-delay impact retains a readable attack pose")
	check(is_equal_approx(Phase.attack_clip_seconds(0.46, 0.4, 0.0), 0.24), "fast attack leaves a movement window without changing cooldown")
	check(is_equal_approx(Phase.attack_clip_seconds(0.46, 0.4, 0.7), 0.7), "impact delay cannot be truncated by presentation")
	check(not Phase.attack_movement_locked(0.0, 0.16), "pose lock cannot block next ready attack")
	var context: Dictionary = {"blocked_cells": {Vector2i(1, 2): true}}
	var clone: Dictionary = context.duplicate(true)
	var token: int = Token.token(context)
	check(token == Token.token(context), "same dictionary identity reuses token")
	check(token != Token.token(clone), "equal-content different identity cannot alias")
	for index: int in range(80):
		Token.token({"index": index})
	check(Token.retained_count() <= 64, "registry bounded")
	check(Token.token(context) != token, "evicted identity never reuses an old token")

	var fixture: Array = _fixture()
	var host: DummyHost = fixture[0]
	var source: DummyEnemy = fixture[1]
	var queue: HCM30SummonQueue = fixture[2]
	queue.enqueue(source, [1], 5, 5)
	await _drain(queue)
	var snap: Dictionary = queue.snapshot()
	check(host.probes == 480, "five failed children retain 96 attempts each")
	check(int(snap["landing_exhausted"]) == 5, "each exhausted child is accounted once")
	check(int(snap["max_probes_in_tick"]) <= 8, "global probe budget")
	check((snap["reserved_by_slot"] as Dictionary).is_empty(), "failure releases all reservations")
	host.queue_free()
	await get_tree().process_frame

	fixture = _fixture()
	host = fixture[0]
	source = fixture[1]
	queue = fixture[2]
	host.blocked = false
	queue.enqueue(source, [1], 2, 2)
	queue.enqueue(source, [1], 5, 2)
	await _drain(queue)
	check(host.births == 2, "queued reservations prevent cap overflow")
	check(int(queue.snapshot()["max_materializations_in_tick"]) <= 1, "one construction attempt per physics tick")
	source.current_hp = 0
	var second_life: DummyEnemy = _source(host, "slot:A")
	queue.enqueue(second_life, [1], 5, 2)
	check(int(queue.snapshot()["pending_batches"]) == 0, "previous-life survivors count for respawned mother")
	check(is_instance_valid(host.children_born[0]), "mother death does not delete living children")
	host.children_born[0].current_hp = 0
	queue.enqueue(second_life, [1], 5, 2)
	await _drain(queue)
	check(host.births == 3, "dead child frees exactly one live cap slot")
	host.queue_free()
	await get_tree().process_frame

	fixture = _fixture()
	host = fixture[0]
	source = fixture[1]
	queue = fixture[2]
	source.set_meta("m30_summon_release_serial", 1)
	queue.enqueue(source, [1], 3, 10)
	queue.enqueue(source, [1], 3, 10)
	check(int(queue.snapshot()["duplicate_release"]) == 1, "reentrant duplicate release deduplicates")
	source.current_hp = 0
	await _drain(queue)
	check(host.births == 0 and (queue.snapshot()["reserved_by_slot"] as Dictionary).is_empty(), "dead mother cancels pending births")
	source.current_hp = 1
	source.set_meta("m30_summon_release_serial", 2)
	queue.enqueue(source, [1], 3, 10)
	host._zone_generation += 1
	await get_tree().physics_frame
	queue.pump()
	check(int(queue.snapshot()["pending_batches"]) == 0, "world generation invalidates queued births")
	host.queue_free()
	await get_tree().process_frame

	fixture = _fixture()
	host = fixture[0]
	source = fixture[1]
	queue = fixture[2]
	host.blocked = false
	host.spawn_failure = true
	queue.enqueue(source, [1], 3, 3)
	await _drain(queue)
	check(int(queue.snapshot()["spawn_failed"]) == 3, "construction failure is terminal for each requested child")
	check(int(queue.snapshot()["max_materializations_in_tick"]) <= 1, "failed construction also consumes global budget")
	check((queue.snapshot()["reserved_by_slot"] as Dictionary).is_empty(), "construction failure releases reservations")
	host.queue_free()
	await get_tree().process_frame
	print("HC_M30_CORE_PASS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
