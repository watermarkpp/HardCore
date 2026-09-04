extends Node

const CasterGeometry := preload(
	"res://scripts/skills/caster_spell_geometry.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


func _ready() -> void:
	_verify_cell_union_keeps_every_polygon()
	_verify_target_footprint_owns_visual_anchor()
	_verify_circle_and_sector_use_projected_cores()
	_verify_projectile_sweep_is_diagnostic_only()
	print(
		"CASTER_SNAPSHOT_VISUAL_PROJECTION_PASS: exact union polygons, "
		+ "target anchors, circle/sector cores and diagnostic sweeps"
	)
	get_tree().quit(0)


func _verify_cell_union_keeps_every_polygon() -> void:
	var snapshot := Snapshot.create_cell_union(
		"wizard.exploding_flame",
		"area:cell-union",
		Vector2(4.0, 5.0),
		[Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 7)]
	)
	var context := CasterGeometry.snapshot_visual_projection_context(
		snapshot,
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(4.0, 5.0))
	)
	assert(context.snapshot_visual_core_policy == (
		"all_exact_cell_polygons_no_bounding_shape"
	))
	assert(context.snapshot_projected_polygons_screen_offset_px.size() == 3)
	assert(context.snapshot_projected_polygons_local_to_effect_px.size() == 3)
	var effect := _effect_for(
		"wizard.exploding_flame",
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(4.0, 5.0)),
		context
	)
	assert(effect.formal_core_polygons_screen_offset_px().size() == 3)
	assert(effect.get_meta("formal_snapshot_polygon_count", 0) == 3)
	effect.free()


func _verify_target_footprint_owns_visual_anchor() -> void:
	var target_center_ground_gu := Vector2(3.25, -1.5)
	var snapshot := Snapshot.create_target_footprint(
		"wizard.lightning", "target:anchor", target_center_ground_gu, 0.35, 71
	)
	var context := CasterGeometry.snapshot_visual_projection_context(
		snapshot, Vector2.ZERO
	)
	var effect := _effect_for("wizard.lightning", Vector2.ZERO, context)
	assert(effect.global_position.is_equal_approx(
		GroundUnit.ground_delta_gu_to_screen_delta_px(target_center_ground_gu)
	))
	var metadata := effect.snapshot_visual_projection_metadata()
	assert(metadata.anchor_policy == "target_release_frame_footpoint")
	assert(metadata.visual_core_policy == (
		"target_anchor_and_footprint_no_extra_area"
	))
	assert(metadata.projected_polygon_count == 1)
	assert(not effect.has_meta("formal_snapshot_visual_core_contract"))
	effect.free()


func _verify_circle_and_sector_use_projected_cores() -> void:
	var circle := Snapshot.create_circle(
		"wizard.hell_lightning", "circle:core", Vector2(2.0, 3.0), 2.0
	)
	var sector := Snapshot.create_sector_arc(
		"warrior.half_moon", "sector:core", Vector2.ZERO,
		Vector2(0.6, 0.8), 1.5, PI * 0.5
	)
	for snapshot: Dictionary in [circle, sector]:
		var context := CasterGeometry.snapshot_visual_projection_context(
			snapshot, Vector2.ZERO
		)
		assert(context.snapshot_visual_core_policy == "projected_polygon_core")
		assert(context.snapshot_projected_polygons_screen_offset_px.size() == 1)
		assert(
			(context.snapshot_projected_polygons_screen_offset_px[0]
			as PackedVector2Array).size() >= 8
		)


func _verify_projectile_sweep_is_diagnostic_only() -> void:
	var sweep := Snapshot.create_swept_capsule_path(
		"wizard.fireball", "projectile:child:2",
		Vector2.ZERO, Vector2(1.0, 0.0), 0.1, 8,
		"wizard.fireball:projectile:parent", 2
	)
	var context := CasterGeometry.snapshot_visual_projection_context(
		sweep, Vector2.ZERO
	)
	assert(context.snapshot_visual_core_policy == (
		"diagnostic_only_do_not_force_capsule_visual"
	))
	var effect := _effect_for("wizard.lightning", Vector2.ZERO, context)
	assert(effect.formal_core_polygons_screen_offset_px().size() == 1)
	assert(not effect.has_meta("formal_snapshot_visual_core_contract"))
	effect.free()


func _effect_for(
	skill_id: String,
	position_screen_px: Vector2,
	context: Dictionary
) -> CasterSkillVisualEffect:
	var effect := CasterSkillVisualEffect.new()
	effect.setup(
		position_screen_px,
		skill_id,
		72.0,
		0.8,
		Vector2.DOWN,
		null,
		"",
		context
	)
	add_child(effect)
	return effect
