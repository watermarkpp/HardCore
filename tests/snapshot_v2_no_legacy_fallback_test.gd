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
	var invalid_v2 := Snapshot.create_circle(
		"wizard.hell_lightning",
		"v2:no-fallback:1",
		Vector2(5, 5),
		3.0,
		16,
		ctx
	).duplicate(true)
	invalid_v2.erase("runtime_map_id")
	assert(int(invalid_v2.get("schema_version", 0)) == 2)

	var before := Snapshot.legacy_snapshot_validation_count
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
			"skill_footprint_snapshot": invalid_v2,
			"snapshot_validation_policy": Snapshot.VALIDATION_STRICT_V2,
			"snapshot_validation_context": ctx,
		}
	)
	assert(
		effect._skill_footprint_snapshot.is_empty(),
		"invalid V2 must be rejected without a legacy fallback"
	)
	var strict := Snapshot.validate_for_consumer(
		invalid_v2,
		ctx,
		Snapshot.VALIDATION_STRICT_V2
	)
	assert(not bool(strict.get("valid", false)))
	assert(
		not bool(strict.get("legacy_used", true)),
		"strict failure must never report legacy_used"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == before,
		"V2 strict failure must not increment the legacy validation counter"
	)
	effect.free()
	print("SNAPSHOT_V2_NO_LEGACY_FALLBACK_PASS")
	get_tree().quit(0)


func _conv(value: Vector2) -> Vector2:
	return value
