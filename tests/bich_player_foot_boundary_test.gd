extends Node

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const PHONE_REPRODUCTION_POSITION := Vector2(
	-1296.47412109375, -631.391357421875
)
const ERROR_LIMIT_PX := 0.05


func _ready() -> void:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_province.runtime.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var raw_size: Array = loaded.runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var boundary := CollisionGeometry.map_inner_boundary_world(design_size)
	assert(boundary.size() == 4)

	assert(
		not CollisionGeometry.player_foot_inside_boundary(
			PHONE_REPRODUCTION_POSITION, design_size
		),
		"手机现场越界坐标未能复现人物脚底进入黑区"
	)
	var repaired := (
		CollisionGeometry.project_player_foot_inside_boundary(
			PHONE_REPRODUCTION_POSITION, design_size
		)
	)
	assert(
		repaired.distance_to(PHONE_REPRODUCTION_POSITION) > 8.0,
		"手机现场坐标没有把完整脚底移回可见地面"
	)
	assert(
		repaired.distance_to(PHONE_REPRODUCTION_POSITION) < 32.0,
		"脚底约束不应按整个人物外观过度内推"
	)
	_assert_foot_inside(repaired, design_size, "phone_reproduction")

	var center := Vector2.ZERO
	assert(
		CollisionGeometry.project_player_foot_inside_boundary(
			center, design_size
		).is_equal_approx(center),
		"地图内部合法位置不应被边界纠偏"
	)

	for side in boundary.size():
		var following := (side + 1) % boundary.size()
		var edge_midpoint := boundary[side].lerp(boundary[following], 0.5)
		var projected := (
			CollisionGeometry.project_player_foot_inside_boundary(
				edge_midpoint, design_size
			)
		)
		assert(
			projected.distance_to(edge_midpoint) > ERROR_LIMIT_PX,
			"第%d边仍允许人物脚底进入黑区" % side
		)
		assert(
			projected.distance_to(edge_midpoint) < 32.0,
			"第%d边脚底约束产生了整个人物外观级别的过度内推" % side
		)
		_assert_foot_inside(
			projected, design_size, "side_%d" % side
		)

	print(
		"BICH_PLAYER_FOOT_BOUNDARY_PASS "
		+ "contract=%s phone_before=%s phone_after=%s"
		% [
			CollisionGeometry.PLAYER_FOOT_BOUNDARY_CONTRACT_ID,
			PHONE_REPRODUCTION_POSITION,
			repaired,
		]
	)
	get_tree().quit(0)


func _assert_foot_inside(
	position: Vector2,
	design_size: Vector2i,
	label: String
) -> void:
	assert(
		CollisionGeometry.player_foot_inside_boundary(
			position, design_size
		),
		"%s 人物脚底未完整进入地面边界" % label
	)
	assert(
		CollisionGeometry.runtime_boundary_contains_world(
			position, design_size
		),
		"%s 人物脚点未进入运行时地面边界" % label
	)
