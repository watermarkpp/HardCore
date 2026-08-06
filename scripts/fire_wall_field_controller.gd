class_name FireWallFieldController
extends Node2D


const GroundSkillVisualCellScript := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)
const GroundSkillEffectScript := preload("res://scripts/ground_effect.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const FIRE_WALL_SKILL_ID := "wizard.fire_wall"
const EXPANSION_EPSILON_GU := 0.05


var source_actor: Node2D
var stable_skill_id := ""
var raw_power := 0
var radius_gu := 0.5
var duration := 1.0
var tick_interval := 1.0
var damage_color := Color(0.45, 0.72, 1.0)
var runtime_tick_callback := Callable()
var runtime_damage_enabled := true
var _runtime_screen_to_ground_position_px := Callable()
var _tick_timer := 0.0
var _field_release_id_prefix := ""
var _release_id := ""
var _snapshot_id := ""
var _canonical_snapshot: Dictionary = {}
var _snapshot_validation_context: Dictionary = {}
var _canonical_snapshot_valid := false
var _runtime_map_id := -1
var _combat_spatial_index: SpatialIndexScript

var visual_cells: Array[GroundSkillVisualCellScript] = []

## Q2-C diagnostics (HC-P1-008 single-query close-out).
var tick_count := 0
var broadphase_query_count := 0
var candidate_count := 0
var max_candidate_count := 0
var controller_exact_test_count := 0
var visual_cell_exact_test_count := 0
var claim_attempt_count := 0
var claim_success_count := 0
var damage_application_count := 0
var duplicate_damage_count := 0
var group_scan_count := 0
var group_nodes_examined := 0
var snapshot_rebuild_count := 0
var spatial_index_unavailable_count := 0
var expired := false
var cancelled := false
var _rejection_reason := ""


func setup_fire_wall_field(
	source: Node2D,
	stable_skill_id_value: String,
	effect: Dictionary,
	positions: Array[Vector2],
	_coverage_cells: Array[Vector2i],
	_target_filters: Array[Callable],
	runtime_tick_callback_value: Callable,
	runtime_screen_to_ground_position_px: Callable,
	source_release_id := "",
	release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {},
	combat_spatial_index: SpatialIndexScript = null,
	runtime_map_id: int = -1
) -> void:
	source_actor = source
	stable_skill_id = stable_skill_id_value
	raw_power = maxi(0, int(effect.get("raw_power", 0)))
	radius_gu = maxf(0.0, float(effect.get("radius_gu", 0.5)))
	duration = maxf(0.1, float(effect.get("duration_seconds", 1)))
	tick_interval = maxf(
		0.05,
		float(effect.get("tick_interval_ms", 1000)) / 1000.0
	)
	damage_color = Color(
		float(effect.get("color_r", 0.45)),
		float(effect.get("color_g", 0.72)),
		float(effect.get("color_b", 1.0))
	)
	runtime_tick_callback = runtime_tick_callback_value
	runtime_damage_enabled = true
	_runtime_screen_to_ground_position_px = runtime_screen_to_ground_position_px
	_field_release_id_prefix = (
		source_release_id
		if not source_release_id.is_empty()
		else "wizard-fire_wall-controller-%d" % get_instance_id()
	)
	_release_id = source_release_id
	_canonical_snapshot = (
		release_snapshot
		if release_snapshot is Dictionary
		else {}
	)
	_snapshot_validation_context = (
		snapshot_validation_context
		if snapshot_validation_context is Dictionary
		else {}
	)
	_canonical_snapshot_valid = bool(
		SkillFootprintSnapshotScript.validate_for_consumer(
			_canonical_snapshot,
			_snapshot_validation_context,
			SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
		).get("valid", false)
	)
	_snapshot_id = str(
		_canonical_snapshot.get("snapshot_id", _release_id)
	)
	_runtime_map_id = int(
		_canonical_snapshot.get("runtime_map_id", runtime_map_id)
	)
	_combat_spatial_index = combat_spatial_index
	visual_cells = []

	var anchor_screen_px := (
		positions[0]
		if not positions.is_empty()
		else Vector2.ZERO
	)
	for index: int in range(positions.size()):
		var visual_cell := GroundSkillVisualCellScript.new()
		visual_cell.setup_ground_unit_effect(
			positions[index],
			raw_power,
			radius_gu,
			duration,
			damage_color,
			stable_skill_id,
			tick_interval,
			74.0,
			"%s:%s" % [_field_release_id_prefix, index],
			_canonical_snapshot,
			_snapshot_validation_context
		)
		visual_cell.configure_runtime_resolution(
			source_actor,
			Callable(self, "_ignore_visual_tick"),
			# Cells are pure presentation: no damage, no claim, no enemy query.
			false,
			Callable(),
			_runtime_screen_to_ground_position_px
		)
		visual_cell.cell_index = index
		visual_cell.canonical_snapshot_id = _snapshot_id
		visual_cell.cell_ground_offset = _ground_delta_between_screen_positions(
			anchor_screen_px,
			positions[index]
		)
		visual_cell.cell_screen_offset_px = (
			positions[index] - anchor_screen_px
		)
		add_child(visual_cell)
		visual_cells.append(visual_cell)


func _ignore_visual_tick(_target: EnemyActor, _raw_power: int) -> void:
	pass


func _physics_process(delta: float) -> void:
	if duration <= 0.0:
		expired = true
		queue_free()
		return
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_apply_field_tick()


func cancel() -> void:
	cancelled = true
	queue_free()


func _apply_field_tick() -> void:
	if visual_cells.is_empty() and not _canonical_snapshot_valid:
		return
	tick_count += 1
	if not _canonical_snapshot_valid:
		_rejection_reason = "invalid_snapshot"
		return
	if (
		_combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
	):
		spatial_index_unavailable_count += 1
		_rejection_reason = "spatial_index_unavailable"
		return
	broadphase_query_count += 1
	var candidates: Array[Dictionary] = (
		_combat_spatial_index.query_aabb_candidates(
			_runtime_map_id,
			_query_bounds_index_space(),
			EXPANSION_EPSILON_GU
		)
	)
	candidate_count += candidates.size()
	max_candidate_count = maxi(max_candidate_count, candidates.size())
	for candidate: Dictionary in candidates:
		var raw_node: Variant = candidate.get("node")
		if not raw_node is EnemyActor:
			continue
		var enemy := raw_node as EnemyActor
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		# One canonical 2x2 Snapshot-V2 exact test per candidate per tick.
		controller_exact_test_count += 1
		if not _canonical_target_is_inside(enemy):
			continue
		if not runtime_tick_callback.is_valid():
			continue
		if runtime_damage_enabled:
			claim_attempt_count += 1
			if not _claim_controller_tick(enemy):
				continue
			claim_success_count += 1
		damage_application_count += 1
		runtime_tick_callback.call(enemy, raw_power)
	for visual_cell: GroundSkillVisualCellScript in visual_cells:
		if is_instance_valid(visual_cell):
			visual_cell.queue_redraw()


func _canonical_target_is_inside(enemy: EnemyActor) -> bool:
	if not is_instance_valid(enemy):
		return false
	var enemy_ground_gu := _runtime_screen_to_ground_position(
		enemy.global_position
	)
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		_canonical_snapshot,
		enemy_ground_gu,
		enemy.combat_radius_gu
	)


func _claim_controller_tick(enemy: EnemyActor) -> bool:
	return GroundSkillEffectScript.claim_fire_wall_controller_tick(
		self,
		source_actor,
		stable_skill_id,
		tick_interval,
		enemy
	)


func _runtime_screen_to_ground_position(screen_position_px: Vector2) -> Vector2:
	if _runtime_screen_to_ground_position_px.is_valid():
		var ground_position_gu: Variant = (
			_runtime_screen_to_ground_position_px.call(screen_position_px)
		)
		if ground_position_gu is Vector2:
			return ground_position_gu
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_position_px
	)


func _ground_delta_between_screen_positions(
	origin_screen_position_px: Vector2,
	target_screen_position_px: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		target_screen_position_px - origin_screen_position_px
	)


func _snapshot_bounds_ground_gu(snapshot: Dictionary) -> Rect2:
	var min_gu := Vector2.INF
	var max_gu := -Vector2.INF
	for raw_polygon: Variant in snapshot.get("polygons_ground_gu", []):
		if raw_polygon is PackedVector2Array:
			for point: Vector2 in raw_polygon as PackedVector2Array:
				min_gu.x = minf(min_gu.x, point.x)
				min_gu.y = minf(min_gu.y, point.y)
				max_gu.x = maxf(max_gu.x, point.x)
				max_gu.y = maxf(max_gu.y, point.y)
	if not min_gu.is_finite() or not max_gu.is_finite():
		var origin := (
			snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2
		)
		return Rect2(origin, Vector2.ZERO)
	return Rect2(min_gu, max_gu - min_gu)


## The shared RuntimeCombatSpatialIndex stores actor positions in the index's
## coordinate space (the actor position provider / delta space). The canonical
## snapshot AABB is absolute map GU; project its corners through the map
## projection and back through the screen-delta conversion so the broadphase
## queries the same space the index lives in. Identity maps are unchanged.
func _query_bounds_index_space() -> Rect2:
	var canonical_bounds := _snapshot_bounds_ground_gu(_canonical_snapshot)
	var ground_to_screen: Callable = (
		_snapshot_validation_context.get(
			"ground_position_gu_to_screen_position_px", Callable()
		)
		if _snapshot_validation_context is Dictionary
		else Callable()
	)
	if not ground_to_screen.is_valid():
		return canonical_bounds
	var top_left_ground := canonical_bounds.position
	var bottom_right_ground := canonical_bounds.end
	var top_left_screen: Vector2 = (
		ground_to_screen.call(top_left_ground) as Vector2
	)
	var bottom_right_screen: Vector2 = (
		ground_to_screen.call(bottom_right_ground) as Vector2
	)
	var top_left_index := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			top_left_screen
		)
	)
	var bottom_right_index := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			bottom_right_screen
		)
	)
	return Rect2(top_left_index, bottom_right_index - top_left_index)


func fire_wall_controller_diagnostics() -> Dictionary:
	return {
		"controller_runtime_id": get_instance_id(),
		"snapshot_id": _snapshot_id,
		"runtime_map_id": _runtime_map_id,
		"visual_cell_count": visual_cells.size(),
		"tick_count": tick_count,
		"broadphase_query_count": broadphase_query_count,
		"candidate_count": candidate_count,
		"max_candidate_count": max_candidate_count,
		"controller_exact_test_count": controller_exact_test_count,
		"visual_cell_exact_test_count": visual_cell_exact_test_count,
		"claim_attempt_count": claim_attempt_count,
		"claim_success_count": claim_success_count,
		"damage_application_count": damage_application_count,
		"duplicate_damage_count": duplicate_damage_count,
		"group_scan_count": group_scan_count,
		"group_nodes_examined": group_nodes_examined,
		"snapshot_rebuild_count": snapshot_rebuild_count,
		"spatial_index_unavailable_count": spatial_index_unavailable_count,
		"expired": expired,
		"cancelled": cancelled,
		"rejection_reason": _rejection_reason,
	}


func runtime_diagnostics() -> Dictionary:
	## Back-compat wrapper used by pre-Q2-C tests; maps old counters onto the
	## new single-query contract (enemy_group_queries -> group scans = 0).
	return {
		"enemy_group_queries": group_scan_count,
		"candidate_checks": controller_exact_test_count,
		"damage_ticks": damage_application_count,
		"visual_cell_count": visual_cells.size(),
	}
