extends RefCounted

## Event-driven world-space label packing. Pickup/collection positions never move.
const CELL := Vector2(192, 96)
const GAP := 4.0
const TWO_COLUMN_THRESHOLD := 5

static func arrange(pickups: Array) -> void:
	var buckets: Dictionary = {}
	for pickup: Node2D in pickups:
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion(): continue
		var label: Label = pickup.get("name_label")
		if label == null or not label.visible: continue
		var key := Vector2i((pickup.global_position / CELL).floor())
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(pickup)
	var visited: Dictionary = {}
	var blocks: Array = []
	# Each bucket is visited once, even when hundreds of items share one cell.
	for key: Vector2i in buckets:
		if visited.has(key): continue
		var queue: Array[Vector2i] = [key]
		visited[key] = true
		var cursor := 0
		var members: Array = []
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			members.append_array(buckets[cell])
			for x in range(-1, 2):
				for y in range(-1, 2):
					var neighbor := cell + Vector2i(x, y)
					if buckets.has(neighbor) and not visited.has(neighbor):
						visited[neighbor] = true
						queue.append(neighbor)
		members.sort_custom(func(a: Node, b: Node) -> bool:
			return int(a.get_meta("loot_registration_order", a.get_instance_id())) < int(b.get_meta("loot_registration_order", b.get_instance_id())))
		var bounds := Rect2(members[0].global_position, Vector2.ZERO)
		var extent := Vector2.ZERO
		for pickup: Node2D in members:
			bounds = bounds.expand(pickup.global_position)
			var label: Label = pickup.get("name_label")
			extent = extent.max(label.get_minimum_size())
		var columns := 2 if members.size() > TWO_COLUMN_THRESHOLD else 1
		var rows := ceili(float(members.size()) / columns)
		var size := Vector2(columns * extent.x + (columns - 1) * GAP, rows * extent.y + (rows - 1) * GAP)
		var rect := Rect2(Vector2(bounds.get_center().x - size.x * 0.5, bounds.position.y - 30.0 - size.y), size)
		blocks.append({"members":members, "columns":columns, "extent":extent, "rect":rect})
	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rect.position.y < b.rect.position.y)
	# Block collision index handles labels that extend across bucket boundaries.
	var occupied: Dictionary = {}
	for block: Dictionary in blocks:
		var rect: Rect2 = block.rect
		while true:
			var next_bottom := rect.end.y
			for cell: Vector2i in _cells(rect):
				for other: Rect2 in occupied.get(cell, []):
					if rect.grow(GAP * 0.5).intersects(other):
						next_bottom = minf(next_bottom, other.position.y - GAP)
			if is_equal_approx(next_bottom, rect.end.y): break
			rect.position.y = next_bottom - rect.size.y
		for cell: Vector2i in _cells(rect.grow(GAP)):
			if not occupied.has(cell): occupied[cell] = []
			occupied[cell].append(rect)
		var index := 0
		for pickup: Node2D in block.members:
			var label: Label = pickup.get("name_label")
			label.size = block.extent
			var row := floori(float(index) / int(block.columns))
			var column := index % int(block.columns)
			label.global_position = rect.position + Vector2(column, row) * (block.extent + Vector2.ONE * GAP)
			index += 1

static func _cells(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start := Vector2i((rect.position / CELL).floor())
	var end := Vector2i((rect.end / CELL).floor())
	for x in range(start.x, end.x + 1):
		for y in range(start.y, end.y + 1): result.append(Vector2i(x, y))
	return result
