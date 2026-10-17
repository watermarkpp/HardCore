extends Node
const SourceSearch := preload("res://scripts/monster_ai_package/path_search.gd")
const SourceTerrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Terrain := preload("res://scripts/gameplay/enemy/enemy_owner_terrain_navigation.gd")
const Polygon := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_runtime.gd")
const Context := preload("res://scripts/gameplay/enemy/enemy_owner_context_token.gd")
const Factory := preload("res://scripts/gameplay/enemy/enemy_owner_path_factory.gd")
class ClockInput:
	extends RefCounted
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func get_physics_frames() -> int: return 701
	func get_ticks_usec() -> int: return 100000

func _ready() -> void:
	var input := ClockInput.new()
	var terrain := Terrain.new()
	var polygon := Polygon.new()
	var contexts := Context.new()
	var admitted: bool = polygon.configure_owner({}, input)
	_verify(admitted, "original assertion 20")
	admitted = contexts.configure_owner({}, input)
	_verify(admitted, "original assertion 22")
	admitted = terrain.configure_owner({"Engine": input, "HCPPolyRuntime": polygon}, input)
	_verify(admitted, "original assertion 24")
	var factory := Factory.new()
	admitted = factory.configure_owner({"Terrain": terrain, "HCM30ContextTokenScript": contexts, "Time": input})
	_verify(admitted, "original assertion 27")
	var runtime := {"source": {"runtime_map_id": 7}, "build_sha256": "a".repeat(64), "design": {"design_size": [16, 16]}, "collision": {"blocked_tiles": ["7,7"]}}
	var context: Dictionary = SourceTerrain.build_context(7, runtime, SourceTerrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID)
	_verify(context.valid, "original assertion 30")
	var original := SourceSearch.new()
	var candidate: RefCounted = factory.create_search()
	var sibling: RefCounted = factory.create_search()
	_verify(candidate.shared == sibling.shared and candidate.shared == factory.shared, "original assertion 34")
	var goals := {Vector2i(12, 12): Vector2(12.5, 12.5)}
	original.configure(context, Vector2i(2, 2), goals, 0.1, Callable())
	candidate.configure(context, Vector2i(2, 2), goals, 0.1, Callable())
	var checks := 2
	for iteration in range(8192):
		var old_state: String = original.advance(1)
		var new_state: String = candidate.advance(1)
		_verify(old_state == new_state and original.expansions == candidate.expansions, "original assertion 42")
		checks += 1
		if old_state != "SEARCHING": break
	_verify(original.state == "FOUND" and original.path == candidate.path, "original assertion 45")
	_verify(candidate.shared.shared_heuristics.size() == 1, "original assertion 46")
	print("ENEMY_OWNER_PATH_DIRECT: PASS checks=", checks + 2, " scope=bounded A* source oracle; scheduler/S native NOT_RUN")
	var receipt_ok := proof.write_receipt("enemy_owner_path_direct_test", proof.records.size(), 0)
	print("ENEMY_OWNER_PATH_DIRECT_TEST_", "PASS" if receipt_ok else "FAIL")
	get_tree().quit(0 if receipt_ok else 1)

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
func _verify(value: bool, label: String) -> void:
	proof.record(value, label)
	assert(value, label)
