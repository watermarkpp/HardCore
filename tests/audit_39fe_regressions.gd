extends Node
## Run only with the package's isolated-userdata runner. Never real APPDATA.
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Query := preload("res://scripts/layers/runtime/combat_target_query_service.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Ground := preload("res://scripts/ground_effect.gd")
const Manager := preload("res://scripts/persistent_ground_effect_manager.gd")
const Splice := preload("res://scripts/map_editor/map_registry_entry_splice.gd")
const Enemy := preload("res://scripts/enemy.gd")

class FailingInventory:
	extends "res://scripts/player_state.gd"
	func _commit_save() -> bool:
		return false
	func _inventory_records_mergeable(a: Dictionary, b: Dictionary) -> bool:
		return a.get("name") == b.get("name")

var _failed := 0
var _checked := 0

func _ready() -> void:
	var formal_test_data := OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata")
	if OS.get_environment("HARDCORE_AUDIT_SANDBOX") != "1" and not formal_test_data:
		push_error("AUDIT STOP: isolated-userdata runner required")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	_checked += 1
	if not condition:
		_failed += 1
		push_error("AUDIT FAIL: " + label)
	else:
		print("AUDIT PASS: " + label)

func _context() -> Dictionary:
	return Snapshot.make_absolute_runtime_context(7, Vector2.ZERO, Vector2.ZERO, func(v: Vector2) -> Vector2: return v)

func _run() -> void:
	_sector()
	_snapshot()
	_registry()
	_pending()
	_spatial()
	_claim_gc()
	_inventory()
	print("AUDIT_RESULT checks=%d failures=%d" % [_checked, _failed])
	get_tree().quit(0 if _failed == 0 else 1)

func _sector() -> void:
	var query := Query.new(null, 7)
	var request := {"radius_gu": 5.0, "half_angle_rad": deg_to_rad(30.0), "direction_ground": Vector2.RIGHT}
	var edge_target := Vector2.from_angle(deg_to_rad(32.0)) * 4.0
	_check(query._exact_hit("sector", request, Vector2.ZERO, edge_target, 0.2), "sector side-body intersection")
	_check(not query._exact_hit("sector", request, Vector2.ZERO, edge_target, 0.05), "sector outside body misses")
	_check(not query._exact_hit("sector", request, Vector2.ZERO, Vector2(7, 0), 0.2), "sector finite radial length")
	request["half_angle_rad"] = NAN
	_check(not query._exact_hit("sector", request, Vector2.ZERO, Vector2.ZERO, 0.2), "sector NaN angle rejected")

func _snapshot() -> void:
	var context := _context()
	var rectangle := Snapshot.create_directed_rectangle("audit.rect", "r1", Vector2(100, 150), Vector2.RIGHT, 5.0, 1.0, 0.0, 0.0, 0.0, "", context)
	_check(Snapshot.validate_for_consumer(rectangle, context).valid, "valid V2 rectangle accepted")
	var forged := rectangle.duplicate(true)
	forged["schema_version"] = 1
	_check(not Snapshot.validate_for_consumer(forged, context).valid, "V1 with absolute fields cannot enter STRICT_V2")
	forged = rectangle.duplicate(true)
	forged.erase("release_id")
	_check(not Snapshot.validate_for_consumer(forged, context).valid, "missing release ID rejected")
	var manager := Manager.new(null)
	var bounds := manager._snapshot_bounds_ground_gu(rectangle)
	_check(bounds == Rect2(100, 149.5, 5, 1), "directed rectangle manager uses full bounds")
	var capsule := Snapshot.create_swept_capsule_path("audit.capsule", "c1", Vector2(20, 30), Vector2(25, 33), 0.5, 4, "", -1, context)
	var cap_bounds: Rect2 = Snapshot.ground_aabb(capsule).bounds_ground_gu
	_check(cap_bounds == Rect2(19.5, 29.5, 6, 4), "capsule analytic broadphase bounds")
	var circle := Snapshot.create_circle("audit.circle", "c2", Vector2(20, 30), 1.0, 8, context)
	forged = circle.duplicate(true)
	forged["polygons_ground_gu"] = [circle.polygon_ground_gu, PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(INF, 0)])]
	_check(not Snapshot.validate_for_consumer(forged, context).valid, "all union polygon members validated")

func _registry() -> void:
	var old := '{"maps":[{"runtime_map_id":1,"map_key":"a","v":1.000},{"runtime_map_id":2,"map_key":"b","size":10}],"note":"{ untouched }"}'
	var expected: Dictionary = JSON.parse_string(old)
	expected.maps[1] = {"runtime_map_id": 2, "map_key": "b", "size": 35, "portals": [1, 2]}
	var result := Splice.replace_entry(old, expected, "b", 2, JSON.stringify(expected.maps[1]))
	_check(result.valid, "registry target full-object splice")
	_check(str(result.get("text", "")).contains('"v":1.000'), "unrelated registry bytes preserved")
	if result.valid:
		var parsed: Dictionary = JSON.parse_string(result.text)
		_check(parsed.maps[1].get("size") == 35 and parsed.maps[1].portals.size() == 2, "new geometry/portals not only hashes")
	expected.maps[0]["v"] = 2
	_check(not Splice.replace_entry(old, expected, "b", 2, JSON.stringify(expected.maps[1])).valid, "unrelated semantic edit refused")

func _pending() -> void:
	var enemy := Enemy.new()
	enemy._hc_path_token = 2
	enemy._hc_path_pending = true
	_check(not enemy._hc_path_job_current(1) and enemy._hc_path_pending, "old token cannot clear new pending")
	_check(not enemy._hc_path_job_current(2) and not enemy._hc_path_pending, "invalid current job clears owner pending")
	enemy.free()

func _spatial() -> void:
	var index := Index.new()
	var actor := Node2D.new()
	var live := {"position": Vector2.ZERO}
	index.register(1, 7, Vector2.ZERO, 0.1, 1, actor, func() -> Vector2: return live.position)
	live.position = Vector2(4.2, 0)
	index.query_aabb_candidates(7, Rect2(-1, -1, 7, 2))
	_check(index._entries[1].absolute_ground_gu == live.position, "lazy rehome synchronizes indexed position")
	index.update_actor(1, Vector2(INF, 0))
	_check(index._entries[1].absolute_ground_gu == live.position, "nonfinite update preserves last valid position")
	index.register(1, 7, Vector2(NAN, 0), 0.1, 1, actor)
	_check(index.registered_actor_count() == 1, "invalid reregister does not remove valid actor")
	actor.free()

func _claim_gc() -> void:
	Ground.reset_runtime_tick_claims_for_tests()
	for i in range(260):
		Ground._runtime_tick_claims[str(i)] = {"owner_effect_id": i, "next_allowed_msec": 10000}
	Ground._cleanup_runtime_tick_claims(1000)
	Ground._runtime_tick_claims["0"]["next_allowed_msec"] = -100000
	Ground._cleanup_runtime_tick_claims(1001)
	_check(Ground._runtime_tick_claims.has("0"), "claim GC not repeated on each hit")
	Ground._cleanup_runtime_tick_claims(2001)
	_check(not Ground._runtime_tick_claims.has("0"), "claim GC eventually removes expired key")
	Ground.reset_runtime_tick_claims_for_tests()

func _inventory() -> void:
	var state := FailingInventory.new()
	state.inventory = [{"name": "audit_item", "count": 2}]
	_check(not state._consume_inventory_index(0, 1), "consume returns failure on save failure")
	_check(state.inventory[0].count == 2, "consume restores inventory")
	state.inventory = [{"name": "audit_item", "count": 10}, {"name": "audit_item", "count": 20}]
	var result := state.sort_inventory_deterministic()
	_check(not result.success, "sort reports failed save")
	_check(state.inventory.size() == 2 and state.inventory[0].count == 10 and state.inventory[1].count == 20, "sort rollback keeps deep quantities 10+20, not 30+20")
	state.free()
