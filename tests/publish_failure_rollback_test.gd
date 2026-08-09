extends Node

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const MAP_KEY := "p0_3r_release_c"
const MAP_ID := 990012
const REG_PATH := "user://p0_3r_rollback_registry.json"
const INVALID_CANDIDATE := (
	"res://tests/fixtures/runtime_release/invalid_checksum.runtime.json"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = "user://p0_3r_formal/c/"
	Fixtures.write_registry(REG_PATH, [])
	var doc := Fixtures.make_document(MAP_KEY, MAP_ID, "P0.3R Rollback")
	var approval := BuildService.approve_for_runtime(doc)
	assert(approval.ok, str(approval.get("errors", [])))
	var candidate_a := BuildService.build_candidate(doc)
	assert(candidate_a.ok, str(candidate_a.get("errors", [])))
	var hash_a := str(candidate_a.build_sha256)
	var formal_path := BuildService.default_runtime_path(MAP_KEY)
	Bridge.test_override_release_registry_path(REG_PATH)
	var published_a := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID,
		candidate_a.document_binding,
		REG_PATH
	)
	assert(bool(published_a.get("success", false)), str(published_a))
	assert(Bridge.is_formal_playable(MAP_ID))
	var file_hash_a := Fixtures.file_sha256(formal_path)
	Fixtures.mutate_and_bake(doc)
	var candidate_b := BuildService.build_candidate(doc)
	assert(candidate_b.ok, str(candidate_b.get("errors", [])))
	var candidate_b_path := str(candidate_b.candidate_path)
	# 1. Invalid candidate -> no change at all.
	var invalid_result := BuildService.publish_runtime_release(
		INVALID_CANDIDATE,
		MAP_ID,
		candidate_b.document_binding,
		REG_PATH
	)
	assert(
		str(invalid_result.get("reason", "")) == "runtime_invalid",
		str(invalid_result)
	)
	_assert_release_a(formal_path, file_hash_a, hash_a)
	# 2. map_key mismatch via override -> rejected before any write.
	var mismatch := BuildService.publish_runtime_release(
		candidate_b_path,
		MAP_ID,
		candidate_b.document_binding,
		REG_PATH,
		"wrong_key_override"
	)
	assert(
		str(mismatch.get("reason", "")) == "runtime_map_key_mismatch",
		str(mismatch)
	)
	_assert_release_a(formal_path, file_hash_a, hash_a)
	# 3. Registry commit failure -> formal A rolled back, registry A remains.
	BuildService.test_fail_registry_commit = true
	var reg_fail := BuildService.publish_runtime_release(
		candidate_b_path,
		MAP_ID,
		candidate_b.document_binding,
		REG_PATH
	)
	assert(
		str(reg_fail.get("reason", "")) == "registry_write_failed",
		str(reg_fail)
	)
	_assert_release_a(formal_path, file_hash_a, hash_a)
	BuildService.test_fail_registry_commit = false
	# 4. Runtime promote failure -> formal A remains, registry A remains.
	BuildService.test_fail_runtime_promote = true
	var promote_fail := BuildService.publish_runtime_release(
		candidate_b_path,
		MAP_ID,
		candidate_b.document_binding,
		REG_PATH
	)
	assert(
		str(promote_fail.get("reason", "")) == "runtime_promote_failed",
		str(promote_fail)
	)
	_assert_release_a(formal_path, file_hash_a, hash_a)
	BuildService.test_fail_runtime_promote = false
	# 5. Post-publish verification failure -> full rollback to A + Registry A.
	BuildService.test_fail_post_publish_verify = true
	var post_fail := BuildService.publish_runtime_release(
		candidate_b_path,
		MAP_ID,
		candidate_b.document_binding,
		REG_PATH
	)
	assert(
		str(post_fail.get("reason", "")) == "post_publish_verify_failed",
		str(post_fail)
	)
	_assert_release_a(formal_path, file_hash_a, hash_a)
	BuildService.test_fail_post_publish_verify = false
	# Old release A remains playable after every rollback path.
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	Fixtures.reset_seams()
	print("PUBLISH_FAILURE_ROLLBACK_PASS")
	get_tree().quit(0)


func _assert_release_a(
	formal_path: String,
	file_hash_a: String,
	hash_a: String
) -> void:
	assert(
		Fixtures.file_sha256(formal_path) == file_hash_a,
		"formal runtime file must remain A after failed publish"
	)
	var reg: Dictionary = Fixtures.read_json(REG_PATH)
	assert(
		str(reg.maps[0].approved_build_sha256) == hash_a,
		"registry approved hash must remain A after failed publish"
	)
	assert(
		int(reg.maps[0].approval_revision) == 1,
		"approval revision must remain 1 after failed publish"
	)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
