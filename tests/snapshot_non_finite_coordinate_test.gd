extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CasterGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ctx := Snapshot.make_absolute_runtime_context(
		1,
		Vector2(5, 5),
		Vector2(5, 5),
		Callable(self, "_conv")
	)
	ctx["expected_runtime_map_id"] = 1
	var non_finite := Snapshot.create_circle(
		"wizard.hell_lightning",
		"non-finite:1",
		Vector2(5, 5),
		3.0,
		16,
		ctx
	).duplicate(true)
	non_finite["polygon_ground_gu"] = PackedVector2Array([
		Vector2.INF,
		Vector2(0, 0),
		Vector2(NAN, 0),
		Vector2(1, 1),
	])
	assert(
		not CasterGeometry.snapshot_strict_valid(non_finite, ctx),
		"non-finite coordinates must be rejected by the geometry consumer"
	)
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
			"skill_footprint_snapshot": non_finite,
			"snapshot_validation_policy": Snapshot.VALIDATION_STRICT_V2,
			"snapshot_validation_context": ctx,
		}
	)
	assert(
		effect._skill_footprint_snapshot.is_empty(),
		"non-finite snapshot must not create a visual core"
	)
	var result := Snapshot.validate_for_consumer(
		non_finite,
		ctx,
		Snapshot.VALIDATION_STRICT_V2
	)
	assert(
		str(result.get("reason", "")).contains("non_finite"),
		"non-finite rejection reason missing, got %s" % result.get("reason", "")
	)
	effect.free()
	print("SNAPSHOT_NON_FINITE_COORDINATE_PASS")
	get_tree().quit(0)


func _conv(value: Vector2) -> Vector2:
	return value
