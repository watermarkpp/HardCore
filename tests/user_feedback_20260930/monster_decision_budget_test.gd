extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"
const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var actors: Array[EnemyActor] = []
	for n in range(30):
		var actor := _spawn(24, CENTER + Vector2(4.0 + float(n % 6) * 0.3, float(n / 6) * 0.3))
		actor.target = player
		actor.set_physics_process(true)
		actors.append(actor)
	var first_service: Array[int] = []
	var seen: Dictionary = {}
	var repeats := 0
	# Five oldest turns are a bounded service obligation. Thirty valid queued
	# actors need six batches, plus one observer boundary to retain callbacks.
	var service_epochs := 0
	for epoch in range(30):
		service_epochs = epoch + 1
		await get_tree().physics_frame
		# Production physics callbacks also use this exact queue after the
		# coroutine's turn. Retain their actual grants from the previous epoch.
		for id: int in Budget.snapshot().previous_owner_ids:
			if not seen.has(id):
				seen[id] = true
				first_service.append(id)
		for actor: EnemyActor in actors:
			var token := Budget.begin(actor, actor._hc_decision_scope())
			if token == 0:
				continue
			var id := actor.get_instance_id()
			if not seen.has(id):
				seen[id] = true
				first_service.append(id)
			Budget.end(token)
			var owners_before: int = Budget.snapshot().epoch_owner_count
			var repeat := Budget.begin(actor, actor._hc_decision_scope(), &"neighbor")
			if repeat != 0:
				repeats += 1
				Budget.end(repeat)
				_check(Budget.begin(actor, actor._hc_decision_scope(), &"neighbor") == 0, "same owner repeated a full chooser in one epoch")
			_check(Budget.snapshot().epoch_owner_count == owners_before, "same owner consumed a second frame slot")
		var snap := Budget.snapshot()
		_check(int(snap.epoch_owner_count) <= 5, "more than five distinct owners admitted in physics epoch")
		_check(int(snap.open_scopes) == 0, "decision scope remained open before await")
		if seen.size() == 30:
			break
	_check(first_service.size() == 30, "FIFO did not serve all 30 formal actors")
	_check(service_epochs <= 7, "thirty valid owners exceeded six batches plus observer boundary")
	_check(repeats > 0, "same-owner repeat admission was never exercised")
	for n in range(mini(first_service.size(), actors.size())):
		_check(first_service[n] == actors[n].get_instance_id(), "first-service order did not preserve FIFO: %d" % n)
	var queue: Array = Budget.snapshot().queue
	_check(queue.size() >= 3, "backlogged middle-invalid-owner case was not queued")
	if queue.size() >= 3:
		# An invalid owner in the middle must be removed while filling the next
		# bounded batch, so it cannot occupy one of the five service turns.
		var middle_id: int = queue[1].owner_id
		var middle_actor: EnemyActor = null
		var middle_snap: Dictionary = Budget.snapshot()
		for candidate: EnemyActor in actors:
			if candidate.get_instance_id() == middle_id:
				middle_actor = candidate
		_check(middle_actor != null, "middle invalid owner fixture missing")
		if middle_actor != null:
			var admitted_before_middle := int(Budget.snapshot().actual_admitted_count)
			middle_actor.set_physics_process(false)
			await get_tree().physics_frame
			await get_tree().process_frame
			middle_snap = Budget.snapshot()
			_check(not _queued(middle_id), "invalid middle owner remained in FIFO")
			_check(not middle_snap.serviced_owner_ids.has(middle_id), "invalid middle owner occupied a service turn")
			_check(int(middle_snap.epoch_owner_count) <= 5, "invalid middle owner exceeded epoch cap")
			_check(int(middle_snap.actual_admitted_count) > admitted_before_middle, "middle invalidation did not preserve valid service")
		queue = middle_snap.queue
	_check(queue.size() >= 2, "backlogged replacement/cancellation cases were not exercised")
	if queue.size() >= 2:
		var tail_id: int = queue.back().owner_id
		var replacement: EnemyActor = null
		for actor: EnemyActor in actors:
			if actor.get_instance_id() == tail_id:
				replacement = actor
		var queued_epoch: int = queue.back().queued_epoch
		replacement.set_meta("zone_generation", 2)
		var replaced := Budget.begin(replacement, replacement._hc_decision_scope())
		if replaced != 0:
			Budget.end(replaced)
		var retained := false
		for row: Dictionary in Budget.snapshot().queue:
			if int(row.owner_id) == tail_id:
				retained = int(row.queued_epoch) == queued_epoch and row.scope == replacement._hc_decision_scope()
		_check(retained, "scope replacement reset FIFO age or retained stale scope")
		var cancelled_id: int = queue[0].owner_id
		Budget.cancel(cancelled_id)
		_check(not _queued(cancelled_id), "cancelled owner remained queued")
		queue = Budget.snapshot().queue
		if not queue.is_empty():
			var disabled_id: int = queue[0].owner_id
			for actor: EnemyActor in actors:
				if actor.get_instance_id() == disabled_id:
					actor.set_physics_process(false)
			_check(not _queued(disabled_id), "disabled head blocked queue progress")
		queue = Budget.snapshot().queue
		if not queue.is_empty():
			var stale_id: int = queue[0].owner_id
			for actor: EnemyActor in actors:
				if actor.get_instance_id() == stale_id:
					actor.set_meta("zone_generation", 3)
			_check(not _queued(stale_id), "stale generation reserved an old queue turn")
	var final := Budget.snapshot()
	_check(int(final.max_epoch_owner_count) <= 5 and int(final.open_scopes) == 0, "budget final cap/scope contract failed")
	for actor: EnemyActor in actors:
		actor.set_physics_process(false)
		Budget.cancel(actor.get_instance_id())
		actor.free()
	_check(Budget.snapshot().queue_length == 0, "actor teardown left queued identities")
	player.free()
	print("MONSTER_DECISION_BUDGET_", "PASS" if failures.is_empty() else "FAIL", " ", failures, " ", final)
	get_tree().quit(0 if failures.is_empty() else 1)

func _queued(id: int) -> bool:
	for row: Dictionary in Budget.snapshot().queue:
		if int(row.owner_id) == id:
			return true
	return false
