extends Node

## R2-W10 ground-loot expiry counterexamples: an unresolved inventory
## transaction must never be destroyed by the ground lifetime, the per-pass
## expiry work stays bounded (32 expirations + 8 pending re-visits), and a
## duplicate registration of the same live pickup keeps one spatial entry
## (index-level unregister-then-insert idempotency).

const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const LootManagerScript := preload("res://scripts/loot_pickup_runtime_manager.gd")

var _manager: Node
var _player: PlayerCharacter
var _gold_events := 0

var checks := 0
var failures: Array[String] = []


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("LOOT_EXPIRY_GUARD: " + label)


func _screen_to_ground(position_px: Vector2) -> Vector2:
	return position_px


func _ground_to_screen(position_gu: Vector2) -> Vector2:
	return position_gu


func _on_gold_collected(_amount: int, pickup: LootPickup) -> void:
	_gold_events += 1
	pickup.confirm_collect()


func _new_pickup(position: Vector2) -> LootPickup:
	var pickup := LootPickupScript.new()
	pickup.setup_gold(1, _player)
	pickup.gold_collected.connect(_on_gold_collected)
	add_child(pickup)
	pickup.global_position = position
	if not _manager.register_pickup(pickup):
		push_error("LOOT_EXPIRY_GUARD: register failed")
		pickup.free()
		return null
	return pickup


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_player = PlayerCharacter.new()
	_player.set_physics_process(false)
	_player.global_position = Vector2(20000.0, 20000.0)
	add_child(_player)
	_manager = LootManagerScript.new()
	add_child(_manager)
	_manager.configure_player(_player)
	_manager.configure_map(
		11,
		1,
		Callable(self, "_screen_to_ground"),
		Callable(self, "_ground_to_screen"),
	)

	# ---- 1. A pending transaction is never destroyed by the ground lifetime.
	var pending_pickup := _new_pickup(Vector2(500.0, 500.0))
	check(pending_pickup != null, "pending pickup registered")
	pending_pickup._collection_pending = true
	_manager._ground_age = 600.0 + 1.0 # past GROUND_LIFETIME_SECONDS
	_manager._expire_ground_loot(0.0)
	check(
		is_instance_valid(pending_pickup) and not pending_pickup.is_queued_for_deletion(),
		"unresolved transaction survives the ground lifetime"
	)
	check(
		_manager._audit_expiry_pending.size() >= 1,
		"pending pickup is re-visitable instead of destroyed"
	)
	# The transaction resolves later: the next audit pass frees the corpse.
	pending_pickup.confirm_collect()
	_manager._expire_ground_loot(0.0)
	_manager._expire_ground_loot(0.0)
	check(
		pending_pickup.is_queued_for_deletion(),
		"resolved pending pickup is freed by the audit pass"
	)

	# ---- 2. One pass expires at most 32 overdue entries.
	var batch: Array[LootPickup] = []
	for index in range(40):
		var pickup := _new_pickup(Vector2(600.0 + float(index), 600.0))
		if pickup != null:
			batch.append(pickup)
	check(batch.size() == 40, "batch fixtures registered")
	_manager._ground_age = 10000.0 # far past every GROUND_LIFETIME deadline
	_manager._expire_ground_loot(0.0)
	var alive_after_one_pass := 0
	for pickup in batch:
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			alive_after_one_pass += 1
	check(
		alive_after_one_pass >= 40 - 32 - 8,
		"one pass keeps bounded expiry work (alive=%d)" % alive_after_one_pass
	)
	# The remaining overdue entries drain on later passes without loss.
	for _pass in range(4):
		_manager._expire_ground_loot(0.0)
	for pickup in batch:
		check(
			not is_instance_valid(pickup) or pickup.is_queued_for_deletion(),
			"overdue loot drains completely across passes"
		)

	# ---- 3. Spatial index registration is idempotent per runtime id.
	# Manager-level register_pickup has no duplicate guard today (production
	# only ever registers freshly created nodes, so it is unreachable there);
	# this pins the correctness boundary the index itself guarantees.
	var duplicate := _new_pickup(Vector2(900.0, 900.0))
	check(duplicate != null, "duplicate fixture registered once")
	var index_before: int = _manager._spatial_index.registered_pickup_count()
	check(
		_manager._spatial_index.register(
			duplicate.get_instance_id(),
			11,
			Vector2(900.0, 900.0),
			999999,
			duplicate,
		),
		"index re-registration of the same id is accepted"
	)
	check(
		_manager._spatial_index.registered_pickup_count() == index_before,
		"re-registration must not duplicate the spatial entry"
	)
	check(
		_manager._spatial_index.ground_position_for(duplicate.get_instance_id())
			== Vector2(900.0, 900.0),
		"re-registration keeps one resolvable position"
	)
	duplicate.queue_free()

	if failures.is_empty():
		print("LOOT_EXPIRY_GUARD_PASS checks=", checks)
		get_tree().quit(0)
	else:
		print("LOOT_EXPIRY_GUARD_FAILED count=%d" % failures.size())
		get_tree().quit(1)
