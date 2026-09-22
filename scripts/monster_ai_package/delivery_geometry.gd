class_name MonsterDeliveryGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

## Monster-only adapter for legacy integer-cell attacks. Snapshot V2 cell
## unions consume absolute map cells: origin_ground_gu is projection metadata
## and never translates geometry_cells_grid_steps.

const CONTRACT_ID := "monster.delivery.geometry.absolute_cells.v1"


static func absolute_cell_for_ground_position(ground_position_gu: Vector2) -> Vector2i:
	if not ground_position_gu.is_finite():
		return Vector2i(-2147483648, -2147483648)
	# Snapshot V2 represents an integer cell as a square centred on that integer
	# (cell +/- 0.5 GU). Quantize to the nearest integer centre so the source or
	# target point used to choose a cell is always inside that cell. roundi also
	# gives the project's established, symmetric half-GU rule for negative maps.
	return Vector2i(roundi(ground_position_gu.x), roundi(ground_position_gu.y))


static func canonical_step_for_ground_delta(delta_ground_gu: Vector2) -> Vector2i:
	if (
		not delta_ground_gu.is_finite()
		or delta_ground_gu.length_squared()
		<= CombatDirectionSpaceScript.EPSILON_GU * CombatDirectionSpaceScript.EPSILON_GU
	):
		return Vector2i.ZERO
	return CombatDirectionSpaceScript.canonical_grid_step(
		CombatDirectionSpaceScript.direction_index_for_ground_delta_gu(
			delta_ground_gu
		)
	)


static func directional_cells(
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	step_count: int,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var origin_cell := absolute_cell_for_ground_position(origin_ground_gu)
	var step := canonical_step_for_ground_delta(direction_ground_gu)
	if origin_cell.x == -2147483648 or step == Vector2i.ZERO or step_count <= 0:
		return result
	for distance_steps: int in range(1, step_count + 1):
		result.append(origin_cell + step * distance_steps)
	return result


static func target_cell(target_ground_gu: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cell := absolute_cell_for_ground_position(target_ground_gu)
	if cell.x != -2147483648:
		result.append(cell)
	return result


static func create_directional_cell_snapshot(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	step_count: int,
	coordinate_context: Dictionary,
) -> Dictionary:
	var cells := directional_cells(
		origin_ground_gu,
		direction_ground_gu,
		step_count,
	)
	if skill_id.is_empty() or release_id.is_empty() or cells.is_empty():
		return {}
	return SkillFootprintSnapshotScript.create_cell_union(
		skill_id,
		release_id,
		origin_ground_gu,
		cells,
		coordinate_context,
	)


static func create_target_cell_snapshot(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	coordinate_context: Dictionary,
) -> Dictionary:
	var cells := target_cell(target_ground_gu)
	if skill_id.is_empty() or release_id.is_empty() or cells.is_empty():
		return {}
	return SkillFootprintSnapshotScript.create_cell_union(
		skill_id,
		release_id,
		origin_ground_gu,
		cells,
		coordinate_context,
	)
