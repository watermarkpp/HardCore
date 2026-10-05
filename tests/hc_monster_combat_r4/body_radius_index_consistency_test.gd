extends Node

## R4 checkpoint review test. NOT_RUN by the remote reviewer.
## This is a GEOMETRY/FACTORY test, not a natural-cadence test.
## Do not change cooldowns or damage to make this test pass.
const IdentityScript := preload("res://scripts/monster_identity.gd")
const GroundUnitScript := preload("res://scripts/ground_unit_space.gd")
const IDS := [24, 76, 238, 239, 226]

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		printerr("R4_RADIUS_INDEX: ", message)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 8000
	var world_ready := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		world_ready = (
			int(game.get("current_map_id")) == GameData.service_runtime_map_id(0)
			and bool(game.call("gameplay_input_is_enabled"))
		)
		if world_ready:
			break
	_expect(world_ready, "fixture world must be ready before a factory assertion")
	if not world_ready:
		await _finish(game)
		return

	var index: RuntimeCombatSpatialIndex = game.get("_combat_spatial_index")
	_expect(index != null, "formal world must own its spatial index")
	if index == null:
		await _finish(game)
		return

	for offset in range(IDS.size()):
		var monster_id: int = IDS[offset]
		var profile: Dictionary = IdentityScript.body_profile(monster_id)
		var expected_radius: float = float(profile.get("ground_radius_gu", -1.0))
		_expect(expected_radius > 0.0, "formal body profile missing for %d" % monster_id)
		var spawn_ground := Vector2(40.5 + 2.0 * float(offset), 13.5)
		var spawn_screen: Vector2 = game.call("_canonical_ground_gu_to_screen_px", spawn_ground)
		var actor: EnemyActor = game.call(
			"_spawn_enemy", GameData.get_monster_by_id(monster_id), spawn_screen,
			monster_id in [76, 238, 239], -1.0,
			{"respawn_enabled": false, "spawn_slot_id": "test:r4-index-radius:%d" % monster_id}
		)
		_expect(actor != null, "formal factory rejected positive-control %d" % monster_id)
		if actor == null:
			continue
		# Freezing this actor is valid here: only initialization/index geometry
		# is tested. Natural combat must be covered by a different scene.
		actor.set_physics_process(false)
		var runtime_id: int = actor.spatial_actor_runtime_id
		var entry: Dictionary = index._entries.get(runtime_id, {})
		var indexed_radius: float = float(entry.get("bounds_gu", -1.0))
		_rows.append({
			"monster_id": monster_id, "runtime_id": runtime_id,
			"profile_gu": expected_radius, "actor_gu": actor.combat_radius_gu,
			"index_gu": indexed_radius,
		})
		_expect(not entry.is_empty(), "index entry missing for %d" % monster_id)
		_expect(
			absf(actor.combat_radius_gu - expected_radius) <= 0.000001,
			"actor/profile radius mismatch for %d" % monster_id
		)
		_expect(
			absf(indexed_radius - expected_radius) <= 0.000001,
			"index/profile radius mismatch for %d: index=%.9f expected=%.9f"
				% [monster_id, indexed_radius, expected_radius]
		)
		var collision: CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
		_expect(collision != null, "physical shape missing for %d" % monster_id)
		if collision != null:
			var polygon: ConvexPolygonShape2D = collision.shape as ConvexPolygonShape2D
			_expect(polygon != null, "expected formal footsole polygon for %d" % monster_id)
			if polygon != null:
				_expect(polygon.points.size() == 16, "footsole vertex count changed for %d" % monster_id)
				for vertex: Vector2 in polygon.points:
					var ground_vertex := GroundUnitScript.screen_delta_px_to_ground_delta_gu(vertex)
					_expect(
						absf(ground_vertex.length() - expected_radius) <= 0.00001,
						"physical/profile radius mismatch for %d" % monster_id
					)
		actor.queue_free()
		await get_tree().process_frame
	await _finish(game)

func _finish(game: Node) -> void:
	print("R4_RADIUS_INDEX_EVIDENCE ", JSON.stringify({"rows": _rows, "failures": _failures}))
	if is_instance_valid(game):
		game.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("R4_BODY_RADIUS_INDEX_CONSISTENCY_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
