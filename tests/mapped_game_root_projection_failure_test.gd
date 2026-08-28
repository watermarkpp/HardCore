extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const MapEditorRuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Lightweight GameRoot instance: only current_map_id + canonical projection
	# are exercised, no scene bootstrapping or real map resource mutation.
	var game_script := load("res://scripts/game_root.gd")
	var game: Node = game_script.new()
	# Formal profile cache contract: repeated reads in one map/context reuse the
	# same Dictionary and closures, while map/audit/registry context changes do
	# not leak the previous profile.
	var formal: Dictionary = game._resolve_projection_profile_for_map(
		MapEditorRuntimeBridge.BICH_MAP_ID
	)
	assert(bool(formal.get("success", false)), "formal Bich projection missing")
	formal["_cache_probe"] = true
	var formal_hit: Dictionary = game._resolve_projection_profile_for_map(
		MapEditorRuntimeBridge.BICH_MAP_ID
	)
	assert(bool(formal_hit.get("_cache_probe", false)), "formal projection cache did not reuse Dictionary")
	assert(
		formal.get("screen_to_ground", Callable())
			== formal_hit.get("screen_to_ground", Callable()),
		"formal projection cache did not reuse screen_to_ground Callable"
	)
	var formal_screen_to_ground: Callable = formal.get(
		"screen_to_ground", Callable()
	)
	var formal_ground_to_screen: Callable = formal.get(
		"ground_to_screen", Callable()
	)
	var formal_probe := Vector2(448.0, -3760.0)
	var formal_ground: Vector2 = formal_screen_to_ground.call(formal_probe)
	var formal_roundtrip: Vector2 = formal_ground_to_screen.call(formal_ground)
	assert(
		formal_ground.is_finite()
		and formal_roundtrip.distance_to(formal_probe) <= 0.01,
		"formal projection roundtrip drifted: %s -> %s -> %s"
		% [formal_probe, formal_ground, formal_roundtrip]
	)
	formal.erase("_cache_probe")
	var identity: Dictionary = game._resolve_projection_profile_for_map(-1)
	assert(not identity.has("_cache_probe"), "projection cache leaked across map ids")
	game.reference_audit_mode = true
	var reference: Dictionary = game._resolve_projection_profile_for_map(
		MapEditorRuntimeBridge.BICH_MAP_ID
	)
	assert(not reference.has("_cache_probe"), "audit-mode switch reused formal Dictionary")
	game.reference_audit_mode = false
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
