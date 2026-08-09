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

const MAP_KEY := "p0_3r_release_b"
const MAP_ID := 990011
const REG_PATH := "user://p0_3r_publish_promotes_registry.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = "user://p0_3r_formal/b/"
	Fixtures.write_registry(REG_PATH, [])
	var doc := Fixtures.make_document(MAP_KEY, MAP_ID, "P0.3R Promote")
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
	assert(int(published_a.get("approval_revision", 0)) == 1)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	# Rebuild as candidate B (no publish yet) and verify release stays A.
	Fixtures.mutate_and_bake(doc)
	var candidate_b := BuildService.build_candidate(doc)
	assert(candidate_b.ok, str(candidate_b.get("errors", [])))
	var hash_b := str(candidate_b.build_sha256)
	assert(hash_b != hash_a)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_a)
	# Publish B: release must become B everywhere.
	var published_b := BuildService.publish_runtime_release(
		str(candidate_b.candidate_path),
		MAP_ID,
		candidate_b.document_binding,
		REG_PATH
	)
	assert(bool(published_b.get("success", false)), str(published_b))
	assert(int(published_b.get("approval_revision", 0)) == 2)
	assert(
		str(published_b.get("approved_build_sha256", "")) == hash_b
	)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_b)
	# Cache reset: still B.
	Bridge.invalidate_release_registry()
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_b)
	# Simulated restart: still B.
	Bridge.reset_release_registry_override()
	Bridge.test_override_release_registry_path(REG_PATH)
	assert(Bridge.is_formal_playable(MAP_ID))
	assert(str(Bridge.load_map(MAP_ID).get("build_sha256", "")) == hash_b)
	# Registry content: entry runtime_path must point at the formal artifact.
	var reg: Dictionary = Fixtures.read_json(REG_PATH)
	assert(str(reg.maps[0].runtime_path) == formal_path)
	assert(str(reg.maps[0].approved_build_sha256) == hash_b)
	assert(int(reg.maps[0].approval_revision) == 2)
	Fixtures.reset_seams()
	print("PUBLISH_PROMOTES_CANDIDATE_PASS")
	get_tree().quit(0)
