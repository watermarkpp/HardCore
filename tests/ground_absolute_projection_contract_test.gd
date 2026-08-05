extends Node

const CasterGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const MapEditorRuntimeBridgeScript := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

var _runtime: Dictionary = {}


func _ready() -> void:
	_runtime = MapEditorRuntimeBridgeScript.load_map(
		MapEditorRuntimeBridgeScript.BICH_MAP_ID
	)
	assert(not _runtime.is_empty(), "missing runtime map data for BICH")
	_verify_runtime_map_absolute_projection_for_target_anchor()
	_verify_visual_context_from_plan_reads_callback_from_plan()
	_verify_fallback_delta_projection_compat()
	print(
		"GROUND_ABSOLUTE_PROJECTION_CONTRACT_PASS: "
		+ "runtime map contract re-projects absolute ground anchors"
	)
	get_tree().quit(0)


func _verify_runtime_map_absolute_projection_for_target_anchor() -> void:
	var fallback_origin_ground_gu := Vector2(30.0, 39.5)
	var fallback_origin_screen_px := (
		_runtime_ground_gu_to_screen_position_px(fallback_origin_ground_gu)
	)
	var target_center_ground_gu := Vector2(42.0, 38.0)
	var snapshot := Snapshot.create_target_footprint(
		"wizard.lightning",
		"runtime:ground:absolute:target",
		target_center_ground_gu,
		0.35,
		71
	)
	var context := CasterGeometry.snapshot_visual_projection_context(
		snapshot,
		fallback_origin_screen_px,
		Callable(self, "_runtime_ground_gu_to_screen_position_px")
	)
	var expected_anchor_screen_px := (
		_runtime_ground_gu_to_screen_position_px(target_center_ground_gu)
	)
	var legacy_anchor_screen_px := (
		GroundUnit.ground_delta_gu_to_screen_delta_px(target_center_ground_gu)
	)
	assert(context.snapshot_anchor_screen_px.is_equal_approx(
		expected_anchor_screen_px
	))
	assert(not context.snapshot_anchor_screen_px.is_equal_approx(
		legacy_anchor_screen_px
	))
	assert(context.coordinate_space == "runtime_map_absolute_ground_gu")
	assert(not context.absolute_ground_reprojected_as_delta)
	assert(context.snapshot_anchor_offset_from_effect_px.is_equal_approx(
		expected_anchor_screen_px - fallback_origin_screen_px
	))
	assert(context.snapshot_coordinate_space == "runtime_map_absolute_ground_gu")


func _verify_visual_context_from_plan_reads_callback_from_plan() -> void:
	var fallback_origin_ground_gu := Vector2(30.0, 39.5)
	var fallback_origin_screen_px := (
		_runtime_ground_gu_to_screen_position_px(fallback_origin_ground_gu)
	)
	var target_center_ground_gu := Vector2(44.0, 39.0)
	var snapshot := Snapshot.create_target_footprint(
		"wizard.laser",
		"runtime:ground:absolute:context",
		target_center_ground_gu,
		0.35,
		71
	)
	var plan := {
		"canonical_geometry_contract": CasterGeometry.CONTRACT_ID,
		"skill_footprint_snapshot": snapshot,
		"geometry_origin_screen_px": fallback_origin_screen_px,
		"geometry_screen_points_px": [Vector2.ZERO],
		"geometry_grid_cells": [Vector2i.ZERO],
		"visual_geometry_context": {},
		"ground_gu_to_screen_position_px": Callable(self, "_runtime_ground_gu_to_screen_position_px"),
	}
	var context := CasterGeometry.visual_context_from_plan(
		"wizard.laser",
		plan,
		fallback_origin_screen_px
	)
	assert(context.coordinate_space == "runtime_map_absolute_ground_gu")
	assert(context.snapshot_anchor_screen_px.is_equal_approx(
		_runtime_ground_gu_to_screen_position_px(target_center_ground_gu)
	))


func _verify_fallback_delta_projection_compat() -> void:
	var fallback_origin_screen_px := Vector2(120.0, 80.0)
	var snapshot := Snapshot.create_circle(
		"wizard.lightning",
		"legacy-delta:fallback",
		Vector2(2.0, 3.0),
		0.5
	)
	var context := CasterGeometry.snapshot_visual_projection_context(
		snapshot,
		fallback_origin_screen_px
	)
	# Without a valid map projection callable, absolute ground coordinates
	# cannot be converted. The anchor now falls back to the caller-provided
	# screen origin (fallback_origin_screen_px) instead of wrongly treating
	# absolute GU as a screen delta.
	assert(context.snapshot_anchor_screen_px.is_equal_approx(
		fallback_origin_screen_px
	))
	assert(context.absolute_ground_reprojected_as_delta)
	assert(context.coordinate_space == "ground_delta_gu")
	assert(context.snapshot_coordinate_space == "ground_delta_gu")
	assert(context.screen_anchor_source == "runtime_fallback_origin")


func _runtime_ground_gu_to_screen_position_px(
	ground_position_gu: Vector2
) -> Vector2:
	return MapEditorRuntimeBridgeScript.ground_position_gu_to_screen_position_px(
		_runtime,
		ground_position_gu
	)
