class_name SkillSpatialProjectionContract
extends RefCounted

## Machine-readable companion to the integration-owned spatial relationship
## matrix. It classifies every canonical 1.76 skill exactly once without
## changing its source-of-truth geometry, range, target cap or effect rules.

const CONTRACT_ID := "skills.spatial_projection.relationship_matrix.v1"
const SOURCE_RULESET_ID := "cn_mir2_176_vanilla_project_canonical_v1"
const SOURCE_MATRIX_ID := "docs.combat.spatial_projection_relationship_matrix.v1"

const RELEASE_CONTACT := "release_contact"
const DIRECTED_CORE := "directed_core"
const GROUND_EXACT := "ground_exact"
const PROJECTILE_SWEEP := "projectile_sweep"
const TARGET_FOOTPRINT := "target_footprint"
const MOVEMENT_SWEEP := "movement_sweep"
const ATTACHED_STATE := "attached_state"
const INHERITS_RELEASE := "inherits_release"
const NON_SPATIAL := "non_spatial"

const ALLOWED_RELATIONSHIP_TYPES: Array[String] = [
	RELEASE_CONTACT,
	DIRECTED_CORE,
	GROUND_EXACT,
	PROJECTILE_SWEEP,
	TARGET_FOOTPRINT,
	MOVEMENT_SWEEP,
	ATTACHED_STATE,
	INHERITS_RELEASE,
	NON_SPATIAL,
]

const SNAPSHOT_CREATE := "create_immutable_release_snapshot"
const SNAPSHOT_INHERIT := "inherit_host_release_snapshot"
const SNAPSHOT_ATTACHED := "attach_to_host_footpoint_without_damage_area"
const SNAPSHOT_NONE := "no_spatial_snapshot"

static var ENTRIES: Array[Dictionary] = [
	_entry(
		"warrior.basic_swordsmanship", INHERITS_RELEASE,
		"host_melee_release", "none", "inherit_host_facing",
		SNAPSHOT_INHERIT, "inherits_host_snapshot", []
	),
	_entry(
		"warrior.slaying_swordsmanship", INHERITS_RELEASE,
		"host_valid_melee_or_melee_skill_release", "none",
		"inherit_host_facing", SNAPSHOT_INHERIT,
		"inherits_host_snapshot", []
	),
	_entry(
		"warrior.thrusting", DIRECTED_CORE,
		"source_geometry_directed_rectangle_2_5_gu_by_1_gu",
		"caster_release_frame_footpoint", "frozen_release_facing",
		SNAPSHOT_CREATE, "effective_core_overlap", []
	),
	_entry(
		"warrior.half_moon", DIRECTED_CORE,
		"source_geometry_rotated_front_four_direction_arc_1_5_gu",
		"caster_release_frame_footpoint", "frozen_release_facing",
		SNAPSHOT_CREATE, "effective_core_overlap", []
	),
	_entry(
		"warrior.wild_rush", MOVEMENT_SWEEP,
		"source_geometry_atomic_caster_and_target_sweep_up_to_3_gu",
		"caster_and_target_release_frame_footpoints",
		"frozen_caster_to_target_direction", SNAPSHOT_CREATE,
		"movement_path_only", []
	),
	_entry(
		"warrior.fire_sword", INHERITS_RELEASE,
		"consuming_host_melee_release", "none", "inherit_host_facing",
		SNAPSHOT_INHERIT, "inherits_host_snapshot", []
	),

	_entry(
		"wizard.fireball", PROJECTILE_SWEEP,
		"source_geometry_projectile_path_and_projectile_radius",
		"caster_release_frame_footpoint", "frozen_launch_direction",
		SNAPSHOT_CREATE, "projectile_centerline_and_sweep_overlap", []
	),
	_entry(
		"wizard.repulsion_ring", GROUND_EXACT,
		"source_geometry_adjacent_ring_exact_cell_union",
		"caster_release_frame_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", [MOVEMENT_SWEEP]
	),
	_entry(
		"wizard.temptation_light", TARGET_FOOTPRINT,
		"selected_monster_release_frame_combat_footprint",
		"selected_target_release_frame_footpoint", "target_instance_lock",
		SNAPSHOT_CREATE, "target_footprint_only", []
	),
	_entry(
		"wizard.hellfire", DIRECTED_CORE,
		"source_geometry_terrain_truncated_rectangle_5_gu_by_1_gu",
		"caster_release_frame_footpoint", "frozen_release_facing",
		SNAPSHOT_CREATE, "effective_core_overlap", []
	),
	_entry(
		"wizard.lightning", TARGET_FOOTPRINT,
		"selected_target_release_frame_combat_footprint",
		"selected_target_release_frame_footpoint", "target_instance_lock",
		SNAPSHOT_CREATE, "target_footprint_only", []
	),
	_entry(
		"wizard.teleport", MOVEMENT_SWEEP,
		"validated_destination_player_combat_footprint",
		"validated_destination_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "destination_footprint_only", []
	),
	_entry(
		"wizard.great_fireball", PROJECTILE_SWEEP,
		"source_geometry_single_target_projectile_path_and_radius",
		"caster_release_frame_footpoint", "frozen_launch_direction",
		SNAPSHOT_CREATE, "projectile_centerline_and_sweep_overlap", []
	),
	_entry(
		"wizard.exploding_flame", GROUND_EXACT,
		"source_geometry_target_centered_3_by_3_exact_cell_union",
		"selected_ground_or_target_release_frame_footpoint",
		"no_damage_facing", SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"wizard.fire_wall", GROUND_EXACT,
		"source_geometry_frozen_2_by_2_exact_cell_union",
		"selected_ground_or_target_release_frame_footpoint",
		"no_damage_facing", SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"wizard.laser", DIRECTED_CORE,
		"source_geometry_terrain_truncated_rectangle_8_gu_by_1_gu",
		"caster_release_frame_footpoint", "frozen_release_facing",
		SNAPSHOT_CREATE, "effective_core_overlap", []
	),
	_entry(
		"wizard.hell_lightning", GROUND_EXACT,
		"source_geometry_radius_2_grid_step_ring_excluding_center_exact_union",
		"caster_release_frame_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"wizard.magic_shield", ATTACHED_STATE,
		"caster_combat_footprint_visual_anchor_only",
		"caster_current_footpoint", "follow_caster",
		SNAPSHOT_ATTACHED, "attached_anchor_only", []
	),
	_entry(
		"wizard.holy_word", TARGET_FOOTPRINT,
		"selected_undead_target_release_frame_combat_footprint",
		"selected_target_release_frame_footpoint", "target_instance_lock",
		SNAPSHOT_CREATE, "target_footprint_only", []
	),
	_entry(
		"wizard.ice_storm", GROUND_EXACT,
		"source_geometry_target_centered_3_by_3_exact_cell_union",
		"selected_ground_or_target_release_frame_footpoint",
		"no_damage_facing", SNAPSHOT_CREATE, "complete_overlap", []
	),

	_entry(
		"taoist.healing", TARGET_FOOTPRINT,
		"selected_self_or_friendly_release_frame_combat_footprint",
		"selected_target_release_frame_footpoint", "target_instance_lock",
		SNAPSHOT_CREATE, "target_footprint_only", []
	),
	_entry(
		"taoist.spiritual_warfare", NON_SPATIAL,
		"none", "none", "none", SNAPSHOT_NONE, "none", []
	),
	_entry(
		"taoist.poison", TARGET_FOOTPRINT,
		"selected_hostile_release_frame_combat_footprint",
		"selected_target_release_frame_footpoint", "target_instance_lock",
		SNAPSHOT_CREATE, "target_footprint_only", []
	),
	_entry(
		"taoist.soul_fire_talisman", PROJECTILE_SWEEP,
		"source_geometry_projectile_path_and_projectile_radius",
		"caster_release_frame_footpoint", "frozen_launch_direction",
		SNAPSHOT_CREATE, "projectile_centerline_and_sweep_overlap", []
	),
	_entry(
		"taoist.summon_skeleton", MOVEMENT_SWEEP,
		"source_geometry_nearest_valid_spawn_footprint_within_2_grid_steps",
		"validated_spawn_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "destination_footprint_only", [RELEASE_CONTACT]
	),
	_entry(
		"taoist.invisibility", ATTACHED_STATE,
		"caster_combat_footprint_visual_anchor_only",
		"caster_current_footpoint", "follow_caster",
		SNAPSHOT_ATTACHED, "attached_anchor_only", []
	),
	_entry(
		"taoist.mass_invisibility", GROUND_EXACT,
		"source_geometry_selected_point_3_by_3_exact_cell_union",
		"selected_ground_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"taoist.magic_defense", GROUND_EXACT,
		"source_geometry_selected_point_radius_3_grid_step_exact_cell_union",
		"selected_ground_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"taoist.defense", GROUND_EXACT,
		"source_geometry_selected_point_radius_3_grid_step_exact_cell_union",
		"selected_ground_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"taoist.revelation", TARGET_FOOTPRINT,
		"selected_player_or_monster_release_frame_combat_footprint",
		"selected_target_release_frame_footpoint", "target_instance_lock",
		SNAPSHOT_CREATE, "target_footprint_only", []
	),
	_entry(
		"taoist.entrapment", GROUND_EXACT,
		"source_geometry_canonical_3_by_3_boundary_exact_cell_union",
		"selected_ground_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"taoist.mass_healing", GROUND_EXACT,
		"source_geometry_selected_point_3_by_3_exact_cell_union",
		"selected_ground_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "complete_overlap", []
	),
	_entry(
		"taoist.summon_divine_beast", MOVEMENT_SWEEP,
		"source_geometry_nearest_valid_spawn_footprint_within_2_grid_steps",
		"validated_spawn_footpoint", "no_damage_facing",
		SNAPSHOT_CREATE, "destination_footprint_only", [DIRECTED_CORE]
	),
]


static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_data: Dictionary in ENTRIES:
		result.append(entry_data.duplicate(true))
	return result


static func entry(skill_id: String) -> Dictionary:
	for entry_data: Dictionary in ENTRIES:
		if str(entry_data.get("skill_id", "")) == skill_id:
			return entry_data.duplicate(true)
	return {}


static func relationship_type(skill_id: String) -> String:
	return str(entry(skill_id).get("relationship_type", ""))


static func requires_release_snapshot(skill_id: String) -> bool:
	return str(entry(skill_id).get("snapshot_policy", "")) == SNAPSHOT_CREATE


static func _entry(
	skill_id: String,
	relationship_type: String,
	formal_footprint: String,
	release_anchor: String,
	facing_policy: String,
	snapshot_policy: String,
	visual_damage_relation: String,
	secondary_relationships: Array
) -> Dictionary:
	return {
		"skill_id": skill_id,
		"relationship_type": relationship_type,
		"formal_footprint": formal_footprint,
		"release_anchor": release_anchor,
		"facing_policy": facing_policy,
		"snapshot_policy": snapshot_policy,
		"visual_damage_relation": visual_damage_relation,
		"secondary_relationships": secondary_relationships.duplicate(),
		"damage_space": (
			"none"
			if relationship_type in [NON_SPATIAL, ATTACHED_STATE]
			else "ground_gu_or_exact_grid_topology"
		),
		"screen_px_policy": "derived_projection_only_never_damage_input",
		"source_ruleset_id": SOURCE_RULESET_ID,
		"source_matrix_id": SOURCE_MATRIX_ID,
	}
