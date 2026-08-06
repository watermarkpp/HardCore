extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Projectile := preload("res://scripts/skill_projectile.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy := Snapshot.create_swept_capsule_path(
		"wizard.fireball",
		"legacy:explicit:1",
		Vector2(4, 4),
		Vector2(8, 4),
		0.25
	)
	assert(
		int(legacy.get("schema_version", 0)) == Snapshot.LEGACY_SCHEMA_VERSION,
		"fixture must be a legacy V1 snapshot"
	)
	var before := Snapshot.legacy_snapshot_validation_count
	var no_context := Snapshot.validate_for_consumer(
		legacy,
		{},
		Snapshot.VALIDATION_EXPLICIT_LEGACY_COMPAT
	)
	assert(not bool(no_context.get("valid", false)))
	assert(
		str(no_context.get("reason", "")) == "legacy_context_required",
		"legacy without explicit context must be rejected, got %s"
		% no_context.get("reason", "")
	)
	assert(Snapshot.legacy_snapshot_validation_count == before)

	var projectile := Projectile.new()
	projectile.skill_footprint_snapshot = legacy
	assert(
		projectile.release_snapshot_intersects_target_footprint_ground_gu(
			Vector2(6, 4),
			0.25
		),
		"production legacy consumer must accept a V1 snapshot under explicit policy"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == before + 1,
		"each explicit legacy consumer validation must increment the counter"
	)
	assert(
		not projectile.release_snapshot_intersects_target_footprint_ground_gu(
			Vector2(12, 4),
			0.25
		),
		"legacy consumer must still resolve geometry correctly"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == before + 2,
		"rejected legacy geometry must still be validated explicitly"
	)
	var accepted := Snapshot.validate_for_consumer(
		legacy,
		Snapshot.legacy_consumer_context(
			"projectile_release_snapshot_intersection",
			"test fixture legacy V1 snapshot",
			"world_ground_plane_absolute"
		),
		Snapshot.VALIDATION_EXPLICIT_LEGACY_COMPAT
	)
	assert(bool(accepted.get("valid", false)))
	assert(bool(accepted.get("legacy_used", false)))
	assert(
		Snapshot.legacy_snapshot_validation_count == before + 3,
		"explicit legacy validation must increment the counter exactly once per entry"
	)
	projectile.free()
	print("SNAPSHOT_LEGACY_EXPLICIT_POLICY_PASS")
	get_tree().quit(0)
