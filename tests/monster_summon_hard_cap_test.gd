extends "res://tests/m30_r4/test_m30_core.gd"

class ReentrantHost:
	extends DummyHost
	var queue: HCM30SummonQueue
	var source: EnemyActor
	var max_owned := 0
	var cancel_before_track := false
	func _hc_m30_materialize(monster: Dictionary, point: Vector2, context: Dictionary) -> EnemyActor:
		var child := super._hc_m30_materialize(monster, point, context)
		child.monster_id = int(monster.monster_id)
		if cancel_before_track:
			cancel_before_track = false
			queue.cancel_all()
			queue.enqueue(source, [183], 100, 100)
		queue.track_child(child)
		var slot := str(context.summoner_spawn_slot)
		max_owned = maxi(max_owned, queue._active(slot) + int(queue._reserved.get(slot, 0)))
		queue.enqueue(source, [183], 100, 100)
		queue.pump()
		return child

class CancelFailedBirthHost:
	extends DummyHost
	var queue: HCM30SummonQueue
	var source: EnemyActor
	var fail_first := true
	func _hc_m30_materialize(monster: Dictionary, point: Vector2, context: Dictionary) -> EnemyActor:
		if fail_first:
			fail_first = false
			queue.cancel_all()
			queue.enqueue(source, [183], 100, 100)
			return null
		return super._hc_m30_materialize(monster, point, context)

func _run() -> void:
	PlayerState.test_mode = true
	var phantom := EnemyActor.new()
	phantom.setup(GameData.get_monster_by_id(182), null, false)
	check(phantom.summon_rule.get("monsterIds", []).size() == 1 and int(phantom.summon_rule.get("monsterIds", [0])[0]) == 183, "formal phantom actor summons exact ID183")
	check(int(phantom.summon_rule.get("maxActive", 0)) == 5, "phantom source config cap5")
	var horn := EnemyActor.new()
	horn.setup(GameData.get_monster_by_id(126), null, false)
	check(int(horn.summon_rule.get("maxActive", 0)) == 5, "horn fly source config cap5")
	phantom.free()
	horn.free()
	for monster_id in [33, 183, 241]:
		var empty_drop := EnemyActor.new()
		empty_drop.setup(GameData.get_monster_by_id(monster_id), null, false)
		check(empty_drop.monster_id == monster_id, "empty-drop monster%d accepted by formal setup" % monster_id)
		check(GameData.get_calibrated_drops(monster_id).is_empty(), "empty-drop monster keeps empty drops")
		check(empty_drop.direct_spell_stats_valid, "empty-drop actor has real combat stats")
		empty_drop.free()
	for cap in [5, 15, 30, 100]:
		var host := ReentrantHost.new()
		host.blocked = false
		add_child(host)
		host.source = _source(host, "phantom:A")
		var second := _source(host, "horn:B")
		host.queue = Queue.new()
		host.queue.configure(host)
		host.add_child(host.queue)
		for release in range(20):
			host.queue.enqueue(host.source, [183], 100, cap)
			host.queue.enqueue(second, [127], 100, cap)
		check(int(host.queue._reserved.get("phantom:A", 0)) == 5, "rapid A reservations capped at5 even configured%d" % cap)
		check(int(host.queue._reserved.get("horn:B", 0)) == 5, "independent B reservations capped at5")
		for job: Dictionary in host.queue._jobs:
			check(int(job.limit) <= 5, "queued effective limit <=5")
		await _drain(host.queue)
		check(host.queue._active("phantom:A") == 5 and host.queue._active("horn:B") == 5, "each source owns5; no global cap")
		check(host.max_owned <= 5, "materialize callback active+reserved<=5 (got%d)" % host.max_owned)
		check(host.births == 10, "no duplicate/reentrant births")
		var child := host.children_born[0]
		var slot := str(child.get_meta("summoner_spawn_slot"))
		child.current_hp = 0
		child.died.emit(child, {})
		check(host.queue._active(slot) == 4, "death frees one slot before corpse leaves tree")
		var refill_source := host.source if slot == "phantom:A" else second
		host.queue.enqueue(refill_source, [183], 100, cap)
		check(int(host.queue._reserved.get(slot, 0)) == 1, "only one replacement reserved")
		await _drain(host.queue)
		check(host.births == 11 and host.queue._active(slot) == 5, "exactly one replacement born")
		check(int(host.queue.snapshot().max_materializations_in_tick) <= 1, "construction budget unchanged")
		check(int(host.queue.snapshot().max_probes_in_tick) <= 8, "probe budget unchanged")
		host.queue_free()
		await get_tree().process_frame
	await _check_boss_summons()
	await _check_boss_legacy_defaults()
	var cancel_host := ReentrantHost.new()
	cancel_host.blocked = false
	cancel_host.cancel_before_track = true
	add_child(cancel_host)
	cancel_host.source = _source(cancel_host, "cancel:A")
	cancel_host.queue = Queue.new()
	cancel_host.queue.configure(cancel_host)
	cancel_host.add_child(cancel_host.queue)
	cancel_host.queue.enqueue(cancel_host.source, [183], 5, 100)
	await _drain(cancel_host.queue)
	check(cancel_host.max_owned <= 5, "cancel/enqueue inside child-ready before registration preserves active+reserved")
	check(cancel_host.births == 5 and cancel_host.queue._active("cancel:A") == 5, "cancelled in-flight birth cannot open a sixth slot")
	check(cancel_host.queue._reserved.is_empty(), "cancelled in-flight reservation fully transferred")
	cancel_host.queue_free()
	await get_tree().process_frame
	var failed_host := CancelFailedBirthHost.new()
	failed_host.blocked = false
	add_child(failed_host)
	failed_host.source = _source(failed_host, "failure:A")
	failed_host.queue = Queue.new()
	failed_host.queue.configure(failed_host)
	failed_host.add_child(failed_host.queue)
	failed_host.queue.enqueue(failed_host.source, [183], 5, 100)
	await _drain(failed_host.queue)
	check(failed_host.births == 4 and failed_host.queue._reserved.is_empty(), "cancelled failed birth releases its retained reservation")
	failed_host.queue.enqueue(failed_host.source, [183], 100, 100)
	await _drain(failed_host.queue)
	check(failed_host.births == 5, "failed birth leaves capacity available for a later release")
	failed_host.queue_free()
	await get_tree().process_frame
	print("MONSTER_SUMMON_HARD_CAP_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_boss_summons() -> void:
	var host := DummyHost.new()
	host.blocked = false
	add_child(host)
	var boss := _source(host, "boss:zuma")
	boss.setup(GameData.get_monster_by_id(160), null, false)
	boss.dormant = false
	check(boss.is_boss, "Boss exemption is canonical classification, not caller flag")
	var rule: Dictionary = boss.boss_rule.mechanics.healthStageSummon
	check(int(rule.minCount) == 4 and int(rule.maxCount) == 7 and int(rule.maxActive) == 15, "Zuma authored count4-7 cap15")
	check(Array(rule.monsterIds).map(func(id): return int(id)) == [156, 153, 150, 128], "original four ordinary kinds; no elite159")
	var queue := Queue.new()
	queue.configure(host)
	host.add_child(queue)
	boss.summon_requested.connect(queue.enqueue)
	var observed := {"counts": {}, "ids": {}}
	boss.summon_requested.connect(func(_source: EnemyActor, ids: Array, count: int, cap: int) -> void:
		check(count >= 4 and count <= 7 and cap == 15, "real Boss producer count/cap")
		check(ids.size() == count, "one original random kind selected per child")
		observed.counts[count] = true
		for id in ids:
			check(int(id) in [156, 153, 150, 128], "only original ordinary child ID emitted")
			observed.ids[id] = true
	)
	boss._rng.seed = 46215
	for release in range(40):
		boss._boss_health_stage = 5
		boss.current_hp = 1
		boss._apply_health_stage_mechanics()
		check(queue._active("boss:zuma") + int(queue._reserved.get("boss:zuma", 0)) <= 15, "rapid Boss stage signals capped15")
	check(observed.counts.size() == 4 and observed.ids.size() == 4, "deterministic samples cover counts4-7 and all four kinds")
	await _drain(queue)
	check(host.births == 15 and queue._active("boss:zuma") == 15, "Boss can exceed ordinary5 but cannot exceed authored15")
	host.queue_free()
	await get_tree().process_frame

func _check_boss_legacy_defaults() -> void:
	var host := DummyHost.new()
	host.blocked = false
	add_child(host)
	var boss := _source(host, "boss:legacy_defaults")
	boss.setup(GameData.get_monster_by_id(160), null, false)
	boss.dormant = false
	boss.boss_rule = boss.boss_rule.duplicate(true)
	var rule: Dictionary = boss.boss_rule.mechanics.healthStageSummon
	for key in ["minCount", "maxCount", "maxActive"]:
		rule.erase(key)
	var queue := Queue.new()
	queue.configure(host)
	host.add_child(queue)
	boss.summon_requested.connect(queue.enqueue)
	boss.summon_requested.connect(func(_source: EnemyActor, _ids: Array, count: int, cap: int) -> void:
		check(count >= 6 and count <= 11 and cap == 30, "generic Boss defaults remain original6-11/cap30")
	)
	for release in range(12):
		boss._boss_health_stage = 5
		boss.current_hp = 1
		boss._apply_health_stage_mechanics()
	await _drain(queue)
	check(host.births == 30 and queue._active("boss:legacy_defaults") == 30, "non-Zuma Boss cap30 is not reduced to5 or15")
	host.queue_free()
	await get_tree().process_frame
