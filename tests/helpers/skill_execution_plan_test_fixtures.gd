class_name SkillExecutionPlanTestFixtures
extends RefCounted

## Q3-A fixture rig: builds frozen SkillCastRequests, frozen Snapshot V2 objects
## and canonical plan contexts for the shadow-parity / contract tests.

const SkillCastRequestScript := preload(
	"res://scripts/skills/skill_cast_request.gd"
)
const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const SpellGeometryScript := preload(
	"res://scripts/skills/caster_spell_geometry.gd"
)
const GroundUnitScript := preload("res://scripts/ground_unit_space.gd")
const SkillDataLoaderScript := preload(
	"res://scripts/skills/skill_data_loader.gd"
)
const Router := preload("res://scripts/skills/skill_runtime_router.gd")


static func _definition_timing(skill_id: String) -> Dictionary:
	return SkillDataLoaderScript.skill(skill_id).get("timing", {})


static func make_request(
	skill_id: String,
	rank := 1,
	level := 35,
	origin_tile := Vector2i.ZERO,
	facing := Vector2i.DOWN,
	target_context := {},
	resource_context := {},
	seed := 42
) -> Dictionary:
	return SkillCastRequestScript.create(
		skill_id,
		rank,
		level,
		origin_tile,
		facing,
		target_context,
		resource_context,
		seed
	)


static func default_target_context(
	has_target := true,
	target_tile := Vector2i(1, 0),
	release_id := "q3a:release:1"
) -> Dictionary:
	return {
		"has_target": has_target,
		"target_tile": target_tile,
		"release_id": release_id,
		"line_of_sight": true,
	}


static func default_resource_context(mana := 500) -> Dictionary:
	return {"mana": mana, "materials": {}}


static func amulet_resource_context(mana := 500) -> Dictionary:
	return {"mana": mana, "materials": {"amulet": 1}}


static func poison_resource_context(mana := 500) -> Dictionary:
	return {
		"mana": mana,
		"materials": {"grey_powder": 1, "yellow_powder": 1},
		"selected_material": "grey_powder",
	}


static func circle_snapshot(
	host: Node,
	skill_id: String,
	release_id: String,
	map_id: int,
	center_gu := Vector2(0, 0),
	radius_gu := 2.0
) -> Dictionary:
	var context := SnapshotScript.make_absolute_runtime_context(
		map_id,
		center_gu,
		center_gu,
		Callable(host, "_ground_to_screen")
	)
	return SnapshotScript.create_circle(
		skill_id,
		release_id,
		center_gu,
		radius_gu,
		16,
		context
	)


static func cell_union_snapshot(
	host: Node,
	skill_id: String,
	release_id: String,
	map_id: int,
	origin_gu: Vector2,
	cells: Array
) -> Dictionary:
	var typed_cells: Array[Vector2i] = []
	for raw_cell: Variant in cells:
		if raw_cell is Vector2i:
			typed_cells.append(raw_cell)
	var context := SnapshotScript.make_absolute_runtime_context(
		map_id,
		origin_gu,
		origin_gu,
		Callable(host, "_ground_to_screen")
	)
	return SpellGeometryScript.create_exact_cell_union_release_snapshot(
		skill_id,
		release_id,
		origin_gu,
		typed_cells,
		context
	)


static func canonical_context(
	map_id := 1,
	release_id := "q3a:release:1",
	caster_id := 0,
	target_id := 0,
	snapshot: Dictionary = {}
) -> Dictionary:
	var context := {
		"release_id": release_id,
		"runtime_map_id": map_id,
		"caster_runtime_id": caster_id,
		"target_runtime_id": target_id,
		"input_mode": "canonical_test",
	}
	if not snapshot.is_empty():
		context["canonical_snapshot"] = snapshot
	return context


static func build_canonical_plan(
	skill_id: String,
	rank := 1,
	level := 35,
	origin_tile := Vector2i.ZERO,
	facing := Vector2i.DOWN,
	target_context := {},
	resource_context := {},
	seed := 42,
	map_id := 1,
	release_id := "q3c:canonical:1",
	snapshot: Dictionary = {}
) -> Dictionary:
	## Q3-C: canonical plan builder for tests. Routes through the single formal
	## planner entry (SkillRuntimeRouter.build_canonical_plan) - the legacy
	## the legacy router entry was removed.
	var request := make_request(
		skill_id,
		rank,
		level,
		origin_tile,
		facing,
		target_context,
		resource_context,
		seed
	)
	return Router.build_canonical_plan(
		request,
		canonical_context(map_id, release_id, 0, 0, snapshot)
	)


static func build_canonical_presentation_plan(
	skill_id: String,
	rank := 3,
	level := 40,
	origin_screen_px := Vector2.ZERO,
	direction_screen_px := Vector2.RIGHT,
	target_position_screen_px := Vector2.ZERO,
	snapshot: Dictionary = {},
	map_id := 1
) -> Dictionary:
	## Q3-C: canonical plan for visual-contract tests. Routes through the
	## single formal planner entry and carries explicit presentation geometry
	## (origin/direction/target position) so the canonical node adapter places
	## visuals deterministically.
	var release_id := "q3c:visual:%s" % skill_id
	var request := make_request(
		skill_id,
		rank,
		level,
		Vector2i.ZERO,
		Vector2i.DOWN,
		default_target_context(true),
		default_resource_context(500),
		42
	)
	var context := canonical_context(map_id, release_id, 0, 0, snapshot)
	context["origin_screen_px"] = origin_screen_px
	context["direction_screen_px"] = direction_screen_px
	context["target_position_screen_px"] = target_position_screen_px
	context["snapshot_validation_context"] = {}
	context["line_strip_builder"] = Callable()
	context["effective_cells_builder"] = Callable()
	return Router.build_canonical_plan(request, context)


static func compare_field(
	label: String,
	legacy_value: Variant,
	canonical_value: Variant,
	differences: Array
) -> void:
	if str(legacy_value) != str(canonical_value):
		differences.append(
			"%s legacy=%s canonical=%s" % [
				label,
				str(legacy_value),
				str(canonical_value),
			]
		)
