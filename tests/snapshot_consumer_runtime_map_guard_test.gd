extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CasterGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var snapshot := Snapshot.create_circle(
		"wizard.hell_lightning",
		"map-guard:1",
		Vector2(5, 5),
		3.0,
		16,
		Snapshot.make_absolute_runtime_context(
			"map_A",
			Vector2(5, 5),
			Vector2(5, 5),
			Callable(self, "_conv")
		)
	)
	var cross_map_context := Snapshot.make_absolute_runtime_context(
		"map_B",
		Vector2(5, 5),
		Vector2(5, 5),
		Callable(self, "_conv")
	)
	cross_map_context["expected_runtime_map_id"] = "map_B"
	assert(
		not CasterGeometry.snapshot_strict_valid(snapshot, cross_map_context),
		"geometry consumer must reject a snapshot declared on another runtime map"
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
			"skill_footprint_snapshot": snapshot,
			"snapshot_validation_policy": Snapshot.VALIDATION_STRICT_V2,
			"snapshot_validation_context": cross_map_context,
		}
	)
	assert(
		effect._skill_footprint_snapshot.is_empty(),
		"cross-map snapshot must not enter a visual consumer"
	)
	var result := Snapshot.validate_for_consumer(
		snapshot,
		cross_map_context,
		Snapshot.VALIDATION_STRICT_V2
	)
	assert(
		str(result.get("reason", "")) == "runtime_map_id_mismatch",
		"cross-map rejection reason mismatch, got %s" % result.get("reason", "")
	)
	effect.free()
	print("SNAPSHOT_CONSUMER_RUNTIME_MAP_GUARD_PASS")
	get_tree().quit(0)


func _conv(value: Vector2) -> Vector2:
	return value
