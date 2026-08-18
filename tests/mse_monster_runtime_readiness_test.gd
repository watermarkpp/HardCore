extends Node


func _ready() -> void:
	# A non-runtime-ready monster (沃玛教主9, ID78, version_difference) must
	# not be silently promoted into a runtime snapshot.
	var blocked := MapEditorTypes.new_map("readiness_blocked", 990016, "Readiness Blocked", Vector2i(32, 32))
	blocked.editor_meta.workspace = "user://readiness_blocked_%s" % str(Time.get_ticks_usec())
	assert(MapEditorGroundService.initialize(blocked).ok)
	var spawn := MapEditorGameplaySemanticService.add_entry(blocked, "monster_spawn", Vector2i(5, 5), {
		"monster_id": 78, "display_name": "沃玛教主9", "count": 1, "max_alive": 1, "respawn_seconds": 60,
	})
	assert(spawn.ok, str(spawn.get("errors", [])))
	var blocked_validation := MapEditorBuildRuntimeService.validate_for_runtime(blocked)
	assert(not blocked_validation.ok, "non-runtime-ready monster must block runtime build")
	assert(
		_has_error_prefix(blocked_validation.get("errors", []), "monster_not_runtime_ready:78:"),
		str(blocked_validation.get("errors", []))
	)

	# A retired identity (鹿, ID16) is absent from the canonical catalog and
	# must fail closed as missing instead of being smuggled into runtime.
	var retired_spawn := MapEditorGameplaySemanticService.add_entry(blocked, "monster_spawn", Vector2i(7, 7), {
		"monster_id": 16, "display_name": "鹿", "count": 1, "max_alive": 1, "respawn_seconds": 60,
	})
	assert(retired_spawn.ok, str(retired_spawn.get("errors", [])))
	var retired_validation := MapEditorBuildRuntimeService.validate_for_runtime(blocked)
	assert(not retired_validation.ok, "retired monster must block runtime build")
	assert(
		_has_error_prefix(retired_validation.get("errors", []), "monster_missing_from_catalog:16"),
		str(retired_validation.get("errors", []))
	)

	# A runtime-ready monster (沃玛教主, ID76) must not add a runtime-readiness error.
	var allowed := MapEditorTypes.new_map("readiness_allowed", 990076, "Readiness Allowed", Vector2i(32, 32))
	allowed.editor_meta.workspace = "user://readiness_allowed_%s" % str(Time.get_ticks_usec())
	assert(MapEditorGroundService.initialize(allowed).ok)
	var boss := MapEditorGameplaySemanticService.add_entry(allowed, "boss_spawn", Vector2i(6, 6), {
		"monster_id": 76, "display_name": "沃玛教主", "count": 1, "max_alive": 1, "respawn_seconds": 1800,
	})
	assert(boss.ok, str(boss.get("errors", [])))
	var allowed_validation := MapEditorBuildRuntimeService.validate_for_runtime(allowed)
	assert(allowed_validation.ok, str(allowed_validation.get("errors", [])))

	print("MSE_MONSTER_RUNTIME_READINESS_PASS")
	get_tree().quit()


func _has_error_prefix(errors: Array, prefix: String) -> bool:
	for error: Variant in errors:
		if str(error).begins_with(prefix):
			return true
	return false
