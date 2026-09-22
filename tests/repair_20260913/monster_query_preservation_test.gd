extends Node

const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Policy := preload("res://scripts/monster_ai_package/policy.gd")
var checks := 0

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func expect(condition: bool, label: String) -> void:
	checks += 1
	assert(condition, label)

func context(blocked: Array) -> Dictionary:
	return Terrain.build_context(7, {
		"source": {"runtime_map_id": 7}, "build_sha256": "a".repeat(64),
		"design": {"design_size": [16, 16]}, "collision": {"blocked_tiles": blocked},
	}, Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID)

func _run() -> void:
	var first := context(["4,4", "5,4", "9,9"])
	var rebuilt := context(["2,2", "9,9"])
	expect(Terrain.context_valid(first), "formal immutable context")
	for terrain: Dictionary in [first, rebuilt, first]:
		var oracle := terrain.duplicate(true)
		for radius: float in [0.0, 0.25, 0.5, 0.50001, 0.75, 1.5]:
			for y in range(-1, 17):
				for x in range(-1, 17):
					var cell := Vector2i(x, y)
					expect(Terrain.cell_walkable(terrain, cell, radius) == Terrain.cell_walkable(oracle, cell, radius), "cached terrain matches uncached exact radius and rebuild")
	# Neither mutable contexts nor an extra blocked cell may reuse a prior hit.
	var mutable := first.duplicate(true)
	expect(Terrain.cell_walkable(mutable, Vector2i(2, 2), 0.25), "initial mutable cell")
	mutable.blocked_cells[Vector2i(2, 2)] = true
	expect(not Terrain.cell_walkable(mutable, Vector2i(2, 2), 0.25), "mutable terrain observed immediately")
	expect(not Terrain.cell_walkable(first, Vector2i(2, 2), 0.25, Vector2i(2, 2)), "transient extra blocker honored")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	var index := Index.new()
	var actors: Array[EnemyActor] = []
	var positions: Dictionary = {}
	var radii: Dictionary = {}
	for i in range(64):
		var actor := EnemyActor.new()
		actor.current_hp = 100
		actor.runtime_map_id = 7 if i < 56 else 8
		actor.spatial_actor_runtime_id = i + 1
		actors.append(actor)
		positions[actor] = Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		radii[actor] = 0.25 + float(i % 6) * 0.25
		index.register(i + 1, actor.runtime_map_id, positions[actor], radii[actor], i, actor)
	for trial in range(160):
		var moved := actors[trial % 56]
		positions[moved] = Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		index.update_actor(moved.spatial_actor_runtime_id, positions[moved])
		if trial == 80:
			actors[3]._death_pending = true
		var a := Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		var b := a + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		for expansion: float in [Policy.LANE_GU, 0.5]:
			var coarse: Array = []
			var tight: Array = []
			index.query_enemy_nodes_segment_into(7, a, b, expansion, coarse)
			index.query_enemy_nodes_segment_unsorted_into(7, a, b, expansion, tight)
			var low := Vector2(minf(a.x,b.x), minf(a.y,b.y)) - Vector2.ONE * (expansion + 1.5)
			var high := Vector2(maxf(a.x,b.x), maxf(a.y,b.y)) + Vector2.ONE * (expansion + 1.5)
			for actor: EnemyActor in coarse:
				var p: Vector2 = positions[actor]
				var inside := p.x >= low.x and p.x <= high.x and p.y >= low.y and p.y <= high.y
				expect(tight.has(actor) == inside, "same-frame move, exact inclusive envelope, live admission")
				var blocks := Policy.frontline_blocks(a, b, p, 0.5, 0.5, radii[actor], 100, actor.spatial_actor_runtime_id) if expansion == Policy.LANE_GU else Policy.core_crossed(a,b,p,0.5,radii[actor])
				expect(not blocks or tight.has(actor), "never prune a true narrow-phase blocker")
	index.clear_map(7)
	var cleared: Array = []
	index.query_enemy_nodes_segment_unsorted_into(7, Vector2(-20,-20), Vector2(20,20), 1.0, cleared)
	expect(cleared.is_empty(), "map lifecycle")
	for actor: EnemyActor in actors:
		actor.free()
	print("MONSTER_QUERY_PRESERVATION_PASS checks=%d" % checks)
	get_tree().quit()
