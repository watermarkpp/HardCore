extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


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

	var accepted := Snapshot.validate_for_consumer(
		legacy,
		Snapshot.legacy_consumer_context(
			"legacy_policy_contract_test",
			"test fixture legacy V1 snapshot",
			"world_ground_plane_absolute"
		),
		Snapshot.VALIDATION_EXPLICIT_LEGACY_COMPAT
	)
	assert(bool(accepted.get("valid", false)))
	assert(bool(accepted.get("legacy_used", false)))
	assert(
		Snapshot.legacy_snapshot_validation_count == before + 1,
		"explicit legacy validation must increment the counter exactly once"
	)
	print("SNAPSHOT_LEGACY_EXPLICIT_POLICY_PASS")
	get_tree().quit(0)
