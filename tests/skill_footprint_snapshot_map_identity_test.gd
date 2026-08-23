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
	var context := SnapshotScript.make_absolute_runtime_context(
		1,
		Vector2(5, 5),
		Vector2(5, 5),
		Callable(self, "_ground_to_screen")
	)
	var snapshot := SnapshotScript.create_target_footprint(
		"wizard.lightning",
		"map_identity",
		Vector2(5, 5),
		0.6,
		0,
		context
	)
	assert(int(snapshot.get("runtime_map_id", -1)) == 1)

	# Same-map consumption passes.
	var same_map := SnapshotScript.validate(
		snapshot,
		{"expected_runtime_map_id": 1}
	)
	assert(bool(same_map.get("valid", false)), "same map must be accepted")

	# Cross-map consumption is rejected without auto-rewriting the map id.
	var cross_map := SnapshotScript.validate(
		snapshot,
		{"expected_runtime_map_id": 2}
	)
	assert(not bool(cross_map.get("valid", false)), "cross-map snapshot must be rejected")
	assert(
		str(cross_map.get("reason", "")) == "runtime_map_id_mismatch",
		"rejection reason must be runtime_map_id_mismatch"
	)
	assert(
		int(snapshot.get("runtime_map_id", -1)) == 1,
		"consumer must not rewrite the snapshot's runtime map id"
	)

	print("SKILL_FOOTPRINT_SNAPSHOT_MAP_IDENTITY_PASS map_A accepted, map_B rejected")
	get_tree().quit(0)
