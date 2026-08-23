extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


var _position_calls := 0
var _delta_calls := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var bad_position := Callable(self, "_bad_position_converter")
	var bad_context := Snapshot.make_absolute_runtime_context(
		1,
		Vector2(5, 5),
		Vector2(5, 5),
		bad_position
	)
	bad_context["ground_delta_gu_to_screen_delta_px"] = (
		Callable(self, "_counted_delta_converter")
	)
	var polygon := PackedVector2Array([
		Vector2(5, 5),
		Vector2(6, 5),
		Vector2(6, 6),
		Vector2(5, 6),
	])
	var offsets := Snapshot.project_ground_polygon_to_screen_offsets_px(
		polygon,
		Vector2(5, 5),
		bad_context
	)
	assert(
		offsets.is_empty(),
		"absolute projection failure must not yield a screen polygon"
	)
	assert(
		_position_calls == 1,
		"absolute path must attempt exactly one position conversion, got %d"
		% _position_calls
	)
	assert(
		_delta_calls == 0,
		"absolute projection failure must never fall through to the delta converter"
	)
	var valid_snapshot := Snapshot.create_circle(
		"wizard.hell_lightning",
		"converter-failure:1",
		Vector2(5, 5),
		3.0,
		16,
		Snapshot.make_absolute_runtime_context(
			1,
			Vector2(5, 5),
			Vector2(5, 5),
			Callable(self, "_conv")
		)
	)
	var invalid_converter_context := Snapshot.make_absolute_runtime_context(
		1,
		Vector2(5, 5),
		Vector2(5, 5),
		Callable()
	)
	var strict := Snapshot.validate_for_consumer(
		valid_snapshot,
		invalid_converter_context,
		Snapshot.VALIDATION_STRICT_V2
	)
	assert(not bool(strict.get("valid", false)))
	assert(
		str(strict.get("reason", ""))
		== "absolute_position_requires_position_converter",
		"strict entry must reject a missing position converter, got %s"
		% strict.get("reason", "")
	)
	print("SNAPSHOT_ABSOLUTE_CONVERTER_FAILURE_PASS")
	get_tree().quit(0)


func _bad_position_converter(_value: Vector2) -> Vector2:
	_position_calls += 1
	return Vector2.INF


func _counted_delta_converter(value: Vector2) -> Vector2:
	_delta_calls += 1
	return value
