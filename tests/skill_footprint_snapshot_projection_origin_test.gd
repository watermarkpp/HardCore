extends Node

const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const MAP_ORIGIN_SCREEN_PX := Vector2(640, 320)


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	# Canonical 64x32 isometric projection with a non-zero map origin.
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_gu
	) + MAP_ORIGIN_SCREEN_PX


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, 2).normalized()]:
		var origin := Vector2(23.5, -17.25)
		var context := SnapshotScript.make_absolute_runtime_context(
			4,
			origin,
			origin,
			Callable(self, "_ground_to_screen")
		)
		var snapshot := SnapshotScript.create_directed_rectangle(
			"wizard.laser",
			"projection_origin_%s" % direction,
			origin,
			direction,
			8.0,
			1.0,
			0.0,
			8.0,
			8.0,
			"actual",
			context
		)
		assert(bool(SnapshotScript.validate(snapshot).get("valid", false)))
		var projected := SnapshotScript.projected_polygon_screen_offset_px(
			snapshot
		)
		assert(projected.size() == 4, "directed rectangle must project four points")
		var expected_p0 := _ground_to_screen(
			origin + (Vector2(-direction.y, direction.x).normalized() * 0.5)
		) - _ground_to_screen(origin)
		assert(
			projected[0].distance_to(expected_p0) < 0.001,
			"absolute ground position must go through ground_position->screen_position minus projection origin, got %s expected %s"
			% [projected[0], expected_p0]
		)
		# The naive delta converter applied to the ABSOLUTE origin would not
		# produce zero; only projection-origin-relative offsets may.
		var naive_absolute_as_delta := (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(origin)
		)
		assert(
			not naive_absolute_as_delta.is_zero_approx(),
			"absolute positions must never be fed to the delta converter"
		)
		var start_edge_midpoint := (projected[0] + projected[3]) * 0.5
		assert(
			start_edge_midpoint.length() < 0.001,
			"snapshot origin (start edge midpoint) must project to zero offset"
		)
	print("SKILL_FOOTPRINT_SNAPSHOT_PROJECTION_ORIGIN_PASS non-zero map origin, 4 directions")
	get_tree().quit(0)
