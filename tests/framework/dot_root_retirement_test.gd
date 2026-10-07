extends "res://tests/framework/feature_state_loan_lifetime_test.gd"

# Current complete-replacement contract: an old STATE reference cannot keep
# every historical root alive. Independently accepted child branches still do.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "dot-root-retirement-owned"
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/state_loan_lifetime_registry.json"), "real finite-chain validation registry loads")
	check(ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime", true), "finite chain explicitly enables")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm", [])
	check(bindings.size() == 2, "original compiler supplies persistent and child bindings")
	if bindings.size() != 2: _finish(); return
	world = World.new(); world.configure(self, PlayerState)
	clock = Clock.new(); clock.configure(self)
	combat = Combat.new(); add_child(combat)
	source_a = Player.new(); add_child(source_a); source_a.set_physics_process(false)
	source_b = Player.new(); add_child(source_b); source_b.set_physics_process(false)
	check(source_a.begin_combat_transition("root:A") and source_a.finish_combat_transition("root:A")
		and source_b.begin_combat_transition("root:B") and source_b.finish_combat_transition("root:B"), "real source lifetimes enter READY")
	var view := Presentation.new(); view.configure(world, true)
	runtime = Runtime.new()
	check(runtime.configure(world, clock, combat, view) and runtime.configure_child_executor(_execute_unit_child), "one original consumer and real Combat port configure")
	runtime.require_reservations = true
	receivers = [_actor(Vector2(1,0),5000), _actor(Vector2.ZERO,5000)]
	var a: RefCounted = _submit("replace-root:A", [10,10], source_a, "A")
	check(a != null, "A accepts two real target facts")
	if a == null: _cleanup(); return
	await _pump()
	var a_id: int = a.sequence()
	check(runtime.active_count() == 2 and runtime.reservation_snapshot().actions == 1, "two A states retain only their actual root")
	var b: RefCounted = _submit("replace-root:B", [1], source_b, "B")
	check(b != null, "B capacity accepts one replacement")
	if b == null: _cleanup(); return
	await _pump()
	var b_id: int = b.sequence()
	check(runtime._reservations.has(a_id) and runtime._reservations[a_id].state_owners == 1, "A keeps only its other still-live state ownership")
	check(_target_state(0).chain_owners.size() == 1 and _target_state(0).chain_owners.has(b_id), "B state does not inherit cancelled A future production")
	var c: RefCounted = _submit("replace-root:C", [20], source_b, "C")
	check(c != null, "C accepts the next complete replacement")
	if c == null: _cleanup(); return
	await _pump()
	check(not runtime._reservations.has(b_id), "replaced-only B root retires despite a retained closed ticket object")
	check(runtime._reservations.has(a_id) and runtime.reservation_snapshot().actions == 2, "unrelated A state and current C remain independently owned")
	check(runtime.reservation_snapshot().states == 2, "only A and current replacement retain their unused state-loan slots")
	var last_id: int = c.sequence()
	for index in range(12):
		var next: RefCounted = _submit("replace-root:continuing:" + str(index), [2], source_b, "new:" + str(index))
		check(next != null, "continuing accepted replacement " + str(index))
		if next == null: _cleanup(); return
		await _pump()
		check(not runtime._reservations.has(last_id) and runtime.reservation_snapshot().actions == 2, "historical roots do not accumulate at replacement " + str(index))
		check(_target_state(0).chain_owners.size() == 1, "current state has exactly one future-production owner " + str(index))
		last_id = next.sequence()
	b.close(); c.close()
	check(runtime._reservations.has(last_id) and runtime._reservations.has(a_id), "old closed tickets cannot revoke the new state or another live root")
	clock.advance_simulation(4.0)
	await _pump()
	check(_promises_empty() and not runtime.has_work() and runtime.heap_count() == 0, "first scenario fully drains without TTL or forced root clear")
	for enemy: EnemyActor in receivers: enemy.queue_free()
	await get_tree().process_frame

	# Preserve a real old child while replacing its parent's final active state.
	receivers = [_actor(Vector2(1,0),1000), _actor(Vector2.ZERO,1)]
	var old: RefCounted = _submit("replace-root:pending-child", [10,1], source_a, "OLD_CHILD_CREDIT")
	check(old != null, "old root accepts a real surviving and a real lethal hit")
	if old == null: _cleanup(); return
	var old_id: int = old.sequence()
	runtime._dispatch_one_fact(); runtime._dispatch_one_fact()
	check(runtime.child_count() == 1 and runtime.active_count() == 1, "committed lethal fact has queued its independent child")
	receivers[1].queue_free()
	receivers[1] = _actor(Vector2.ZERO,1000)
	var newer: RefCounted = _submit("replace-root:before-child", [3], source_b, "NEW_STATE_CREDIT")
	check(newer != null, "new state replacement accepts before old child executes")
	if newer == null: _cleanup(); return
	runtime._dispatch_one_fact()
	check(runtime._reservations.has(old_id) and runtime._reservations[old_id].state_owners == 0, "old state owner retires but queued child independently retains old root")
	check(runtime.child_count() == 1 and runtime._reservations[old_id].branches.size() == 1, "old accepted branch is neither cancelled nor duplicated")
	var previous_children := child_deliveries
	var hp_before := [receivers[0].current_hp, receivers[1].current_hp]
	await _pump()
	check(child_deliveries == previous_children + 1, "old child still executes once through real Combat")
	check(receivers[0].current_hp == hp_before[0] - 1 and receivers[1].current_hp == hp_before[1] - 1, "both old-child actual HP writes are retained")
	check(_target_state(0).command.historical_credit.get("marker") == "OLD_CHILD_CREDIT", "later actual old child application keeps its original historical credit")
	check(not runtime._reservations.has(newer.sequence()), "newer root retires when the later real child replaces its last state")
	clock.advance_simulation(4.0)
	await _pump()
	check(_promises_empty() and runtime.active_count() == 0 and runtime.heap_count() == 0 and view.node_count() == 0, "queued child and all subsequent state/receipt/resource owners reach terminal")
	check(runtime.errors.is_empty(), "no hidden capacity failure or omitted child")
	_cleanup()

func _target_state(index: int) -> Dictionary:
	for state: Dictionary in runtime._states.values():
		if state.target.resolve() == receivers[index]: return state
	return {}

func _cleanup() -> void:
	if runtime != null: runtime.clear()
	for enemy: EnemyActor in receivers:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion(): enemy.queue_free()
	if is_instance_valid(source_a): source_a.queue_free()
	if is_instance_valid(source_b): source_b.queue_free()
	if is_instance_valid(combat): combat.queue_free()
	check(ContentLayers.reload_feature_catalog(), "default registry is restored")
	_finish()

func _finish() -> void:
	var written := proof.write_receipt("dot_root_retirement_test", proof.records.size(), errors.size())
	print("DOT_ROOT_RETIREMENT_", "PASS" if written and errors.is_empty() else "FAIL", " checks=", proof.records.size(), " errors=", errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
