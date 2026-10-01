extends RefCounted
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Spatial := preload("res://scripts/runtime_combat_spatial_index.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const PolyIndex := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Build := preload("res://scripts/map_editor/polygon/poly_build.gd")

static func to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

static func to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)

static func open_context() -> Dictionary:
	return {"valid": true, "contract_id": Terrain.CONTRACT_ID, "runtime_map_id": 1,
		"build_sha256": "b".repeat(64), "coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80), "blocked_cells": {}}

static func polygon_context(polygons: Array, radius: float) -> Dictionary:
	var entries: Array = []
	for polygon: Array in polygons:
		entries.append(Author.entry("r3_%d" % entries.size(), Geo.decode(polygon)))
	var prepared := Author.prepare({"design": {"design_size": [16, 16]},
		"editor_meta": {"collision_authority": Geo.AUTHORITY}, "layers": {"collision": entries}})
	if not prepared.ok:
		return {}
	var index := PolyIndex.new()
	if not index.setup(Vector2i(16, 16), prepared.parts):
		return {}
	var baked := Build._bake(Vector2i(16, 16), prepared.entries, index, radius, Graph.key_for_radius(radius))
	if not baked.ok:
		return {}
	return Terrain.build_context(1, {"build_sha256": "c".repeat(64), "source": {"runtime_map_id": 1},
		"design": {"design_size": [16, 16]}, "collision": {
		"coordinate_contract_id": Geo.CONTRACT, "physics_source_id": Geo.PHYSICS_SOURCE,
		"ground_coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"convex_parts_ground_gu": prepared.parts, "blocked_tiles": [], "blocked_count": 0,
		"navigation": {"contract_id": "hc.polygon_nav_faces.v1", "profiles": [baked.record]}}},
		Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID)

static func player(owner_node: Node, ground: Vector2) -> PlayerCharacter:
	var result := PlayerCharacter.new()
	result.set_meta("runtime_map_id", 1)
	result.set_meta("zone_generation", 1)
	result.global_position = to_screen(ground)
	owner_node.add_child(result)
	result.set_physics_process(false)
	result.max_hp = 1000000
	result.current_hp = 1000000
	return result

static func enemy(owner_node: Node, id: int, ground: Vector2, victim: PlayerCharacter,
	context: Dictionary = {}) -> EnemyActor:
	var result := EnemyActor.new()
	result.setup(GameData.get_monster_by_id(id), victim, false)
	result.global_position = to_screen(ground)
	result.set_meta("spawn_position", result.global_position)
	result.set_meta("safe_zones", [])
	result.set_meta("zone_generation", 1)
	result.configure_runtime_map_projection(1, Callable(GU, "ground_delta_gu_to_screen_delta_px"),
		Callable(GU, "screen_delta_px_to_ground_delta_gu"))
	result.configure_terrain_navigation_context(open_context() if context.is_empty() else context)
	owner_node.add_child(result)
	result.set_physics_process(false)
	result.target = victim
	result.take_damage(1, victim)
	result.spatial_actor_runtime_id = result.get_instance_id()
	result.combat_spatial_index = Spatial.new()
	result.combat_spatial_index.register(result.spatial_actor_runtime_id, 1,
		to_ground(result.global_position), result.combat_radius_gu, 1, result)
	return result

static func dispose(actor: EnemyActor, victim: PlayerCharacter) -> void:
	if actor.combat_spatial_index != null:
		actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	victim.free()

static func write_evidence(name: String, payload: Dictionary) -> bool:
	var root := "res://outputs/test_logs/source176_r3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var file := FileAccess.open(root + "/" + name + ".json", FileAccess.WRITE)
	if file == null:
		return false
	payload["reported_tested_sha"] = OS.get_environment("HARDCORE_R3_TESTED_SHA")
	payload["runtime_content_sha256"] = OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	file.store_string(JSON.stringify(payload, "  "))
	return true
