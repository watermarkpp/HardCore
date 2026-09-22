extends Node
# RV14-R2 review: a real two-map publish sequence must keep the untouched
# sibling map byte-identical. Publishing an update for map A may not rewrite
# map B's registry fragment (approval revision included) nor B's formal
# runtime bytes (the visual snapshot is embedded in the runtime document).
const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const KEY_A := "p0_3r_sibling_a"
const ID_A := 990151
const KEY_B := "p0_3r_sibling_b"
const ID_B := 990152
const REG_PATH := "user://p0_3r_sibling_registry.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	Bridge.invalidate_release_registry()
	BuildService.test_formal_runtime_root_override = (
		"user://p0_3r_sibling_formal_%d/" % Time.get_ticks_usec()
	)
	Fixtures.write_registry(REG_PATH, [])
	Bridge.test_override_release_registry_path(REG_PATH)

	var doc_a := Fixtures.make_document(KEY_A, ID_A, "Sibling A")
	assert(BuildService.approve_for_runtime(doc_a).ok)
	var candidate_a := BuildService.build_candidate(doc_a)
	assert(candidate_a.ok, str(candidate_a.get("errors", [])))
	var published_a := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path), ID_A, candidate_a.document_binding,
		REG_PATH
	)
	assert(bool(published_a.get("success", false)), str(published_a))

	var doc_b := Fixtures.make_document(KEY_B, ID_B, "Sibling B")
	assert(BuildService.approve_for_runtime(doc_b).ok)
	var candidate_b := BuildService.build_candidate(doc_b)
	assert(candidate_b.ok, str(candidate_b.get("errors", [])))
	var published_b := BuildService.publish_runtime_release(
		str(candidate_b.candidate_path), ID_B, candidate_b.document_binding,
		REG_PATH
	)
	assert(bool(published_b.get("success", false)), str(published_b))

	var reg_after_b: Dictionary = Fixtures.read_json(REG_PATH)
	assert(reg_after_b.maps.size() == 2, "two published maps expected")
	var entry_b_before: Dictionary = {}
	for entry: Variant in reg_after_b.maps:
		if int((entry as Dictionary).get("runtime_map_id", -1)) == ID_B:
			entry_b_before = entry
	assert(not entry_b_before.is_empty(), "sibling B registry entry must exist")
	var formal_b := BuildService.default_runtime_path(KEY_B)
	var bytes_b_before := Fixtures.file_sha256(formal_b)
	assert(bytes_b_before != "", "sibling B runtime artifact must exist")

	# Update A only: mutate, bake, build and publish again.
	Fixtures.mutate_and_bake(doc_a)
	var candidate_a2 := BuildService.build_candidate(doc_a)
	assert(candidate_a2.ok, str(candidate_a2.get("errors", [])))
	var published_a2 := BuildService.publish_runtime_release(
		str(candidate_a2.candidate_path), ID_A, candidate_a2.document_binding,
		REG_PATH
	)
	assert(bool(published_a2.get("success", false)), str(published_a2))

	var reg_after_a2: Dictionary = Fixtures.read_json(REG_PATH)
	assert(reg_after_a2.maps.size() == 2, "no map may be dropped by the update")
	var entry_b_after: Dictionary = {}
	var revision_a := -1
	for entry: Variant in reg_after_a2.maps:
		var row: Dictionary = entry
		if int(row.get("runtime_map_id", -1)) == ID_B:
			entry_b_after = row
		if int(row.get("runtime_map_id", -1)) == ID_A:
			revision_a = int(row.get("approval_revision", -1))
	assert(
		entry_b_after == entry_b_before,
		"sibling B registry fragment must be byte-identical after A update"
	)
	assert(revision_a == 2, "map A revision must advance to 2")
	assert(
		Fixtures.file_sha256(formal_b) == bytes_b_before,
		"sibling B runtime/visual bytes must stay unchanged after A update"
	)
	assert(Bridge.is_formal_playable(ID_A) and Bridge.is_formal_playable(ID_B))

	Fixtures.reset_seams()
	Bridge.invalidate_release_registry()
	print("RV14_MULTI_MAP_PUBLISH_SIBLING_INVARIANCE_PASS")
	get_tree().quit(0)
