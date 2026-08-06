class_name FireWallFieldController
extends Node2D


const GroundSkillVisualCellScript := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)


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

var visual_cells: Array[GroundSkillVisualCellScript] = []

var _enemy_group_queries := 0
var _candidate_checks := 0
var _damage_ticks := 0


func setup_fire_wall_field(
	source: Node2D,
	stable_skill_id_value: String,
	effect: Dictionary,
	positions: Array[Vector2],
	_coverage_cells: Array[Vector2i],
	target_filters: Array[Callable],
	runtime_tick_callback_value: Callable,
	runtime_screen_to_ground_position_px: Callable,
	source_release_id := "",
	release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {}
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
	visual_cells = []

	for index: int in range(positions.size()):
		var target_filter := Callable()
		if index < target_filters.size():
			target_filter = target_filters[index]
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
			release_snapshot,
			snapshot_validation_context
		)
		visual_cell.configure_runtime_resolution(
			source_actor,
			Callable(self, "_ignore_visual_tick"),
			# Fire-wall controller owns runtime ticking and tick claims; keep
			# cells as visual-only so they don't race the controller.
			false,
			target_filter,
			_runtime_screen_to_ground_position_px
		)
		add_child(visual_cell)
		visual_cells.append(visual_cell)


func _ignore_visual_tick(_target: EnemyActor, _raw_power: int) -> void:
	pass


func _physics_process(delta: float) -> void:
	if duration <= 0.0:
		queue_free()
		return
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_apply_field_tick()


func _apply_field_tick() -> void:
	if visual_cells.is_empty():
		return
	_enemy_group_queries += 1
	var all_nodes: Array = get_tree().get_nodes_in_group("enemies")
	for node: Node in all_nodes:
		if (
			not is_instance_valid(node)
			or not node is EnemyActor
			or node.is_queued_for_deletion()
		):
			continue
		var enemy := node as EnemyActor
		_candidate_checks += 1
		for cell: GroundSkillVisualCellScript in visual_cells:
			if not is_instance_valid(cell):
				continue
			var is_hit := cell.runtime_target_is_inside(enemy)
			if not is_hit:
				continue
			cell.queue_redraw()
			if not runtime_tick_callback.is_valid():
				break
			if not _claim_cell_tick(cell, enemy):
				break
			_damage_ticks += 1
			runtime_tick_callback.call(enemy, raw_power)
			break
		for visual_cell in visual_cells:
			if is_instance_valid(visual_cell):
				visual_cell.queue_redraw()


func _claim_cell_tick(
	cell: GroundSkillVisualCellScript,
	enemy: EnemyActor
) -> bool:
	return (
		not runtime_damage_enabled
		or cell.claim_runtime_tick(enemy)
	)


func runtime_diagnostics() -> Dictionary:
	return {
		"enemy_group_queries": _enemy_group_queries,
		"candidate_checks": _candidate_checks,
		"damage_ticks": _damage_ticks,
		"visual_cell_count": visual_cells.size(),
	}
