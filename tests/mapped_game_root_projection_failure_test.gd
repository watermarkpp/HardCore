extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Lightweight GameRoot instance: only current_map_id + canonical projection
	# are exercised, no scene bootstrapping or real map resource mutation.
	var game_script := load("res://scripts/game_root.gd")
	var game: Node = game_script.new()
	game.current_map_id = 9999  # mapped id with NO runtime map available
	var before := int(game.missing_projection_rejection_count)
	var result: Dictionary = game._try_canonical_screen_px_to_ground_gu(
		Vector2(0.0, 80.0)
	)
	assert(
		not bool(result.get("success", true)),
		"mapped GameRoot conversion must fail when the map has no formal projection profile"
	)
	assert(
		str(result.get("reason", ""))
		== str(GroundUnit.REASON_UNSUPPORTED_MAP_PROJECTION),
		"GameRoot failure must use the unified reason"
	)
	var raw: Vector2 = game._canonical_screen_px_to_ground_gu(
		Vector2(0.0, 80.0)
	)
	assert(
		not raw.is_finite(),
		"mapped GameRoot conversion must never return delta masquerading as absolute"
	)
	var back: Vector2 = game._canonical_ground_gu_to_screen_px(
		Vector2(130.0, 130.0)
	)
	assert(
		not back.is_finite(),
		"mapped ground_to_screen must fail closed as well"
	)
	assert(
		int(game.missing_projection_rejection_count) > before,
		"GameRoot must record the projection failure"
	)
	# Formal enemy spawn must be refused on the broken mapped context.
	var enemy_result: EnemyActor = game._spawn_enemy(
		{"name": "p01_no_spawn", "hp": 1, "attackMin": 1, "attackMax": 1, "level": 1},
		Vector2(0.0, 80.0),
		false
	)
	assert(
		enemy_result == null,
		"mapped enemy spawn must be rejected when the projection is missing"
	)
	assert(
		game._combat_spatial_index == null
		or game._combat_spatial_index.registered_actor_count() == 0,
		"no enemy may be registered at fake coordinates"
	)
	var rejections_total := int(game.missing_projection_rejection_count)
	game.free()
	await get_tree().process_frame
	print(
		"MAPPED_GAME_ROOT_PROJECTION_FAILURE_PASS reason=%s rejections=%d"
		% [result.get("reason", ""), rejections_total]
	)
	get_tree().quit(0)
