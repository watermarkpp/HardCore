class_name EntrapmentBoundaryController
extends RefCounted

const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

const CONTRACT_ID := "skills.taoist.entrapment.boundary_controller.v1"
const SKILL_ID := "taoist.entrapment"
const REQUIRED_BOUNDARY_CELL_COUNT := 8
const CONTACT_EPSILON_GU := 0.0001

var _active := false
var _runtime_map_id := -1
var _caster_instance_id := 0
var _caster_ref: WeakRef
var _remaining_seconds := 0.0
var _boundary_snapshot: Dictionary = {}
var _center_cell := Vector2i.ZERO
var _last_end_reason := ""


func configure(
	effect: Dictionary,
	boundary_snapshot: Dictionary,
	expected_runtime_map_id: int,
	caster_actor: Node2D,
	ground_position_gu_to_screen_position_px: Callable
) -> Dictionary:
	reset("reconfigured")
	if str(effect.get("controller_contract_id", "")) != CONTRACT_ID:
		return _failure("controller_contract_mismatch")
	if not is_instance_valid(caster_actor):
		return _failure("caster_required")
	var declared_caster_id := int(effect.get("caster_instance_id", 0))
	if declared_caster_id <= 0 or declared_caster_id != caster_actor.get_instance_id():
		return _failure("caster_instance_mismatch")
	var duration_seconds := float(effect.get("duration_seconds", 0.0))
	if not is_finite(duration_seconds) or duration_seconds <= 0.0:
		return _failure("positive_duration_required")
	if expected_runtime_map_id < 0:
		return _failure("runtime_map_required")
	if int(effect.get("runtime_map_id", -1)) != expected_runtime_map_id:
		return _failure("descriptor_runtime_map_mismatch")
	var origin_ground_gu: Variant = boundary_snapshot.get(
		"origin_ground_gu", Vector2.INF
	)
	if not origin_ground_gu is Vector2 or origin_ground_gu == Vector2.INF:
		return _failure("snapshot_origin_required")
	var expected_context := SkillFootprintSnapshotScript.make_absolute_runtime_context(
		expected_runtime_map_id,
		origin_ground_gu,
		boundary_snapshot.get("projection_origin_ground_gu", origin_ground_gu),
		ground_position_gu_to_screen_position_px
	)
	var validation := SkillFootprintSnapshotScript.validate_for_consumer(
		boundary_snapshot,
		expected_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	)
	if not bool(validation.get("valid", false)):
		return _failure("strict_v2_snapshot_required", validation)
	if str(boundary_snapshot.get("skill_id", "")) != SKILL_ID:
		return _failure("entrapment_snapshot_required")
	if (
		str(boundary_snapshot.get("shape_type", ""))
		!= str(SkillFootprintSnapshotScript.SHAPE_CELL_UNION)
	):
		return _failure("cell_union_snapshot_required")
	var topology := _canonical_boundary_topology(boundary_snapshot)
	if not bool(topology.get("valid", false)):
		return _failure(str(topology.get("reason", "invalid_boundary_topology")))
	_runtime_map_id = expected_runtime_map_id
	_caster_instance_id = declared_caster_id
	_caster_ref = weakref(caster_actor)
	_remaining_seconds = duration_seconds
	_boundary_snapshot = boundary_snapshot.duplicate(true)
	_center_cell = topology.get("center_cell", Vector2i.ZERO)
	_last_end_reason = ""
	_active = true
	return {
		"valid": true,
		"reason": "",
		"contract_id": CONTRACT_ID,
		"runtime_map_id": _runtime_map_id,
		"caster_instance_id": _caster_instance_id,
		"boundary_cell_count": REQUIRED_BOUNDARY_CELL_COUNT,
		"center_cell": _center_cell,
	}


func reset(reason := "cleared") -> void:
	if _active or not reason.is_empty():
		_last_end_reason = reason
	_active = false
	_runtime_map_id = -1
	_caster_instance_id = 0
	_caster_ref = null
	_remaining_seconds = 0.0
	_boundary_snapshot = {}
	_center_cell = Vector2i.ZERO


func is_active() -> bool:
	return _active


func caster_actor() -> Node2D:
	if _caster_ref == null:
		return null
	var actor: Variant = _caster_ref.get_ref()
	return actor as Node2D if is_instance_valid(actor) and actor is Node2D else null


func advance(
	delta: float,
	current_runtime_map_id: int,
	player_center_ground_gu := Vector2.INF,
	player_combat_radius_gu := 0.0
) -> String:
	if not _active:
		return ""
	if current_runtime_map_id != _runtime_map_id:
		return _end("map_transition")
	if caster_actor() == null:
		return _end("caster_invalid")
	_remaining_seconds = maxf(0.0, _remaining_seconds - maxf(0.0, delta))
	if _remaining_seconds <= 0.0:
		return _end("duration_expired")
	if (
		player_center_ground_gu is Vector2
		and player_center_ground_gu != Vector2.INF
		and SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			_boundary_snapshot,
			player_center_ground_gu,
			maxf(0.0, player_combat_radius_gu)
		)
	):
		return _end("player_entered_boundary")
	return ""


func movement_candidate_blocked(
	_candidate_from_ground_gu: Vector2,
	candidate_to_ground_gu: Vector2,
	_actor_combat_radius_gu: float
) -> bool:
	if not _active:
		return false
	## The eight frozen cells are the complete ring around the sole interior
	## cell. They are a classic path barrier for the monster footpoint, not a
	## demand that the monster's full combat circle fit inside one grid cell.
	## Checking the final footpoint against the open center also catches a large
	## single-frame step that tunnels completely beyond the ring.
	return not _footpoint_strictly_inside_center(candidate_to_ground_gu)


func player_footprint_touches_boundary(
	player_center_ground_gu: Vector2,
	player_combat_radius_gu: float
) -> bool:
	return (
		_active
		and SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			_boundary_snapshot,
			player_center_ground_gu,
			maxf(0.0, player_combat_radius_gu)
		)
	)


func state_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"active": _active,
		"runtime_map_id": _runtime_map_id,
		"caster_instance_id": _caster_instance_id,
		"remaining_seconds": _remaining_seconds,
		"boundary_cell_count": int(
			_boundary_snapshot.get("geometry_cells_grid_steps", []).size()
		),
		"center_cell": _center_cell,
		"last_end_reason": _last_end_reason,
		"snapshot_id": str(_boundary_snapshot.get("snapshot_id", "")),
	}


func _footpoint_strictly_inside_center(center_ground_gu: Vector2) -> bool:
	var offset := center_ground_gu - Vector2(_center_cell)
	return (
		absf(offset.x) <= 0.5 + CONTACT_EPSILON_GU
		and absf(offset.y) <= 0.5 + CONTACT_EPSILON_GU
	)


func _end(reason: String) -> String:
	reset(reason)
	return reason


static func _failure(reason: String, details := {}) -> Dictionary:
	return {
		"valid": false,
		"reason": reason,
		"contract_id": CONTRACT_ID,
		"details": details,
	}


static func _canonical_boundary_topology(snapshot: Dictionary) -> Dictionary:
	var raw_cells: Variant = snapshot.get("geometry_cells_grid_steps", [])
	var raw_polygons: Variant = snapshot.get("polygons_ground_gu", [])
	if not raw_cells is Array or raw_cells.size() != REQUIRED_BOUNDARY_CELL_COUNT:
		return {"valid": false, "reason": "exactly_eight_boundary_cells_required"}
	if not raw_polygons is Array or raw_polygons.size() != REQUIRED_BOUNDARY_CELL_COUNT:
		return {"valid": false, "reason": "exactly_eight_boundary_polygons_required"}
	var unique_cells := {}
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483648, -2147483648)
	for raw_cell: Variant in raw_cells:
		if not raw_cell is Vector2i:
			return {"valid": false, "reason": "boundary_cell_type_invalid"}
		var cell := raw_cell as Vector2i
		if unique_cells.has(cell):
			return {"valid": false, "reason": "boundary_cells_must_be_unique"}
		unique_cells[cell] = true
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	if max_cell - min_cell != Vector2i(2, 2):
		return {"valid": false, "reason": "boundary_must_span_exact_3x3"}
	var center_cell := min_cell + Vector2i.ONE
	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var expected_cell := Vector2i(x, y)
			if expected_cell == center_cell:
				if unique_cells.has(expected_cell):
					return {"valid": false, "reason": "boundary_center_must_be_open"}
			elif not unique_cells.has(expected_cell):
				return {"valid": false, "reason": "boundary_ring_cell_missing"}
	return {"valid": true, "reason": "", "center_cell": center_cell}
