extends RefCounted

## Event-driven world-space label placement (2026-09-20 user principle,
## replacing the former block-packing grid that pooled a whole cluster's
## names above the cluster and broke name-to-item association):
##   1. Every label's HOME is directly above its own ground icon — the exact
##      position a single drop presents. After ANY refresh (drop, pickup,
##      expiry, filter change) a label returns home whenever the home slot is
##      free, including labels displaced by an earlier conflict.
##   2. A label leaves home only when the home slot is really taken, and then
##      takes the NEAREST free slot from bounded concentric rings (26px step,
##      3 rings ≈ ≤78px — under one plate width), direction order biased
##      upward away from the icon, then lateral, then downward.
##   3. Other pickups' ground-icon rects are association obstacles: a name
##      plate never covers another item's icon.
## Pickup/collection positions never move. The manager owns triggering:
## set changes mark a dirty flag and call arrange once per coalesced batch
## (call_deferred) — no timers, no per-frame work, idle frames cost nothing.

const CELL := Vector2(192, 96)
const PLATE_PADDING := 8.0
const GAP := 6.0
const RING_STEP := 26.0
const RING_COUNT := 3
# Deterministic nearest-first ring directions: up, upper diagonals, lateral,
# lower diagonals, down. No RNG anywhere.
const DIRECTIONS: Array[Vector2] = [
	Vector2.UP,
	Vector2(-0.70710678, -0.70710678),
	Vector2(0.70710678, -0.70710678),
	Vector2(-1.0, 0.0),
	Vector2(1.0, 0.0),
	Vector2(-0.70710678, 0.70710678),
	Vector2(0.70710678, 0.70710678),
	Vector2(0.0, 1.0),
]


static func arrange(pickups: Array) -> void:
	var ordered: Array = []
	var icon_index: Dictionary = {}
	for pickup: Node2D in pickups:
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			continue
		var label: Label = pickup.get("name_label")
		if label == null or not label.visible:
			continue
		ordered.append(pickup)
		# Association obstacle = the icon's VISUAL core (the rect shrunk by 5px
		# drops transparent texture edges): a plate brushing 2-5px of a
		# neighbour icon's transparent top edge must not force displacement,
		# while a plate actually sitting on the icon body is rejected.
		var icon_core := _icon_world_rect(pickup).grow(-5.0)
		if icon_core.size.x <= 0.0 or icon_core.size.y <= 0.0:
			# Tiny icons (small gold piles) collapse under the 5px shrink;
			# keep the ungrown visual core so the obstacle stays valid instead
			# of feeding negative-size rects into Rect2.intersects.
			icon_core = _icon_world_rect(pickup)
		_index_rect(icon_index, icon_core, pickup.get_instance_id())
	# Oldest registration first: first come keeps home priority.
	ordered.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return int(a.get_meta("loot_registration_order", a.get_instance_id())) < int(b.get_meta("loot_registration_order", b.get_instance_id())))
	# Saturation gate: when so many items share the search neighbourhood that
	# no candidate slot can possibly be free (members x own plate area exceed
	# the reachable region capacity), skip the search entirely and keep the
	# label at home — in a pathological pile the nearest slot IS home, and the
	# O(n x 9) gate replaces the O(candidates x members) scan that made dense
	# piles quadratic (measured 102ms for a 150-item pile before this gate).
	var home_cell_counts: Dictionary = {}
	for pickup: Node2D in ordered:
		var key: Vector2i = Vector2i((pickup.global_position / CELL).floor())
		home_cell_counts[key] = int(home_cell_counts.get(key, 0)) + 1
	var placed_index: Dictionary = {}
	for pickup: Node2D in ordered:
		var label: Label = pickup.get("name_label")
		var plate_size: Vector2 = pickup.get("name_plate_size")
		if not (plate_size is Vector2) or plate_size.x <= 0.0:
			plate_size = label.get_minimum_size() + Vector2(PLATE_PADDING, 0.0)
		var home_origin: Vector2 = (
			pickup.global_position + Vector2(-plate_size.x * 0.5, -36.0)
		)
		var offset := Vector2.ZERO
		if not _neighbourhood_saturated(pickup.global_position, plate_size, home_cell_counts):
			if _is_free(home_origin, plate_size, placed_index, icon_index, pickup.get_instance_id()):
				offset = Vector2.ZERO
			else:
				offset = _nearest_free_offset(
					home_origin, plate_size, placed_index, icon_index, pickup.get_instance_id())
		_index_rect(placed_index, Rect2(home_origin + offset, plate_size), -1)
		var target_local := Vector2(-plate_size.x * 0.5, -36.0) + offset
		if pickup.has_method("set_name_label_display_offset"):
			pickup.set_name_label_display_offset(offset)
		elif not label.position.is_equal_approx(target_local):
			label.position = target_local


## True when the 3x3 cell neighbourhood around the item already holds more
## plate area than the ring-search reachable region can hold, so no free
## candidate slot can exist and the search would be pure waste.
static func _neighbourhood_saturated(item_position: Vector2, plate_size: Vector2, home_cell_counts: Dictionary) -> bool:
	var own_area: float = plate_size.x * plate_size.y
	if own_area <= 0.0:
		return false
	var capacity := (CELL.x + RING_COUNT * RING_STEP * 2.0) * (CELL.y + RING_COUNT * RING_STEP * 2.0)
	var threshold: int = int(capacity / own_area)
	var key := Vector2i((item_position / CELL).floor())
	var members := 0
	for x: int in range(-1, 2):
		for y: int in range(-1, 2):
			members += int(home_cell_counts.get(key + Vector2i(x, y), 0))
	return members > threshold


static func _is_free(
	origin: Vector2,
	plate_size: Vector2,
	placed_index: Dictionary,
	icon_index: Dictionary,
	owner_id: int,
) -> bool:
	var plate_query := Rect2(origin, plate_size).grow(GAP * 0.5)
	var icon_query := Rect2(origin, plate_size)
	for cell: Vector2i in _cells(plate_query):
		for entry: Variant in placed_index.get(cell, []):
			if plate_query.intersects((entry as Array)[0]):
				return false
		for entry: Variant in icon_index.get(cell, []):
			var packed: Array = entry
			if int(packed[1]) == owner_id:
				continue
			if icon_query.intersects(packed[0]):
				return false
	return true


static func _nearest_free_offset(
	home_origin: Vector2,
	plate_size: Vector2,
	placed_index: Dictionary,
	icon_index: Dictionary,
	owner_id: int,
) -> Vector2:
	var home_center := home_origin + plate_size * 0.5
	var best_offset := Vector2.ZERO
	var best_overlap := INF
	for ring: int in range(1, RING_COUNT + 1):
		for direction: Vector2 in DIRECTIONS:
			var center := home_center + direction * (float(ring) * RING_STEP)
			var origin := center - plate_size * 0.5
			var overlap := _overlap_area(
				origin, plate_size, placed_index, icon_index, owner_id)
			if overlap <= 0.0:
				return center - home_center
			if overlap < best_overlap:
				best_overlap = overlap
				best_offset = center - home_center
	# Pathological pile where every ring slot is blocked: place at the
	# least-overlapping candidate so a name never disappears.
	return best_offset


## Total overlap area of a candidate plate against placed plates (with a
## half-GAP clearance grown in, so plates never visually touch) and against
## OTHER pickups' icon cores (ungrown: touching is not covering).
static func _overlap_area(
	origin: Vector2,
	plate_size: Vector2,
	placed_index: Dictionary,
	icon_index: Dictionary,
	owner_id: int,
) -> float:
	var plate_query := Rect2(origin, plate_size).grow(GAP * 0.5)
	var icon_query := Rect2(origin, plate_size)
	var total := 0.0
	for cell: Vector2i in _cells(plate_query):
		for entry: Variant in placed_index.get(cell, []):
			var other: Rect2 = (entry as Array)[0]
			if plate_query.intersects(other):
				total += plate_query.intersection(other).get_area()
		for entry: Variant in icon_index.get(cell, []):
			var packed: Array = entry
			if int(packed[1]) == owner_id:
				continue
			var other: Rect2 = packed[0]
			if icon_query.intersects(other):
				total += icon_query.intersection(other).get_area()
	return total


static func _icon_world_rect(pickup: Node2D) -> Rect2:
	var local: Rect2 = (
		pickup.ground_icon_rect_local()
		if pickup.has_method("ground_icon_rect_local")
		else Rect2(Vector2(-12, -16), Vector2(24, 24))
	)
	return Rect2(pickup.global_position + local.position, local.size)


static func _index_rect(index: Dictionary, rect: Rect2, owner_id: int) -> void:
	var entry := [rect, owner_id]
	for cell: Vector2i in _cells(rect.grow(GAP)):
		if not index.has(cell):
			index[cell] = []
		index[cell].append(entry)


static func _cells(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start := Vector2i((rect.position / CELL).floor())
	var end := Vector2i((rect.end / CELL).floor())
	for x: int in range(start.x, end.x + 1):
		for y: int in range(start.y, end.y + 1):
			result.append(Vector2i(x, y))
	return result
