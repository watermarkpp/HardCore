extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ctx := Snapshot.make_absolute_runtime_context(
		"map_1",
		Vector2(5, 5),
		Vector2(5, 5),
		Callable(self, "_conv")
	)
	ctx["expected_runtime_map_id"] = "map_1"
	var base := Snapshot.create_circle(
		"wizard.hell_lightning",
		"strict:reject:1",
		Vector2(5, 5),
		3.0,
		16,
		ctx
	)
	var pseudo_v2: Dictionary = base.duplicate(true)
	pseudo_v2["schema_version"] = 2
	pseudo_v2.erase("coordinate_space")

	var effect := CasterSkillVisualEffect.new()
	effect.setup(
		Vector2(100, 100),
		"wizard.hell_lightning",
		72.0,
		0.8,
		Vector2.RIGHT,
		null,
		"",
		{
			"skill_footprint_snapshot": pseudo_v2,
			"snapshot_validation_policy": Snapshot.VALIDATION_STRICT_V2,
			"snapshot_validation_context": ctx,
		}
	)
	assert(
		str(effect.snapshot_visual_projection_metadata().get("snapshot_id", ""))
		== "",
		"pseudo-V2 snapshot must not enter a STRICT consumer"
	)
	assert(
		effect._skill_footprint_snapshot.is_empty(),
		"rejected snapshot must not be stored by the consumer"
	)
	var result := Snapshot.validate_for_consumer(
		pseudo_v2,
		ctx,
		Snapshot.VALIDATION_STRICT_V2
	)
	assert(not bool(result.get("valid", false)))
	assert(
		str(result.get("reason", "")).contains("missing_coordinate_space"),
		"rejection must carry a precise reason, got %s" % result.get("reason", "")
	)
	effect.free()
	print("SNAPSHOT_STRICT_CONSUMER_REJECTION_PASS")
	get_tree().quit(0)


func _conv(value: Vector2) -> Vector2:
	return value
