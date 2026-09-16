extends Node

## Batch publisher for the formal map wave. Runs the editor's own two-step
## transaction (build candidate -> publish runtime release) for every formal
## document whose compiled content differs from its published artifact, and
## SKIPS maps that are already content-identical. Same gates as the editor
## buttons: document identity validation, runtime approval stamping, build
## validation, candidate binding match, transactional promote with rollback.
## Idempotent: safe to re-run after a timeout; already-published maps skip.

func _ready() -> void:
	var keys: Array[String] = []
	for row_v: Variant in _read_json(
		"res://assets/data/map_design/map_identity_registry.json"
	).get("maps", []):
		if row_v is Dictionary:
			var key := str(row_v["map_id"])
			if not key.is_empty():
				keys.append(key)

	var already_published: Array[String] = []
	var published: Array[String] = []
	var failures: Array[String] = []
	var started := Time.get_ticks_msec()

	for key in keys:
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(key)
		)
		if not bool(loaded.get("ok", false)):
			failures.append("%s load: %s" % [key, str(loaded.get("errors", []))])
			continue
		var document: Dictionary = loaded.document
		var identity_check := MapEditorSaveService.validate_document_runtime_identity(document)
		if not bool(identity_check.get("ok", false)):
			failures.append("%s identity: %s" % [key, str(identity_check.get("reason", ""))])
			continue
		var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
		if not bool(approval.get("ok", false)):
			failures.append("%s approval: %s" % [key, str(approval.get("errors", []))])
			continue
		var candidate := MapEditorBuildRuntimeService.build_candidate(document)
		if not bool(candidate.get("ok", false)):
			failures.append("%s build: %s" % [key, str(candidate.get("errors", []))])
			continue
		var artifact_path := MapEditorBuildRuntimeService.default_runtime_path(key)
		var artifact_sha := ""
		if FileAccess.file_exists(artifact_path):
			var artifact: Variant = JSON.parse_string(FileAccess.get_file_as_string(artifact_path))
			if artifact is Dictionary:
				artifact_sha = str(artifact.get("build_sha256", ""))
		var candidate_sha := str(candidate.get("build_sha256", ""))
		if not artifact_sha.is_empty() and artifact_sha == candidate_sha:
			already_published.append(key)
			continue
		var publish := MapEditorBuildRuntimeService.publish_runtime_release(
			str(candidate.get("candidate_path", "")),
			int(document.get("runtime_map_id", -1)),
			candidate.get("document_binding", {}),
			MapEditorBuildRuntimeService.DEFAULT_RELEASE_REGISTRY_PATH,
			key
		)
		if bool(publish.get("success", false)):
			published.append(key)
			print("BATCH_PUBLISH %s sha=%s rev=%d" % [
				key,
				str(publish.get("approved_build_sha256", "")).substr(0, 12),
				int(publish.get("approval_revision", 0)),
			])
		else:
			failures.append("%s publish: %s %s" % [
				key, str(publish.get("reason", "")), str(publish.get("errors", []))
			])

	print("BATCH_SUMMARY total=%d published=%d already_fresh=%d failed=%d elapsed_ms=%d" % [
		keys.size(), published.size(), already_published.size(),
		failures.size(), Time.get_ticks_msec() - started
	])
	for entry: String in failures:
		print("BATCH_FAIL ", entry)
	print("BATCH_DONE")
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
