extends "res://tests/world_crowd_firewall_profile_test.gd"
## Controlled placement on the published map. All authored actors, geometry,
## stats, collision, AI, rendering and optional canonical fire walls stay live.
## Only test spawn locations/player HP differ. This is not device FPS evidence.

const Poly := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
var _crowd_count := 0

func _select_profile_focus(enemies: Array) -> Dictionary:
	_crowd_count = int(OS.get_environment("HARDCORE_DENSE_COUNT"))
	assert(_crowd_count in [10, 20, 30])
	assert(enemies.size() > _crowd_count)
	var offsets: Array[Vector2] = []
	for y in range(-5, 6):
		for x in range(-5, 6):
			var point := Vector2(x, y) * 0.85
			if point.length() >= 1.8 and point.length() <= 4.5:
				offsets.append(point)
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if a.length_squared() == b.length_squared(): return a.x < b.x if a.x != b.x else a.y < b.y
		return a.length_squared() < b.length_squared())
	var probe: EnemyActor = enemies[0]
	for enemy: EnemyActor in enemies:
		if enemy.combat_radius_gu > probe.combat_radius_gu: probe = enemy
	var context: Dictionary = _game._monster_terrain_navigation_context
	var center := Vector2.INF
	var placements: Array[Vector2] = []
	# Always choose the same 30-body legal site even for 10/20-body runs.
	for y in range(6, 58, 3):
		for x in range(5, 28, 3):
			var candidate := Vector2(x, y)
			if not probe._hc_point_walkable(candidate): continue
			var options: Array[Vector2] = []
			for offset: Vector2 in offsets:
				var point := candidate + offset
				if probe._hc_point_walkable(point) and Poly.segment_walkable(context, candidate, point, probe.combat_radius_gu):
					options.append(point)
			if options.size() >= 30:
				center = candidate
				placements = options
				break
		if center.is_finite(): break
	assert(center.is_finite(), "published map needs a legal 30-body fixture")
	var far_points: Array[Vector2] = []
	for y in range(3, 62, 2):
		for x in range(3, 30, 2):
			var point := Vector2(x, y)
			if point.distance_to(center) > 22.0 and probe._hc_point_walkable(point):
				far_points.append(point)
	assert(far_points.size() >= enemies.size() - _crowd_count)
	var layout: Array[Dictionary] = []
	for serial in range(enemies.size()):
		var enemy: EnemyActor = enemies[serial]
		var ground: Vector2 = placements[serial] if serial < _crowd_count else far_points[serial - _crowd_count]
		var screen := _ground_to_screen(ground)
		enemy.set_combat_position(screen, &"dense_profile_fixture")
		enemy.set_meta("spawn_position", screen)
		enemy._rng.seed = 20260922 + serial
		layout.append({"monster_id": enemy.monster_id, "ground": [ground.x, ground.y], "crowd": serial < _crowd_count})
	return {"position": _ground_to_screen(center), "nearby": _crowd_count,
		"kind": "published_map_controlled_crowd", "requested_crowd": _crowd_count,
		"total_authored_actors": enemies.size(), "layout": layout,
		"layout_sha256": JSON.stringify(layout).sha256_text()}

func _profile_source_hashes() -> Dictionary:
	var hashes := super._profile_source_hashes()
	for path in ["res://tests/world_dense_melee_profile_test.gd",
		"res://scripts/map_editor/polygon/poly_index.gd", "res://scripts/map_editor/polygon/poly_geometry.gd",
		"res://scripts/monster_ai_package/policy.gd", "res://scripts/runtime_combat_spatial_index.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes
