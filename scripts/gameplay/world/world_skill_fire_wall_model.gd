extends "res://scripts/gameplay/world/world_skill_effect_model.gd"


const SkillFootprintSnapshotScript = preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpaceScript = preload("res://scripts/ground_unit_space.gd")

const FIRE_WALL_SKILL_ID = "wizard.fire_wall"
const EXPANSION_EPSILON_GU = 0.05



var stable_skill_id = ""
var raw_power = 0
var radius_gu = 0.5
var duration = 1.0
var tick_interval = 1.0
var damage_color = Color(0.45, 0.72, 1.0)
var runtime_tick_callback = Callable()
var runtime_damage_enabled = true
var _runtime_screen_to_ground_position_px = Callable()
var _tick_timer = 0.0
var _field_release_id_prefix = ""
var _release_id = ""
var _snapshot_id = ""
var _canonical_snapshot: Dictionary = {}
var _snapshot_validation_context: Dictionary = {}
var _canonical_snapshot_valid = false
var _runtime_map_id = -1
var _combat_spatial_index: Object
## R1-A: the shared target-query service fronts every broadphase query.
var _target_query_service: Object
## PERF-1: caller-owned node scratch for the allocation-conscious envelope
## fast path (no candidate records on the hot tick).
var _target_node_scratch: Array[Object] = []
## FREEZE-P0.1: fail-closed projection diagnostics.
var missing_projection_rejection_count = 0

var visual_cells: Array[Object] = []

## Q2-C diagnostics (HC-P1-008 single-query close-out).
var tick_count = 0
var broadphase_query_count = 0
var candidate_count = 0
var max_candidate_count = 0
var controller_exact_test_count = 0
var visual_cell_exact_test_count = 0
var claim_attempt_count = 0
var claim_success_count = 0
var damage_application_count = 0
var duplicate_damage_count = 0
var group_scan_count = 0
var group_nodes_examined = 0
var snapshot_rebuild_count = 0
var spatial_index_unavailable_count = 0
var expired = false
var cancelled = false
var _rejection_reason = ""
## SOT wizard.fire_wall: field lifetime is real time. Wall-clock expiry keeps
## running across menu pause (get_tree().paused) and app background, so a
## recast on the same tile refreshes it instead of stacking frozen fields.
var expires_at_ticks_msec = -1
var refresh_count = 0
## Shared animation clock (ms): one advancing source per field; the 9 visual
## cells commit one batched frame without independent process callbacks.
var _anim_clock_ms = 0.0



const TargetQueryCore := preload("res://scripts/gameplay/world/world_skill_target_query.gd")


func setup_fire_wall_field(
	source: Object,
	stable_skill_id_value: String,
	effect: Dictionary,
	positions: Array[Vector2],
	_coverage_cells: Array[Vector2i],
	_target_filters: Array[Callable],
	runtime_tick_callback_value: Callable,
	runtime_screen_to_ground_position_px: Callable,
	source_release_id = "",
	release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {},
	combat_spatial_index: Object = null,
	runtime_map_id: int = -1
) -> void:
	# Propagate root world sorting through the logical field to each cell proxy.
	_presentation.set_cast_y_sort(self, true)
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
		else "wizard-fire_wall-controller-%d" % runtime_actor_id()
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
	# R1-A: every production target query enters through the shared service;
	# the snapshot gate below stays the exact authority for this shape.
	_target_query_service = TargetQueryCore.new(
		combat_spatial_index, _runtime_map_id, _actors
	)
	visual_cells = []

	var anchor_screen_px = (
		positions[0]
		if not positions.is_empty()
		else Vector2.ZERO
	)
	for index: int in range(positions.size()):
		var visual_cell: RefCounted = _presentation.create_fire_wall_cell(self, {
			"position_screen_px":positions[index], "raw_power":raw_power, "radius_gu":radius_gu,
			"duration":duration, "color":damage_color, "skill_id":stable_skill_id,
			"tick_interval":tick_interval, "visual_radius_px":74.0,
			"release_id":"%s:%s" % [_field_release_id_prefix,index],
			"cell_index":index, "canonical_snapshot_id":_snapshot_id,
			"cell_ground_offset":_ground_delta_between_screen_positions(anchor_screen_px,positions[index]),
			"cell_screen_offset_px":positions[index]-anchor_screen_px})
		if visual_cell == null:
			_world.fault("fire_wall_visual_cell_rejected", {"cell_index":index})
			return
		visual_cells.append(visual_cell)
	_arm_wall_clock_expiry()


func _arm_wall_clock_expiry() -> void:
	expires_at_ticks_msec = (
		_clock.now_msec() + int(round(duration * 1000.0))
	)


func refresh_field(
	effect: Dictionary,
	release_snapshot: Dictionary,
	snapshot_validation_context: Dictionary,
	source_release_id: String
) -> void:
	raw_power = maxi(0, int(effect.get("raw_power", raw_power)))
	duration = maxf(0.1, float(effect.get("duration_seconds", duration)))
	tick_interval = maxf(
		0.05,
		float(effect.get("tick_interval_ms", tick_interval * 1000.0)) / 1000.0
	)
	_release_id = (
		source_release_id if not source_release_id.is_empty() else _release_id
	)
	if release_snapshot is Dictionary and not release_snapshot.is_empty():
		_canonical_snapshot = release_snapshot
	if snapshot_validation_context is Dictionary:
		_snapshot_validation_context = snapshot_validation_context
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
	_arm_wall_clock_expiry()
	for visual_cell: Object in visual_cells:
		if is_instance_valid(visual_cell):
			visual_cell.refresh_lifetime(duration)
	refresh_count += 1


func _physics_process(delta: float) -> void:
	# Wall-clock expiry runs first: the field lifetime is real time (SOT),
	# so fields expired during menu pause or app background free on the next
	# simulated frame instead of surviving frozen.
	if (
		expires_at_ticks_msec >= 0
		and _clock.now_msec() >= expires_at_ticks_msec
	):
		expired = true
		_world.queue_cast_retirement(self)
		return
	_anim_clock_ms += delta * 1000.0
	if duration <= 0.0:
		expired = true
		_world.queue_cast_retirement(self)
		return
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_apply_field_tick()


func cancel() -> void:
	cancelled = true
	_world.queue_cast_retirement(self)


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
	var projection_valid_for_targets = (
		_runtime_map_id < 0
		or _runtime_screen_to_ground_position_px.is_valid()
	)
	if _runtime_map_id >= 0 and not projection_valid_for_targets:
		# FREEZE-P0.1: mapped exact-phase target conversion without a projection
		# must fail closed; the broadphase AABB (absolute snapshot) may still
		# run, but no candidate is ever exact-tested against fake deltas.
		missing_projection_rejection_count += 1
		_rejection_reason = str(
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		for visual_cell: Object in visual_cells:
			if is_instance_valid(visual_cell):
				visual_cell._presentation.redraw_cast(self)
		return
	# PERF-1: the controller broadphase uses the allocation-conscious
	# service envelope path (caller-owned node output, query-stamp dedup,
	# no candidate records). EXPANSION_EPSILON_GU keeps the exact candidate
	# universe the previous record query produced (bounds + epsilon + the
	# index max actor bounds); the canonical snapshot exact gate below is
	# unchanged. Candidate counters now reflect live nodes (the replaced
	# record path also counted dying registrations).
	_target_node_scratch.clear()
	if not _target_query_service.query_envelope_into(
		_snapshot_bounds_ground_gu(_canonical_snapshot),
		_target_node_scratch,
		true,
		EXPANSION_EPSILON_GU,
	):
		# Fail-closed parity with the previous direct-index behavior: a
		# rejected service query delivers nothing for this tick.
		_rejection_reason = "target_query_%s" % (
			_target_query_service.last_rejection_reason()
		)
		return
	candidate_count += _target_node_scratch.size()
	max_candidate_count = maxi(
		max_candidate_count, _target_node_scratch.size()
	)
	for enemy: Object in _target_node_scratch:
		if (
			not _actors.is_runtime_present(enemy)
			or _actors.is_queued_for_retirement(enemy)
			or not enemy.can_receive_damage()
		):
			continue
		# One canonical 3x3 Snapshot-V2 exact test per candidate per tick.
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
	# Sprite frames are submitted by the presentation batch. Tick damage does
	# not invalidate the cells' empty fallback drawing commands.


func _canonical_target_is_inside(enemy: Object) -> bool:
	if not _actors.is_runtime_present(enemy):
		return false
	if _runtime_map_id >= 0 and not _runtime_screen_to_ground_position_px.is_valid():
		missing_projection_rejection_count += 1
		_rejection_reason = str(
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		return false
	var enemy_ground_gu = _runtime_screen_to_ground_position(
		_actors.position_screen_px(enemy)
	)
	if not enemy_ground_gu.is_finite():
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		_canonical_snapshot,
		enemy_ground_gu,
		enemy.combat_radius_gu
	)


func _runtime_screen_to_ground_position(screen_position_px: Vector2) -> Vector2:
	if _runtime_screen_to_ground_position_px.is_valid():
		var ground_position_gu: Variant = (
			_runtime_screen_to_ground_position_px.call(screen_position_px)
		)
		if ground_position_gu is Vector2:
			return ground_position_gu
	if _runtime_map_id < 0:
		return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			screen_position_px
		)
	missing_projection_rejection_count += 1
	_rejection_reason = str(
		GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
	)
	return Vector2.INF


func _ground_delta_between_screen_positions(
	origin_screen_position_px: Vector2,
	target_screen_position_px: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		target_screen_position_px - origin_screen_position_px
	)


func _snapshot_bounds_ground_gu(snapshot: Dictionary) -> Rect2:
	var min_gu = Vector2.INF
	var max_gu = -Vector2.INF
	for raw_polygon: Variant in snapshot.get("polygons_ground_gu", []):
		if raw_polygon is PackedVector2Array:
			for point: Vector2 in raw_polygon as PackedVector2Array:
				min_gu.x = minf(min_gu.x, point.x)
				min_gu.y = minf(min_gu.y, point.y)
				max_gu.x = maxf(max_gu.x, point.x)
				max_gu.y = maxf(max_gu.y, point.y)
	if not min_gu.is_finite() or not max_gu.is_finite():
		var origin = (
			snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2
		)
		return Rect2(origin, Vector2.ZERO)
	return Rect2(min_gu, max_gu - min_gu)


func fire_wall_controller_diagnostics() -> Dictionary:
	return {
		"controller_runtime_id": runtime_actor_id(),
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
		"missing_projection_rejection_count": missing_projection_rejection_count,
		"expires_at_ticks_msec": expires_at_ticks_msec,
		"refresh_count": refresh_count,
		"anim_clock_ms": _anim_clock_ms,
		"animation_batch": _presentation.fire_wall_animation_diagnostics(self),
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

func _ready() -> void:
	_presentation.activate_fire_wall_cells(self, visual_cells)

func _process(_delta: float) -> void:
	_presentation.synchronize_fire_wall_cells(self, visual_cells, _anim_clock_ms)

func _claim_controller_tick(enemy: Object) -> bool:
	return _claims.claim_fire_wall_controller_tick(self, source_actor, stable_skill_id, tick_interval, enemy)
