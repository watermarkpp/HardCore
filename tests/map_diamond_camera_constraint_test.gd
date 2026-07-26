extends Node

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const PUBLISHED_RUNTIME_MAPS := [
	"bich_province", "orc_tomb_1", "orc_tomb_2", "orc_tomb_3",
	"wooma_forest", "wooma_temple_1", "wooma_temple_2",
	"wooma_temple_3", "bich_mine_1", "bich_mine_2",
	"corpse_king_hall",
]


func _ready() -> void:
	var viewport_half := Vector2(640, 360)
	var covered_maps := 0
	var zoom_adjustments := 0
	for map_key: String in PUBLISHED_RUNTIME_MAPS:
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, map_key)
		var raw_size: Array = loaded.runtime.design.design_size
		var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var boundary: PackedVector2Array = CollisionGeometry.map_inner_boundary_world(
			size
		)
		var minimum_zoom := CameraConstraint.minimum_uniform_zoom(
			boundary, viewport_half
		)
		var zoom_value := maxf(1.06, minimum_zoom + 0.001)
		if zoom_value > 1.061:
			zoom_adjustments += 1
		var desired: Vector2 = boundary[1] + Vector2(900, -700)
		var constrained := CameraConstraint.constrain_center(
			size, viewport_half, Vector2.ONE * zoom_value, desired
		)
		assert(str(constrained.contract_id) == CameraConstraint.CONTRACT_ID)
		assert(constrained.ok, "%s has no legal camera center" % map_key)
		assert(CameraConstraint.viewport_inside_boundary(constrained),
			"%s constrained viewport still exposes off-map pixels" % map_key)
		assert(not Vector2(constrained.center).is_equal_approx(desired),
			"%s did not project an exterior camera request" % map_key)
		var stable := CameraConstraint.constrain_center(
			size, viewport_half, Vector2.ONE * zoom_value,
			Vector2(constrained.center)
		)
		assert(Vector2(stable.center).is_equal_approx(
			Vector2(constrained.center)
		), "%s legal camera center was not stable" % map_key)
		covered_maps += 1
	assert(covered_maps == PUBLISHED_RUNTIME_MAPS.size())
	assert(zoom_adjustments > 0,
		"small maps unexpectedly fit the logical viewport at zoom 1.06")
	var bich_current := CameraConstraint.constrain_center(
		Vector2i(80, 80), viewport_half, Vector2.ONE * 1.06,
		Vector2(2400, 900)
	)
	assert(bich_current.ok)
	assert(CameraConstraint.viewport_inside_boundary(bich_current))
	print(
		(
			"MAP_DIAMOND_CAMERA_CONSTRAINT_PASS contract=%s maps=%d "
			+ "small_map_zoom_adjustments=%d"
		)
		% [CameraConstraint.CONTRACT_ID, covered_maps, zoom_adjustments]
	)
	get_tree().quit(0)
