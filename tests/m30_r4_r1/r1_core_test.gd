extends Node
const Phase := preload("res://scripts/monster_ai_package/m30/walk_phase.gd")
const Queue := preload("res://scripts/monster_ai_package/m30/summon_queue.gd")
var failures: int = 0
var checks: int = 0

class DummyEnemy:
	extends EnemyActor
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

class SpyVisual:
	extends MonsterVisual
	var contact_refreshes: int = 0
	func _ready() -> void:
		set_process(false)
	func _refresh_actor_ground_indicator() -> void:
		contact_refreshes += 1

class DummyHost:
	extends Node
	var current_map_id: int = 4
	var _zone_generation: int = 1
	var _active_enemy_cache: Dictionary = {}
	var _map_transition_in_progress: bool = false
	var _world_bootstrap_in_progress: bool = false
	var source: DummyEnemy
	var queue: HCM30SummonQueue
	var mode: String = ""
	var probes: int = 0
	var births: int = 0
	func _hc_m30_resolve_monster(raw: Variant) -> Dictionary:
		if mode == "die_resolve":
			source.current_hp = 0
		return {"monster_id": int(raw)}
	func _hc_m30_probe_landing(_p: Vector2) -> Vector2:
		probes += 1
		if mode == "die_probe":
			source.current_hp = 0
		elif mode == "world_probe":
			_zone_generation += 1
		elif mode == "slot_probe":
			source.set_meta("spawn_slot_id", "other_slot")
		elif mode == "reentrant_probe":
			queue.pump()
		return Vector2(1.0, 1.0)
	func _hc_m30_materialize(_m: Dictionary, p: Vector2, context: Dictionary) -> EnemyActor:
		var child: DummyEnemy = DummyEnemy.new()
		child.current_hp = 1
		child.runtime_map_id = current_map_id
		child.set_meta("zone_generation", _zone_generation)
		child.set_meta("summoner_spawn_slot", context["summoner_spawn_slot"])
		child.position = p
		add_child(child)
		_active_enemy_cache[child.get_instance_id()] = child
		queue.track_child(child)
		births += 1
		if mode == "cancel_materialize":
			mode = ""
			queue.cancel_all()
			queue.enqueue(source, [1], 1, 5)
		return child

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("M30R1_CORE: " + label)

func _fixture(mode: String) -> DummyHost:
	var host: DummyHost = DummyHost.new()
	add_child(host)
	host.mode = mode
	host.source = DummyEnemy.new()
	host.source.current_hp = 10
	host.source.runtime_map_id = 4
	host.source.set_meta("zone_generation", 1)
	host.source.set_meta("spawn_slot_id", "slot:A")
	host.source.set_meta("hc_combat_life_epoch", 1)
	host.add_child(host.source)
	host.queue = Queue.new()
	host.queue.configure(host)
	host.add_child(host.queue)
	host.queue.enqueue(host.source, [1], 1, 5)
	host.queue.set_physics_process(false)
	return host

func _run() -> void:
	var phase: HCM30WalkPhase = Phase.new()
	phase.accept_distance(0.30, 1)
	phase.configure_cycle(2.0)
	check(is_equal_approx(phase.phase, 0.30), "late stride calibration preserves phase")
	phase.accept_distance(0.20, 2)
	check(is_equal_approx(phase.phase, 0.40), "new cycle affects only future distance")
	check(Phase.action_frame_index(0.42, 0.62, 6) == 1, "action frame comes from its own timer")
	var enemy: DummyEnemy = DummyEnemy.new()
	add_child(enemy)
	var visual: SpyVisual = SpyVisual.new()
	visual.actor = enemy
	enemy.add_child(visual)
	visual.sprite = Sprite2D.new()
	visual.add_child(visual.sprite)
	visual.frame_size = Vector2i(8, 8)
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 48
	texture.height = 64
	visual.active_resources = {
		"idle": texture, "walk": texture, "attack": texture, "hit": texture, "death": texture,
		"frame_counts": {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "death": 4},
		"direction_mode": "mir2_north_first",
	}
	visual.play_attack(0.62)
	visual._advance_action_timers(0.20)
	visual._update_animation_frame(0.0)
	var frame_before: int = visual.current_frame
	var remaining_before: float = visual._attack_remaining
	var duration_before: float = visual._hc_m30_attack_duration
	visual.play_hit(0.22)
	visual._update_animation_frame(0.0)
	check(visual.current_state == "attack", "existing attack priority is unchanged")
	check(visual.current_frame == frame_before, "hit does not rewind attack frame")
	check(visual._attack_remaining == remaining_before and visual._hc_m30_attack_duration == duration_before, "hit does not retime attack")
	visual._advance_action_timers(0.10)
	visual._update_animation_frame(0.0)
	check(visual.current_frame >= frame_before, "attack progress stays monotonic after hit")
	visual.contact_refreshes = 0
	visual._apply_render_state(texture, Rect2(8, 0, 8, 8))
	check(visual.contact_refreshes == 0, "rectangle-only frame update does not recompute footprint")
	visual._apply_render_state(GradientTexture2D.new(), Rect2(8, 0, 8, 8))
	check(visual.contact_refreshes == 1, "texture transition retains footprint refresh")
	visual.position += Vector2(1.0, 0.0)
	visual._apply_render_state(visual.sprite.texture, visual.sprite.region_rect)
	check(visual.contact_refreshes == 2, "visual-origin edit retains footprint refresh")
	enemy.combat_radius_gu += 0.1
	visual._apply_render_state(visual.sprite.texture, visual.sprite.region_rect)
	check(visual.contact_refreshes == 3, "radius edit retains footprint refresh")
	enemy.queue_free()
	await get_tree().process_frame
	for mode: String in ["die_resolve", "die_probe", "world_probe", "slot_probe", "reentrant_probe", "cancel_materialize"]:
		var host: DummyHost = _fixture(mode)
		await get_tree().physics_frame
		host.queue.pump()
		host.queue.set_physics_process(false)
		var snapshot: Dictionary = host.queue.snapshot()
		if mode in ["die_resolve", "die_probe", "world_probe", "slot_probe"]:
			check(host.births == 0, mode + " rejects stale birth")
			check((snapshot["reserved_by_slot"] as Dictionary).is_empty(), mode + " releases reservation")
		elif mode == "reentrant_probe":
			check(host.births == 1 and host.probes == 1, "reentrant pump cannot duplicate birth/probe")
			check(int(snapshot["reentrant_pump_rejected"]) == 1, "reentrant pump is diagnosed")
		else:
			check(host.births == 1, "cancel during factory does not erase a committed child")
			check(int(snapshot["reserved_by_slot"].get("slot:A", 0)) == 1, "old completion cannot debit a new reservation")
			await get_tree().physics_frame
			host.queue.pump()
			check(host.births == 2 and (host.queue.snapshot()["reserved_by_slot"] as Dictionary).is_empty(), "new job drains independently")
		check(int(host.queue.snapshot()["max_materializations_in_tick"]) <= 1, mode + " retains global construction cap")
		host.queue_free()
		await get_tree().process_frame
	print("M30_R4R1_CORE_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	_run.call_deferred()
