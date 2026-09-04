extends Node

const WorldBackgroundScript := preload("res://scripts/world_background.gd")
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const TEST_SIZE := Vector2i(80, 80)


func _ready() -> void:
	var background := WorldBackgroundScript.new()
	add_child(background)
	var expected_tile_boundary := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(80.0, 0.0),
		Vector2(80.0, 80.0),
		Vector2(0.0, 80.0),
	])
	var expected_world_boundary := PackedVector2Array([
		Vector2(0.0, -1264.0),
		Vector2(2560.0, 16.0),
		Vector2(0.0, 1296.0),
		Vector2(-2560.0, 16.0),
	])

	var tile_boundary := CollisionGeometry.map_inner_boundary_tile_polygon(TEST_SIZE)
	assert(tile_boundary == expected_tile_boundary,
		"v2 CPU tile boundary is not the authored [0,size] ring")
	var world_boundary := background.editor_runtime_ground_boundary_world(TEST_SIZE)
	assert(world_boundary == expected_world_boundary,
		"v2 CPU world boundary does not match fixed 80x80 projection")
	assert(CollisionGeometry.map_inner_boundary_world(TEST_SIZE) == expected_world_boundary,
		"v2 collision world boundary diverges from fixed projection")

	var bich_guard := background._build_guard_band_node({
		"visual": {
			"design_size": [80, 80],
			"runtime_map_id": 910001,
			"guard_band_px": 1536,
		}
	})
	var generic_guard := background._build_guard_band_node({
		"visual": {
			"design_size": [80, 80],
			"runtime_map_id": 911001,
			"guard_band_px": 1536,
		}
	})
	assert(bich_guard is Polygon2D, "Bich guard node was not built")
	assert(generic_guard is Polygon2D, "generic guard node was not built")
	_assert_v2_guard_shader(bich_guard as Polygon2D, "Bich")
	_assert_v2_guard_shader(generic_guard as Polygon2D, "generic")

	print("WORLD_BACKGROUND_GROUND_V2_GUARD_CONTRACT_PASS boundary=0,size shaders=2")
	get_tree().quit(0)


func _assert_v2_guard_shader(guard: Polygon2D, label: String) -> void:
	var material := guard.material as ShaderMaterial
	assert(material != null, "%s guard has no ShaderMaterial" % label)
	var shader := material.shader
	assert(shader != null, "%s guard has no shader" % label)
	var code := shader.code
	assert(code.contains("max(-iso, vec2(0.0))"),
		"%s shader does not use the v2 lower boundary" % label)
	assert(code.contains("iso - design_size, vec2(0.0)"),
		"%s shader does not use the v2 upper boundary" % label)
	assert(not code.contains("vec2(-0.5)"),
		"%s shader retains the old half-cell lower boundary" % label)
	assert(not code.contains("design_size - vec2(0.5)"),
		"%s shader retains the old half-cell upper boundary" % label)
