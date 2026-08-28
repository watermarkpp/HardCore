extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const Publish := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const RuntimeService := preload(
	"res://scripts/map_editor/map_editor_runtime_map_service.gd"
)
const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)

const TEST_REGISTRY := "res://tests/fixtures/runtime_release/test_release_registry.json"
const MISSING_REGISTRY := "res://tests/fixtures/runtime_release/missing_registry.json"
const WORK_REGISTRY := "user://p0_3_test_release_registry.json"

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Work on a copy so publishing never mutates the tracked fixture.
	_copy_registry_to_work()
	Bridge.test_override_release_registry_path(TEST_REGISTRY)
	var fixture_load := RuntimeService.load_runtime(
		"res://tests/fixtures/runtime_release/future_test_map.runtime.json"
	)
	print(
		"GATE_DEBUG 990123 artifact=%s reason=%s load_ok=%s errors=%s"
		% [
			Bridge.runtime_artifact_exists(990123),
			Bridge.release_rejection_reason(990123),
			fixture_load.ok,
			str(fixture_load.errors),
		]
	)
	# Future map activation WITHOUT any core code edit (registry entry + valid
	# runtime only).
	assert(
		Bridge.is_formal_playable(990123),
		"future map 990123 must be playable via registry + valid runtime"
	)
	assert(
		str(Bridge.release_rejection_reason(990123)) == "",
		"future map must have no rejection reason"
	)
	var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
		990123
	)
	assert(
		bool(profile.get("success", false)),
		"future map formal profile must resolve without bridge source edits"
	)
	# Stale build (runtime rebuilt, registry approved hash unchanged).
	assert(
		not Bridge.is_formal_playable(990124),
		"stale build must not be playable"
	)
	assert(
		str(Bridge.release_rejection_reason(990124))
		== str(Bridge.REASON_RUNTIME_BUILD_NOT_APPROVED),
		"stale build must use runtime_build_not_approved"
	)
	# Invalid runtime (checksum invalid).
	assert(
		not Bridge.is_formal_playable(990125)
		and str(Bridge.release_rejection_reason(990125))
			== str(Bridge.REASON_RUNTIME_INVALID),
		"invalid runtime must use runtime_invalid"
	)
	# Map key mismatch.
	assert(
		not Bridge.is_formal_playable(990126)
		and str(Bridge.release_rejection_reason(990126))
			== str(Bridge.REASON_RUNTIME_MAP_KEY_MISMATCH),
		"map key mismatch must be rejected"
	)
	# Runtime file missing.
	assert(
		not Bridge.is_formal_playable(990127)
		and str(Bridge.release_rejection_reason(990127))
			== str(Bridge.REASON_RUNTIME_FILE_MISSING),
		"missing runtime file must be rejected"
	)
	# Staging release not ready.
	assert(
		not Bridge.is_formal_playable(990128)
		and str(Bridge.release_rejection_reason(990128))
			== str(Bridge.REASON_RUNTIME_RELEASE_NOT_READY),
		"staging release must not be playable"
	)
	# Unregistered runtime.
	assert(
		not Bridge.is_formal_playable(9999)
		and str(Bridge.release_rejection_reason(9999))
			== str(Bridge.REASON_RUNTIME_RELEASE_NOT_REGISTERED),
		"unregistered runtime must be rejected"
	)
	# Marker-only is NOT authority: real map 4 marker exists but the test
	# registry approves a mismatched hash -> not playable.
	assert(
		not Bridge.is_formal_playable(4)
		and str(Bridge.release_rejection_reason(4))
			== str(Bridge.REASON_RUNTIME_BUILD_NOT_APPROVED),
		"marker existence + hash mismatch must never grant playability"
	)
	# Marker exists + registry absent -> not playable.
	Bridge.test_override_release_registry_path(MISSING_REGISTRY)
	assert(
		not Bridge.is_formal_playable(4)
		and str(Bridge.release_rejection_reason(4))
			== str(Bridge.REASON_RUNTIME_RELEASE_REGISTRY_MISSING),
		"marker exists + registry missing must not grant playability"
	)
	# Republish restores: publish future v2 over 990123.
	# FREEZE-P0.3R: redirect formal runtime promotion to a scratch user:// root
	# so the test never writes the tracked formal runtime directory.
	Publish.test_formal_runtime_root_override = "user://p0_3r_formal/gate/"
	# Point the bridge at the work registry before publish so the publish
	# postcondition verification reads the registry it is about to commit.
	Bridge.test_override_release_registry_path(WORK_REGISTRY)
	var publish_document := Fixtures.make_document(
		"future_test_map", 990123, "Future Test Map"
	)
	var approval := Publish.approve_for_runtime(publish_document)
	assert(approval.ok, str(approval.get("errors", [])))
	var candidate := Publish.build_candidate(publish_document)
	assert(candidate.ok, str(candidate.get("errors", [])))
	var published: Dictionary = Publish.publish_runtime_release(
		str(candidate.candidate_path),
		990123,
		candidate.document_binding,
		WORK_REGISTRY
	)
	assert(
		bool(published.get("success", false)),
		"publish must succeed"
	)
	assert(
		Bridge.is_formal_playable(990123),
		"republish must restore playability"
	)
	# Travel / World READY / formal spawn gates on an invalid release.
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	for _wait in range(600):
		if (
			bool(_game.gameplay_input_is_enabled())
			and not bool(_game.get("_world_bootstrap_in_progress"))
		):
			break
		await get_tree().process_frame
	await get_tree().process_frame
	_game.current_map_id = 990124  # stale build
	assert(
		not bool(_game._check_world_ready_contract()),
		"World READY must be false on a stale release"
	)
	var traveled: bool = _game._request_map_travel(990124)
	assert(not traveled, "travel into a stale release must be refused")
	assert(
		int(_game.current_map_id) == 990124,
		"refused travel must not switch the current map"
	)
	var enemy: EnemyActor = _game._spawn_enemy(
		GameData.get_monster_by_id(21),
		Vector2(0.0, 80.0),
		false
	)
	assert(enemy == null, "formal spawn must be rejected on a stale release")
	# Future map formal spawn works after publish (activation proof).
	_game.current_map_id = 990123
	var future_enemy: EnemyActor = _game._spawn_enemy(
		GameData.get_monster_by_id(21),
		Vector2(0.0, 80.0),
		false,
		-1.0,
		{"respawn_enabled": false}
	)
	assert(
		future_enemy != null,
		"published future map must allow a formal enemy spawn"
	)
	future_enemy.queue_free()
	Bridge.reset_release_registry_override()
	Publish.test_formal_runtime_root_override = ""
	Publish.test_fail_runtime_promote = false
	Publish.test_fail_registry_commit = false
	Publish.test_fail_post_publish_verify = false
	_game.queue_free()
	await get_tree().process_frame
	print("MAP_RUNTIME_RELEASE_GATE_PASS")
	get_tree().quit(0)


func _copy_registry_to_work() -> void:
	var source := FileAccess.open(TEST_REGISTRY, FileAccess.READ)
	var target := FileAccess.open(WORK_REGISTRY, FileAccess.WRITE)
	target.store_string(source.get_as_text())
	source.close()
	target.close()
