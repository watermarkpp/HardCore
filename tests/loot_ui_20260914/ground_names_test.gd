extends Node
## Ground-name layout contract, 2026-09-20 user principle:
##   - a label's HOME is directly above its own ground icon (single-drop
##     position); after any refresh a label returns home whenever free
##   - displacement only on real conflict, always the nearest free slot,
##     bounded (<= 3 rings x 26px), never covering another item's icon
##   - burst changes coalesce into ONE layout pass; idle frames never relayout
##   - performance budget is asserted, not assumed.
const Manager := preload("res://scripts/loot_pickup_runtime_manager.gd")
const Layout := preload("res://scripts/loot_name_layout.gd")

const MAX_DISPLACEMENT := 80.0
const DENSE_BUDGET_USEC := 8000
const CLUSTER_BUDGET_USEC := 4000

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	LootPreferences.set_filter_level(0)
	var manager := Manager.new()
	add_child(manager)
	manager.configure_map(1, 1, func(p: Vector2) -> Vector2: return p, func(p: Vector2) -> Vector2: return p)
	var target := PlayerCharacter.new()

	# --- Scenario A: sparse items all sit at home, zero displacement ---
	var sparse: Array = []
	for i in range(5):
		sparse.append(_spawn_pickup(manager, target, Vector2(i * 420.0, i * 60.0)))
	Layout.arrange(sparse)
	for i in range(sparse.size()):
		var pickup: LootPickup = sparse[i]
		assert(pickup.name_label_display_offset == Vector2.ZERO, "sparse label %d must stay at home" % i)
		assert(pickup.global_position == _spawned_positions[i], "pickup node must never move")
	_assert_association(sparse)

	# --- Scenario B: realistic cluster resolves with bounded displacement ---
	var cluster: Array = []
	var cluster_spots := [
		Vector2(0, 0), Vector2(40, 0), Vector2(80, 0),
		Vector2(20, 30), Vector2(60, 30), Vector2(100, 30),
	]
	for spot: Vector2 in cluster_spots:
		cluster.append(_spawn_pickup(manager, target, spot))
	var cluster_start := Time.get_ticks_usec()
	Layout.arrange(cluster)
	var cluster_usec := Time.get_ticks_usec() - cluster_start
	assert(cluster_usec < CLUSTER_BUDGET_USEC, "cluster layout %dus over budget" % cluster_usec)
	for i in range(cluster.size()):
		for j in range(cluster.size()):
			if i == j: continue
			assert(not _label_rect(cluster[i]).intersects(_label_rect(cluster[j])), "cluster plates %d/%d overlap" % [i, j])
	_assert_association(cluster)
	# --- Scenario C: a displaced label returns home once the blocker leaves ---
	var pair_a := _spawn_pickup(manager, target, Vector2(2000, 0))
	var pair_b := _spawn_pickup(manager, target, Vector2(2020, 0))
	Layout.arrange([pair_a, pair_b])
	assert(pair_a.name_label_display_offset == Vector2.ZERO, "older item keeps home")
	assert(not _label_rect(pair_a).intersects(_label_rect(pair_b)), "pair plates must not overlap")
	var displaced := pair_b.name_label_display_offset
	assert(displaced != Vector2.ZERO, "younger item 20px away must yield its home")
	assert(displaced.length() <= MAX_DISPLACEMENT, "displacement %s over bound" % displaced)
	manager.unregister_pickup(pair_a)
	pair_a.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(pair_b.name_label_display_offset == Vector2.ZERO, "younger label must return home after blocker leaves")

	# --- Scenario D: burst coalescing, idle frames, filter trigger ---
	# Scenario C's unregister already flushed one layout; measure the burst
	# relative to that baseline.
	var baseline := manager.name_layout_count
	var dense: Array = []
	var before: Array = []
	for i in range(150):
		var pickup := _spawn_pickup(manager, target, Vector2((i % 15) * 10.0, (i / 15) * 8.0), i)
		dense.append(pickup)
		before.append(pickup.global_position)
	await get_tree().process_frame
	assert(manager.name_layout_count == baseline + 1, "burst must coalesce into one layout")
	var dense_start := Time.get_ticks_usec()
	Layout.arrange(dense)
	var dense_usec := Time.get_ticks_usec() - dense_start
	assert(dense_usec < DENSE_BUDGET_USEC, "dense 150 layout %dus over budget" % dense_usec)
	for i in range(dense.size()):
		assert(dense[i].global_position == before[i], "pickup node must never move")
		var displacement: Vector2 = dense[i].name_label_display_offset
		assert(displacement.length() <= MAX_DISPLACEMENT, "dense displacement over bound")
	for i in range(5):
		await get_tree().process_frame
	assert(manager.name_layout_count == baseline + 1, "idle frames must not relayout")
	LootPreferences.set_filter_level(1)
	await get_tree().process_frame
	assert(manager.name_layout_count == baseline + 2)
	for i in range(0, 150, 2):
		assert(not dense[i].name_label.visible)
	LootPreferences.set_filter_level(0)

	for pickup: LootPickup in dense:
		pickup.queue_free()
	for pickup: LootPickup in sparse:
		pickup.queue_free()
	for pickup: LootPickup in cluster:
		pickup.queue_free()
	pair_b.queue_free()
	await get_tree().process_frame
	manager.queue_free()
	target.free()
	await get_tree().process_frame
	print(
		"GROUND_NAMES_HOME_FIRST_PASS sparse=5 cluster=6 cluster_usec=%d dense=150 dense_usec=%d coalesced=1 return_home=true" % [
			cluster_usec, dense_usec,
		])
	get_tree().quit()

var _spawned_positions: Array = []

func _spawn_pickup(manager: Manager, target: PlayerCharacter, position: Vector2, parity := -1) -> LootPickup:
	var pickup := LootPickup.new()
	# Explicit parity keeps the filter assertion deterministic: even parity ->
	# item 80 (filterable), odd -> item 130 (always visible). Callers that do
	# not care fall back to the running spawn counter.
	var effective_parity: int = parity if parity >= 0 else _spawned_positions.size()
	var item := GameData.get_item_record(130 if effective_parity % 2 else 80)
	var item_id := GameData._stable_item_id(item)
	pickup.setup_item_record({"item_id": item_id, "output_item_id": item_id, "item_name": item.name, "output_record": item}, target)
	pickup.position = position
	add_child(pickup)
	assert(pickup.z_index == -2 and not pickup.z_as_relative)
	assert(manager.register_pickup(pickup))
	_spawned_positions.append(position)
	return pickup

func _label_rect(pickup: LootPickup) -> Rect2:
	return Rect2(
		pickup.global_position + pickup.name_label.position,
		pickup.name_label.size,
	)

func _assert_association(pickups: Array) -> void:
	for i in range(pickups.size()):
		var pickup: LootPickup = pickups[i]
		var label_rect := _label_rect(pickup)
		var home := pickup.global_position + pickup.name_label_home_position()
		assert(
			label_rect.position.distance_to(home) <= MAX_DISPLACEMENT,
			"label %d drifted from its own item home" % i,
		)
		for j in range(pickups.size()):
			if i == j: continue
			var other: LootPickup = pickups[j]
			var icon_core: Rect2 = other.ground_icon_rect_local().grow(-5.0)
			var icon_world := Rect2(
				other.global_position + icon_core.position,
				icon_core.size,
			)
			assert(
				not label_rect.intersects(icon_world),
				"label %d covers item %d's icon" % [i, j],
			)
