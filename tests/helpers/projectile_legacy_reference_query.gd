class_name ProjectileLegacyReferenceQuery
extends RefCounted

## Q2-A: test-only legacy reference for the pre-BroadPhase projectile hot path.
## It replicates the old per-step loop:
##   for enemy in scene-order array:
##       exact Snapshot-V2 intersection (release range gate + segment capsule)
##       -> first hit wins; otherwise null.
## Production code must never call this helper.

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Projectile := preload("res://scripts/skill_projectile.gd")


static func old_path_first_hit(
	release_snapshot: Dictionary,
	segment_snapshot: Dictionary,
	segment_start_screen_px: Vector2,
	segment_end_screen_px: Vector2,
	enemies: Array,
	expected_context: Dictionary,
	projectile_radius_gu: float
) -> EnemyActor:
	for raw_enemy: Variant in enemies:
		if not raw_enemy is EnemyActor:
			continue
		var enemy := raw_enemy as EnemyActor
		if enemy.is_queued_for_deletion() or not is_instance_valid(enemy):
			continue
		if old_exact_intersects(
			release_snapshot,
			segment_snapshot,
			segment_start_screen_px,
			segment_end_screen_px,
			enemy,
			expected_context,
			projectile_radius_gu
		):
			return enemy
	return null


static func old_exact_intersects(
	release_snapshot: Dictionary,
	segment_snapshot: Dictionary,
	segment_start_screen_px: Vector2,
	segment_end_screen_px: Vector2,
	enemy: EnemyActor,
	expected_context: Dictionary,
	projectile_radius_gu: float
) -> bool:
	var enemy_center_ground_gu := (
		GroundUnit.screen_delta_px_to_ground_delta_gu(
			enemy.global_position
		)
	)
	if (
		bool(Snapshot.validate_for_consumer(
			release_snapshot,
			expected_context,
			Snapshot.VALIDATION_STRICT_V2
		).get("valid", false))
		and not Snapshot.intersects_target_combat_footprint_ground_gu(
			release_snapshot,
			enemy_center_ground_gu,
			enemy.combat_radius_gu
		)
	):
		return false
	if bool(Snapshot.validate_for_consumer(
		segment_snapshot,
		expected_context,
		Snapshot.VALIDATION_STRICT_V2
	).get("valid", false)):
		return Snapshot.intersects_target_combat_footprint_ground_gu(
			segment_snapshot,
			enemy_center_ground_gu,
			enemy.combat_radius_gu
		)
	var segment_start_ground_relative := (
		GroundUnit.screen_delta_px_to_ground_delta_gu(
			segment_start_screen_px - enemy.global_position
		)
	)
	var segment_end_ground_relative := (
		GroundUnit.screen_delta_px_to_ground_delta_gu(
			segment_end_screen_px - enemy.global_position
		)
	)
	var contact_radius_gu := (
		enemy.combat_radius_gu
		+ maxf(0.0, projectile_radius_gu)
	)
	return Projectile.swept_segment_intersects_footprint_gu(
		segment_start_ground_relative,
		segment_end_ground_relative,
		Vector2.ZERO,
		contact_radius_gu
	)
