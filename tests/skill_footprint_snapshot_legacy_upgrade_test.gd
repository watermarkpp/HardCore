extends Node

const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Legacy builder entry (no context) keeps V1 semantics.
	var legacy := SnapshotScript.create_directed_rectangle(
		"wizard.laser",
		"legacy_test",
		Vector2(10, -4),
		Vector2.RIGHT,
		8.0,
		1.0
	)
	assert(int(legacy.get("schema_version", 0)) == SnapshotScript.LEGACY_SCHEMA_VERSION)
	assert(
		str(legacy.get("coordinate_space", ""))
		== SnapshotScript.COORDINATE_SPACE_LEGACY_GROUND_GU
	)
	assert(
		not bool(SnapshotScript.validate(legacy).get("valid", false)),
		"ambiguous legacy snapshot must be rejected by the strict validator"
	)

	# No explicit context -> upgrade must fail.
	var no_context := SnapshotScript.upgrade_legacy_snapshot(legacy, {})
	assert(no_context.is_empty(), "upgrade without explicit context must fail")

	# Explicit absolute context -> upgrade succeeds with V2 identity.
	var absolute_context := SnapshotScript.make_absolute_runtime_context(
		4,
		Vector2(10, -4),
		Vector2(10, -4),
		Callable(self, "_ground_to_screen")
	)
	var upgraded_absolute := SnapshotScript.upgrade_legacy_snapshot(
		legacy,
		absolute_context
	)
	assert(not upgraded_absolute.is_empty(), "absolute upgrade must succeed")
	assert(
		int(upgraded_absolute.get("schema_version", 0))
		== SnapshotScript.SCHEMA_VERSION
	)
	assert(
		str(upgraded_absolute.get("coordinate_space", ""))
		== SnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	)
	assert(int(upgraded_absolute.get("runtime_map_id", -1)) == 4)
	assert(str(upgraded_absolute.get("migration_source", "")) == "legacy_v1")
	assert(bool(SnapshotScript.validate(upgraded_absolute).get("valid", false)))

	# Explicit local-delta context -> upgrade succeeds with zero origin.
	var local_context := SnapshotScript.make_local_delta_context(
		Callable(GroundUnitSpaceScript, "ground_delta_gu_to_screen_delta_px")
	)
	var upgraded_local := SnapshotScript.upgrade_legacy_snapshot(
		legacy,
		local_context
	)
	assert(not upgraded_local.is_empty(), "local upgrade must succeed")
	assert(
		str(upgraded_local.get("coordinate_space", ""))
		== SnapshotScript.COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU
	)
	assert(
		(upgraded_local.get("origin_ground_gu", Vector2.INF) as Vector2)
		== Vector2.ZERO
	)
	assert(bool(SnapshotScript.validate(upgraded_local).get("valid", false)))

	print("SKILL_FOOTPRINT_SNAPSHOT_LEGACY_UPGRADE_PASS context required, V2 identity preserved")
	get_tree().quit(0)
