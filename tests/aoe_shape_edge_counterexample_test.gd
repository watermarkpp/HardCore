extends Node

## R2-W4 AOE runtime counterexample matrix. Pins, for ALL six footprint
## shapes, the two contracts the existing broadphase parity test leaves
## unprobed:
##   1. broadphase superset at the shape boundary: an enemy whose CENTER is
##      outside the snapshot AABB but whose combat footprint is tangent to
##      the shape must still be a broadphase candidate AND an exact hit;
##   2. exact tangency is inclusive (contact epsilon), just beyond is not;
##   3. a discarded (tampered / emptied) snapshot degrades to NO hits, never
##      to an implicit circle hit.

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")

const RUNTIME_MAP_ID := 9104
const TARGET_RADIUS := 0.25
## CONTACT_EPSILON_GU is 0.0001; stay clearly beyond it for the miss cases.
const MISS_MARGIN := 0.05

var failures: Array[String] = []
var checks := 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("AOE_SHAPE_EDGE_COUNTEREXAMPLE: " + label)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var context := Snapshot.make_local_delta_context(
		Callable(GroundUnitSpace, "ground_delta_gu_to_screen_delta_px")
	)

	# ---- Per-shape edge counterexamples (snapshot level) ----
	_circle_cases(context)
	_sector_cases(context)
	_directed_rectangle_cases(context)
	_capsule_cases(context)
	_cell_union_cases(context)
	_target_footprint_cases(context)

	# ---- Broadphase superset at the shape boundary ----
	_broadphase_superset_cases(context)

	# ---- Invalid snapshots degrade to no hits ----
	_invalid_snapshot_cases(context)

	if failures.is_empty():
		print("AOE_SHAPE_EDGE_COUNTEREXAMPLE_PASS checks=", checks)
		get_tree().quit(0)
	else:
		print(
			"AOE_SHAPE_EDGE_COUNTEREXAMPLE_FAILED count=%d" % failures.size()
		)
		get_tree().quit(1)


func _hits(
	snapshot: Dictionary,
	position: Vector2,
	radius := TARGET_RADIUS
) -> bool:
	return Snapshot.intersects_target_combat_footprint_ground_gu(
		snapshot, position, radius
	)


func _circle_cases(context: Dictionary) -> void:
	var circle := Snapshot.create_circle(
		"player.aoe.circle", "edge.circle", Vector2.ZERO, 2.0, 48, context
	)
	check(_hits(circle, Vector2(2.25, 0)), "circle max-reach tangency inclusive")
	check(
		not _hits(circle, Vector2(2.25 + MISS_MARGIN, 0)),
		"circle just beyond tangency misses"
	)
	check(_hits(circle, Vector2(1.5, 0)), "circle interior hits")
	check(_hits(circle, Vector2(2.0, 0)), "circle boundary center hits")


func _sector_cases(context: Dictionary) -> void:
	var sector := Snapshot.create_sector_arc(
		"warrior.half_moon",
		"edge.sector",
		Vector2.ZERO,
		Vector2.RIGHT,
		3.0,
		PI / 12.0,
		32,
		context
	)
	check(
		_hits(sector, Vector2(3.25, 0)),
		"sector max-reach tangency inclusive"
	)
	check(
		not _hits(sector, Vector2(3.25 + MISS_MARGIN, 0)),
		"sector just beyond max reach misses"
	)
	var edge_direction := Vector2.RIGHT.rotated(PI / 12.0)
	check(
		_hits(sector, edge_direction * 2.0),
		"sector edge ray point hits"
	)
	var outside_direction := Vector2.RIGHT.rotated(PI / 12.0 + 0.2)
	check(
		not _hits(sector, outside_direction * 2.0),
		"sector outside the arc angle at mid radius misses"
	)
	check(
		not _hits(sector, Vector2.LEFT * 2.0),
		"sector behind the apex misses"
	)


func _directed_rectangle_cases(context: Dictionary) -> void:
	var rectangle := Snapshot.create_directed_rectangle(
		"warrior.thrusting",
		"edge.rect",
		Vector2.ZERO,
		Vector2.RIGHT,
		4.0,
		2.0,
		0.0,
		0.0,
		0.0,
		"",
		context
	)
	check(
		_hits(rectangle, Vector2(4.25, 0)),
		"rectangle far-edge tangency inclusive"
	)
	check(
		not _hits(rectangle, Vector2(4.25 + MISS_MARGIN, 0)),
		"rectangle just beyond the far edge misses"
	)
	var corner := Vector2(4, 1)
	var corner_diagonal := Vector2.ONE.normalized()
	check(
		_hits(rectangle, corner + corner_diagonal * TARGET_RADIUS),
		"rectangle corner tangency inclusive"
	)
	check(
		not _hits(
			rectangle, corner + corner_diagonal * (TARGET_RADIUS + MISS_MARGIN)
		),
		"rectangle just past the corner misses"
	)
	check(
		not _hits(rectangle, Vector2(-TARGET_RADIUS - MISS_MARGIN, 0)),
		"rectangle behind the origin misses"
	)


func _capsule_cases(context: Dictionary) -> void:
	var capsule := Snapshot.create_swept_capsule_path(
		"player.aoe.line", "edge.capsule", Vector2.ZERO, Vector2(4, 0), 0.5,
		8, "", -1, context
	)
	var tangent_y := 0.5 + TARGET_RADIUS
	check(
		_hits(capsule, Vector2(2, tangent_y)),
		"capsule side tangency inclusive"
	)
	check(
		not _hits(capsule, Vector2(2, tangent_y + MISS_MARGIN)),
		"capsule just beyond the side misses"
	)
	check(
		_hits(capsule, Vector2(4 + tangent_y, 0)),
		"capsule end-cap tangency inclusive"
	)
	check(
		not _hits(capsule, Vector2(4 + tangent_y + MISS_MARGIN, 0)),
		"capsule just beyond the end cap misses"
	)


func _cell_union_cases(context: Dictionary) -> void:
	var cells := Snapshot.create_cell_union(
		"wizard.ice_storm",
		"edge.cells",
		Vector2.ZERO,
		[Vector2i(0, 0), Vector2i(1, 0)],
		context
	)
	check(_hits(cells, Vector2(1, 0)), "cell center hits")
	check(
		_hits(cells, Vector2(1.75, 0)),
		"cell edge tangency inclusive"
	)
	check(
		not _hits(cells, Vector2(1.75 + MISS_MARGIN, 0)),
		"cell just beyond the edge misses"
	)
	var cell_corner := Vector2(1.5, 0.5)
	var diagonal := Vector2.ONE.normalized()
	check(
		_hits(cells, cell_corner + diagonal * TARGET_RADIUS),
		"cell corner tangency inclusive"
	)
	check(
		not _hits(
			cells, cell_corner + diagonal * (TARGET_RADIUS + MISS_MARGIN)
		),
		"cell just past the corner misses"
	)
	check(
		not _hits(cells, Vector2(2.3, 0)),
		"gap beyond the union misses"
	)


func _target_footprint_cases(context: Dictionary) -> void:
	var footprint := Snapshot.create_target_footprint(
		"wizard.lightning",
		"edge.footprint",
		Vector2.ZERO,
		1.0,
		42,
		context
	)
	check(
		_hits(footprint, Vector2(1.25, 0)),
		"target footprint circle tangency inclusive"
	)
	check(
		not _hits(footprint, Vector2(1.25 + MISS_MARGIN, 0)),
		"target footprint just beyond tangency misses"
	)
	check(_hits(footprint, Vector2(0.5, 0)), "target footprint overlap hits")


func _enemy(position: Vector2, radius := TARGET_RADIUS) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.current_hp = 100
	enemy.max_hp = 100
	enemy.combat_radius_gu = radius
	enemy.global_position = position
	enemy._dying = false
	enemy._death_pending = false
	return enemy


func _exact_hit(snapshot: Dictionary, enemy: EnemyActor) -> bool:
	return _hits(snapshot, enemy.global_position, enemy.combat_radius_gu)


func _broadphase_superset_cases(context: Dictionary) -> void:
	# Enemies whose centers sit OUTSIDE the shape AABB by exactly their combat
	# radius (tangent footprints) are the tightest broadphase case.
	var cases := [
		{
			"label": "circle",
			"snapshot": Snapshot.create_circle(
				"player.aoe.circle", "bp.circle", Vector2.ZERO, 2.0, 48, context
			),
			"straddle": Vector2(2.25, 0),
			"near_miss": Vector2(2.3, 0),
			"inside": Vector2(1.5, 0),
		},
		{
			"label": "sector_arc",
			"snapshot": Snapshot.create_sector_arc(
				"warrior.half_moon", "bp.sector", Vector2.ZERO, Vector2.RIGHT,
				3.0, PI / 12.0, 32, context
			),
			"straddle": Vector2(3.25, 0),
			"near_miss": Vector2(3.3, 0),
			"inside": Vector2(1.5, 0),
		},
		{
			"label": "directed_rectangle",
			"snapshot": Snapshot.create_directed_rectangle(
				"warrior.thrusting", "bp.rect", Vector2.ZERO, Vector2.RIGHT,
				4.0, 2.0, 0.0, 0.0, 0.0, "", context
			),
			"straddle": Vector2(4.25, 0),
			"near_miss": Vector2(4.3, 0),
			"inside": Vector2(2, 0),
		},
		{
			"label": "swept_capsule_path",
			"snapshot": Snapshot.create_swept_capsule_path(
				"player.aoe.line", "bp.capsule", Vector2.ZERO, Vector2(4, 0),
				0.5, 8, "", -1, context
			),
			"straddle": Vector2(2, 0.75),
			"near_miss": Vector2(2, 0.8),
			"inside": Vector2(2, 0),
		},
		{
			"label": "cell_union",
			"snapshot": Snapshot.create_cell_union(
				"wizard.ice_storm", "bp.cells", Vector2.ZERO,
				[Vector2i(0, 0), Vector2i(1, 0)], context
			),
			"straddle": Vector2(1.75, 0),
			"near_miss": Vector2(1.8, 0),
			"inside": Vector2(0.5, 0),
		},
	]
	for case: Dictionary in cases:
		var snapshot: Dictionary = case.snapshot
		var index := SpatialIndex.new()
		var enemies: Array[EnemyActor] = []
		var slots := {
			"straddle": case.straddle,
			"near_miss": case.near_miss,
			"inside": case.inside,
			"far": Vector2(50, 50),
		}
		var slot_ids := {}
		var slot_index := 0
		for slot: String in slots.keys():
			var enemy := _enemy(slots[slot])
			enemies.append(enemy)
			slot_ids[enemy.get_instance_id()] = slot
			index.register(
				slot_index + 1, RUNTIME_MAP_ID, slots[slot],
				enemy.combat_radius_gu, slot_index + 1, enemy
			)
			slot_index += 1
		var bounds: Rect2 = Snapshot.ground_aabb(snapshot).get(
			"bounds_ground_gu", Rect2()
		)
		check(bool(Snapshot.ground_aabb(snapshot).get("valid", false)),
			"%s ground aabb valid" % case.label)
		var candidates: Array = []
		index.query_enemy_nodes_aabb_into(RUNTIME_MAP_ID, bounds, candidates)
		var exact_from_full_scan: Array[int] = []
		var exact_from_candidates: Array[int] = []
		for enemy: EnemyActor in enemies:
			if not _exact_hit(snapshot, enemy):
				continue
			exact_from_full_scan.append(enemy.get_instance_id())
			if candidates.has(enemy):
				exact_from_candidates.append(enemy.get_instance_id())
		var label: String = case.label
		check(
			exact_from_full_scan == exact_from_candidates,
			"%s broadphase is a superset of exact hits (straddle included)"
			% label
		)
		var expected_hits := ["straddle", "inside"]
		for instance_id: int in exact_from_full_scan:
			check(
				slot_ids.get(instance_id, "") in expected_hits,
				"%s exact set is exactly straddle+inside" % label
			)
		index.clear_map(RUNTIME_MAP_ID)
		for enemy: EnemyActor in enemies:
			enemy.free()


func _invalid_snapshot_cases(context: Dictionary) -> void:
	var base_cases := [
		{
			"label": "circle",
			"snapshot": Snapshot.create_circle(
				"player.aoe.circle", "inv.circle", Vector2.ZERO, 2.0, 48, context
			),
			"victim": Vector2(1.0, 0),
		},
		{
			"label": "sector_arc",
			"snapshot": Snapshot.create_sector_arc(
				"warrior.half_moon", "inv.sector", Vector2.ZERO, Vector2.RIGHT,
				3.0, PI / 12.0, 32, context
			),
			"victim": Vector2(1.0, 0),
		},
		{
			"label": "directed_rectangle",
			"snapshot": Snapshot.create_directed_rectangle(
				"warrior.thrusting", "inv.rect", Vector2.ZERO, Vector2.RIGHT,
				4.0, 2.0, 0.0, 0.0, 0.0, "", context
			),
			"victim": Vector2(2, 0),
		},
		{
			"label": "swept_capsule_path",
			"snapshot": Snapshot.create_swept_capsule_path(
				"player.aoe.line", "inv.capsule", Vector2.ZERO, Vector2(4, 0),
				0.5, 8, "", -1, context
			),
			"victim": Vector2(2, 0),
		},
		{
			"label": "cell_union",
			"snapshot": Snapshot.create_cell_union(
				"wizard.ice_storm", "inv.cells", Vector2.ZERO,
				[Vector2i(0, 0), Vector2i(1, 0)], context
			),
			"victim": Vector2(0.5, 0),
		},
	]
	for case: Dictionary in base_cases:
		var snapshot: Dictionary = case.snapshot
		var victim: Vector2 = case.victim
		var label: String = case.label
		check(
			_hits(snapshot, victim),
			"%s victim is hit when the snapshot is valid" % label
		)
		# Broken base contract: the snapshot-level predicate must refuse.
		var broken: Dictionary = snapshot.duplicate(true)
		broken["contract_id"] = "skills.footprint_snapshot.tampered.v1"
		check(
			not _hits(broken, victim),
			"%s broken base contract yields no hits (no circle degeneration)"
			% label
		)
		# Strict V2 consumer gate must invalidate the tampered snapshot too.
		var strict := Snapshot.validate_for_consumer(
			broken,
			context,
			Snapshot.VALIDATION_STRICT_V2
		)
		check(
			not bool(strict.get("valid", true)),
			"%s strict V2 rejects the tampered snapshot" % label
		)
	# An erased cell union must not silently become anything else.
	var cell_snapshot: Dictionary = base_cases[4].snapshot
	var stripped := cell_snapshot.duplicate(true)
	stripped["geometry_cells_grid_steps"] = []
	check(
		not _hits(stripped, Vector2(0.5, 0)),
		"emptied cell union yields no hits (no implicit shape)"
	)
	# An empty snapshot is never a hit.
	check(
		not _hits({}, Vector2(0, 0)),
		"empty snapshot yields no hits"
	)
