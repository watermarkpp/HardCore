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

const MAP_KEY := "p0_3r_release_a"
const MAP_ID := 990010
const REG_PATH := "user://p0_3r_build_candidate_registry.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = "user://p0_3r_formal/a/"
	Fixtures.write_registry(REG_PATH, [])
	var doc := Fixtures.make_document(MAP_KEY, MAP_ID, "P0.3R Release A")
	var approval := BuildService.approve_for_runtime(doc)
	assert(approval.ok, str(approval.get("errors", [])))
	var candidate_a := BuildService.build_candidate(doc)
	assert(candidate_a.ok, str(candidate_a.get("errors", [])))
	var hash_a := str(candidate_a.build_sha256)
	var formal_path := BuildService.default_runtime_path(MAP_KEY)
	Bridge.test_override_release_registry_path(REG_PATH)
	var published := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path), MAP_ID, REG_PATH
	)
	assert(bool(published.get("success", false)), str(published))
	assert(bool(published.get("formal_playable", false)))
	assert(int(published.get("approval_revision", 0)) == 1)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	var file_hash_a := Fixtures.file_sha256(formal_path)
	# Mutate the document so build B differs from A.
	Fixtures.mutate_and_bake(doc)
	var candidate_b := BuildService.build_candidate(doc)
	assert(candidate_b.ok, str(candidate_b.get("errors", [])))
	var hash_b := str(candidate_b.build_sha256)
	assert(hash_b != hash_a, "build B must differ from build A")
	# Contract: Build Candidate never mutates the formal release.
	assert(
		not str(candidate_b.candidate_path).begins_with(
			"res://assets/data/runtime/map_editor/"
		),
		"candidate must not be written into the formal runtime directory"
	)
	assert(
		Fixtures.file_sha256(formal_path) == file_hash_a,
		"formal runtime file must be unchanged after build candidate"
	)
	var reg_after: Dictionary = Fixtures.read_json(REG_PATH)
	assert(
		str(reg_after.maps[0].approved_build_sha256) == hash_a,
		"registry approved hash must stay A after build candidate"
	)
	# Same process, cache intact: release A still playable and load_map A.
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	# Cache reset: still A.
	Bridge.invalidate_release_registry()
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	# Simulated restart: re-load registry from scratch, still A.
	Bridge.reset_release_registry_override()
	Bridge.test_override_release_registry_path(REG_PATH)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	# Default build() with no output path also lands in the candidate dir.
	var legacy_default := BuildService.build(doc)
	assert(legacy_default.ok, str(legacy_default.get("errors", [])))
	assert(
		str(legacy_default.candidate_path).begins_with(
			"res://outputs/map_runtime_candidates/"
		),
		"default build() must write a candidate, never the formal runtime"
	)
	assert(
		Fixtures.file_sha256(formal_path) == file_hash_a,
		"formal runtime must remain unchanged after default build()"
	)
	Fixtures.reset_seams()
	print("BUILD_CANDIDATE_DOES_NOT_MUTATE_RELEASE_PASS")
	get_tree().quit(0)
