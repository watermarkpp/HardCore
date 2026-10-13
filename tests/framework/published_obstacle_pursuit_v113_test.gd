extends Node

## Real released geometry, formal body resolution, and HC scheduler search entry.
## Missing exact-radius data must fail FOUND; the error itself is never success.
const Body := preload("res://scripts/actor_body_policy.gd")
const MapBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const PolyRuntime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "published_obstacle_pursuit_v113_test"
const START := Vector2(10, 13)
const GOAL := Vector2(18, 13)
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

static func destinations() -> Dictionary:
	return {Vector2i(18, 13): GOAL}

func run() -> void:
	var runtime := MapBridge.load_map(918005)
	check(not runtime.is_empty(), "918005 approved release loads")
	var context := Terrain.build_context(918005, runtime, "isometric_cell_center_64x32_v2")
	check(Terrain.context_valid(context, 918005), "918005 formal polygon context valid")
	var rows: Array = []
	for id: int in [64, 89, 236, 224]:
		var entry := MonsterIdentity.require_catalog_entry(id)
		var body := Body.resolve_monster_body(id, str(entry.get("classification", "")), MonsterIdentity.body_profile(id))
		check(not body.is_empty(), "formal body monster=%d" % id)
		if body.is_empty():
			continue
		var radius := WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(float(body.screen_radius_px))
		check(Terrain.point_walkable(context, START, radius), "full body legal origin monster=%d" % id)
		check(Terrain.point_walkable(context, GOAL, radius), "full body legal goal monster=%d" % id)
		check(not PolyRuntime.segment_walkable(context, START, GOAL, radius), "published central stone blocks direct pursuit monster=%d" % id)
		var task := Search.new()
		task.set_polygon_origin(START)
		task.configure_deferred(context, Vector2i(10, 13), destinations, radius, Callable())
		var calls := 0
		while task.state in ["PREPARING", "SEARCHING"] and calls < 4096:
			task.advance(32)
			calls += 1
		check(task.state == "FOUND", "central stone detour FOUND monster=%d actual=%s" % [id, task.state])
		check(not task.path.is_empty(), "central stone detour nonempty monster=%d" % id)
		var previous := START
		var sideways := false
		var route: Array = []
		for point: Vector2 in task.path:
			check(PolyRuntime.segment_walkable(context, previous, point, radius), "detour segment full-footprint clear monster=%d" % id)
			sideways = sideways or absf(point.y - START.y) > 0.5
			route.append([point.x, point.y])
			previous = point
		check(sideways, "route goes around central stone monster=%d" % id)
		check(previous.distance_to(GOAL) < 0.001, "route reaches last-known target position monster=%d" % id)
		rows.append({"monster_id": id, "radius_gu": radius, "state": task.state, "advance_calls": calls, "expansions": task.expansions, "route": route})
	var evidence := {"map_id": 918005, "build_sha256": runtime.get("build_sha256", ""), "cases": rows, "checks": checks, "failures": failures, "scope": "published_navigation_only"}
	FileAccess.open("user://published_obstacle_pursuit_v113.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	var receipt_ok := proof.write_receipt(SCENE_ID, checks, failures.size())
	print("PUBLISHED_OBSTACLE_PURSUIT_", "PASS" if failures.is_empty() and receipt_ok else "FAIL", " ", JSON.stringify(evidence))
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)
