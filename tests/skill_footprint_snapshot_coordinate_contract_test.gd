extends Node

const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_gu
	) + Vector2(640, 320)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Absolute context snapshot carries runtime_map_id + projection origin.
	var absolute_context := SnapshotScript.make_absolute_runtime_context(
		"map_4",
		Vector2(12.5, -8.25),
		Vector2(12.5, -8.25),
		Callable(self, "_ground_to_screen")
	)
	var absolute_snapshot := SnapshotScript.create_directed_rectangle(
		"wizard.laser",
		"contract_test",
		Vector2(12.5, -8.25),
		Vector2.RIGHT,
		8.0,
		1.0,
		0.0,
		8.0,
		8.0,
		"",
		absolute_context
	)
	var absolute_validation := SnapshotScript.validate(absolute_snapshot)
	assert(bool(absolute_validation.get("valid", false)), "absolute snapshot must validate: %s" % absolute_validation.get("reason", ""))
	assert(int(absolute_snapshot.get("schema_version", 0)) == SnapshotScript.SCHEMA_VERSION)
	assert(
		str(absolute_snapshot.get("coordinate_space", ""))
		== SnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	)
	assert(str(absolute_snapshot.get("runtime_map_id", "")) == "map_4")
	assert(
		(absolute_snapshot.get("projection_origin_ground_gu", Vector2.ZERO) as Vector2)
		== Vector2(12.5, -8.25)
	)
	# Screen offsets are relative to the projection origin: origin maps to zero.
	var projected_absolute := (
		SnapshotScript.projected_polygon_screen_offset_px(absolute_snapshot)
	)
	assert(projected_absolute.size() == 4)
	var start_edge_midpoint := (projected_absolute[0] + projected_absolute[3]) * 0.5
	assert(
		start_edge_midpoint.length() < 0.001,
		"absolute snapshot origin (start edge midpoint) must project to screen offset zero"
	)

	# Local delta snapshot declares local space with zero origin.
	var local_context := SnapshotScript.make_local_delta_context(
		Callable(GroundUnitSpaceScript, "ground_delta_gu_to_screen_delta_px")
	)
	var local_snapshot := SnapshotScript.create_circle(
		"wizard.hell_lightning",
		"local_test",
		Vector2.ZERO,
		3.0,
		16,
		local_context
	)
	var local_validation := SnapshotScript.validate(local_snapshot)
	assert(bool(local_validation.get("valid", false)), "local snapshot must validate: %s" % local_validation.get("reason", ""))
	assert(
		str(local_snapshot.get("coordinate_space", ""))
		== SnapshotScript.COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU
	)
	assert(
		(local_snapshot.get("origin_ground_gu", Vector2.INF) as Vector2)
		== Vector2.ZERO
	)

	# Missing coordinate_space is rejected.
	var missing_space := absolute_snapshot.duplicate(true)
	missing_space.erase("coordinate_space")
	missing_space.erase("schema_version")
	assert(
		not bool(SnapshotScript.validate(missing_space).get("valid", false)),
		"missing coordinate_space must be rejected"
	)

	# Invalid coordinate_space is rejected.
	var invalid_space := absolute_snapshot.duplicate(true)
	invalid_space["coordinate_space"] = "screen_px"
	assert(
		not bool(SnapshotScript.validate(invalid_space).get("valid", false)),
		"invalid coordinate_space must be rejected"
	)

	# Non-finite coordinates are rejected.
	var non_finite := absolute_snapshot.duplicate(true)
	non_finite["origin_ground_gu"] = Vector2(NAN, 0.0)
	assert(
		not bool(SnapshotScript.validate(non_finite).get("valid", false)),
		"non-finite coordinates must be rejected"
	)

	# Screen offset polygon must not be marked as absolute screen position.
	assert(
		not bool(absolute_snapshot.get("polygon_screen_offset_px_is_absolute", false)),
		"screen offset fields must stay offset semantics"
	)

	print(
		"SKILL_FOOTPRINT_SNAPSHOT_COORDINATE_CONTRACT_PASS "
		+ "absolute=valid local=valid legacy_rejected=true"
	)
	get_tree().quit(0)
