extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillBeamVisualEffect := preload(
	"res://scripts/caster_skill_beam_visual_effect.gd"
)
const CasterSkillAnimationPlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)
const CasterSpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const CasterSkillGeometryService := preload("res://scripts/skills/skill_geometry_service.gd")
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")

const SKILL_ID := "wizard.laser"
const DECLARED_LENGTH_GU := 8.0

var _wall_cell: Vector2i = Vector2i.ZERO


func _context() -> Dictionary:
	return {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 500,
		"magic_stat_roll": 30,
		"spiritual_stat_roll": 30,
		"random_0_to_10": 0,
	}


func _beam_profile() -> Dictionary:
	var profile := CasterSkillVisualRegistry.profile(SKILL_ID).duplicate(true)
	profile["enable_beam_visual"] = true
	return profile


func _is_wall_cell(cell: Vector2i) -> bool:
	return cell == _wall_cell


func _compute_wall_cut_cells(direction_cell: Vector2i) -> Array[Vector2i]:
	var definition := SkillDataLoader.skill(SKILL_ID)
	var geometry: Dictionary = definition.get("geometry", {})
	var raw_cells: Array = CasterSkillGeometryService.cells(
		definition,
		Vector2i.ZERO,
		direction_cell
	)
	assert(raw_cells.size() >= 5)
	assert(raw_cells[4] is Vector2i)
	_wall_cell = raw_cells[4] as Vector2i
	var effective_cells := CasterSpellGeometry.effective_cells(
		SKILL_ID,
		geometry,
		raw_cells,
		Callable(self, "_is_wall_cell")
	)
	return effective_cells


func _build_wall_cutoff_snapshot(
	direction_screen_px: Vector2,
	direction_cell: Vector2i
) -> Dictionary:
	var effective_cells := _compute_wall_cut_cells(direction_cell)
	var actual_length_gu := float(effective_cells.size())
	assert(actual_length_gu > 0.0 and actual_length_gu < DECLARED_LENGTH_GU)
	var direction_ground := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction_screen_px
	).normalized()
	var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
		SKILL_ID,
		"beam_runtime_terrain_cutoff",
		Vector2.ZERO,
		direction_ground,
		actual_length_gu,
		1.0,
		0.0,
		DECLARED_LENGTH_GU,
		actual_length_gu
	).duplicate()
	snapshot["declared_axis_screen_length_px"] = (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * DECLARED_LENGTH_GU
		).length()
	)
	snapshot["declared_effect_length_gu"] = DECLARED_LENGTH_GU
	snapshot["resolved_effect_length_gu"] = actual_length_gu
	return snapshot


func _spawn_beam(snapshot: Dictionary, direction_screen_px: Vector2) -> CasterSkillBeamVisualEffect:
	var profile := _beam_profile()
	var effect := CasterSkillVisualFactory.create(profile)
	assert(effect is CasterSkillBeamVisualEffect)
	effect.setup(
		Vector2.ZERO,
		SKILL_ID,
		72.0,
		0.8,
		direction_screen_px,
		null,
		"",
		{
			"skill_footprint_snapshot": snapshot,
			"visual_profile": profile,
		}
	)
	add_child(effect)
	return effect as CasterSkillBeamVisualEffect


func _ready() -> void:
	var resolved_plan := CasterSkillRuntime.resolve(SKILL_ID, _context())
	assert(resolved_plan.get("visual", {}).get("role", "") == "line_effect")
	var profile := _beam_profile()
	assert(profile.get("visual_type", "") == "beam")
	assert(profile.get("enable_beam_visual", false) == true)

	var direction_screen_px: Vector2 = DirectionSpace.projected_screen_direction_px(2) # east
	var direction_cell: Vector2i = Vector2i.RIGHT
	var snapshot := _build_wall_cutoff_snapshot(
		direction_screen_px,
		direction_cell
	)
	var declared_px := float(snapshot.get("declared_axis_screen_length_px", 0.0))
	var actual_px := float(snapshot.get("axis_screen_length_px", 0.0))
	assert(declared_px > actual_px)
	var effect := _spawn_beam(snapshot, direction_screen_px)
	await get_tree().process_frame
	var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
	assert(sprite != null)
	var fitted_length := sprite.fitted_visual_forward_extent(direction_screen_px.normalized())
	assert(is_equal_approx(fitted_length, actual_px))
	assert(int(snapshot.get("resolved_effect_length_gu", 0.0)) == 4)
	var metadata := effect.beam_debug_metadata()
	assert(metadata.get("length_source", "") == "actual_length")
	assert(is_equal_approx(
		effect._beam_length_px,
		actual_px
	))

	print(
		"[SkillVisual][BeamTerrain] declared=%s resolved=%s geometry_source=%s"
		% [
			declared_px,
			actual_px,
			str(metadata.get("geometry_driven_scale", false)).to_lower()
		]
	)
	print("BEAM_RUNTIME_TERRAIN_CUTOFF_TEST_PASS")
	effect.queue_free()
	get_tree().quit(0)
