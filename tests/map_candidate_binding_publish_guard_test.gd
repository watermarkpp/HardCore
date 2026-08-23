extends Node

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const MapEditorAppScript := preload(
	"res://scripts/map_editor/map_editor_app.gd"
)

const MAP_KEY_A := "candidate_binding_a"
const MAP_ID_A := 991101
const MAP_KEY_B := "candidate_binding_b"
const MAP_ID_B := 991102


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	var nonce := Time.get_ticks_usec()
	var registry_path := "user://candidate_binding_%d.json" % nonce
	BuildService.test_formal_runtime_root_override = (
		"user://candidate_binding_formal_%d/" % nonce
	)
	Fixtures.write_registry(registry_path, [])
	var document_a := Fixtures.make_document(
		MAP_KEY_A, MAP_ID_A, "候选绑定地图甲"
	)
	var document_b := Fixtures.make_document(
		MAP_KEY_B, MAP_ID_B, "候选绑定地图乙"
	)
	assert(BuildService.approve_for_runtime(document_a).ok)
	assert(BuildService.approve_for_runtime(document_b).ok)
	var candidate_a := BuildService.build_candidate(document_a)
	assert(candidate_a.ok, str(candidate_a.get("errors", [])))

	# UI guard: the cached candidate remains valid for the exact document,
	# then is discarded both after a document switch and after an edit.
	var app := MapEditorAppScript.new()
	app.current_document = document_a
	app._last_build_candidate = candidate_a
	assert(not app._invalidate_last_build_candidate_if_stale())
	app.current_document = document_b
	assert(app._invalidate_last_build_candidate_if_stale())
	assert(app._last_build_candidate.is_empty())
	app.current_document = document_a
	app._last_build_candidate = candidate_a
	Fixtures.mutate_and_bake(document_a)
	assert(app._invalidate_last_build_candidate_if_stale())
	assert(app._last_build_candidate.is_empty())
	app._last_build_candidate = candidate_a
	app._reset_document_session_state()
	assert(app._last_build_candidate.is_empty())
	app.free()

	var registry_hash := Fixtures.file_sha256(registry_path)
	var formal_path := BuildService.default_runtime_path(MAP_KEY_A)
	# Service guard: switching to B cannot publish candidate A under B's ID.
	var switched := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID_B,
		BuildService.document_binding(document_b),
		registry_path,
		MAP_KEY_B
	)
	assert(
		str(switched.get("reason", ""))
		== "candidate_runtime_map_id_mismatch",
		str(switched)
	)
	# Service guard: candidate A cannot publish after A itself was edited.
	var edited := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID_A,
		BuildService.document_binding(document_a),
		registry_path,
		MAP_KEY_A
	)
	assert(
		str(edited.get("reason", "")) == "candidate_document_mismatch",
		str(edited)
	)
	assert(Fixtures.file_sha256(registry_path) == registry_hash)
	assert(not FileAccess.file_exists(formal_path))
	Fixtures.reset_seams()
	print("MAP_CANDIDATE_BINDING_PUBLISH_GUARD_PASS")
	get_tree().quit(0)
