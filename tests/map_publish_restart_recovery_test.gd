extends Node

## R2-W1 crash-recovery counterexamples for the map publish transaction.
## The in-process failure seams roll back correctly, but a crash between the
## backup rename and the promote rename leaves a restart state that no code
## recovers: formal artifact missing + .bak holding the last complete
## release, or registry missing + registry .bak holding the last complete
## registry. This test proves the restart recovery contract:
##   1. a failed retry must never destroy the recoverable old version,
##   2. the next publish must recover and proceed (restart recovery),
##   3. a half-published state (artifact B + registry A) must fail closed,
##      never serving a mixed version.

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const KEY_A := "p0_3r_crash_a"
const ID_A := 990021
const REG_A := "user://p0_3r_crash_registry_a.json"
const KEY_B := "p0_3r_crash_b"
const ID_B := 990022
const REG_B := "user://p0_3r_crash_registry_b.json"


func _ready() -> void:
	_run.call_deferred()


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _run() -> void:
	Fixtures.reset_seams()
	Bridge.invalidate_release_registry()

	# ---- Scenario 1: runtime artifact crash window ----
	BuildService.test_formal_runtime_root_override = "user://p0_3r_crash_formal_a/"
	Fixtures.write_registry(REG_A, [])
	var doc_a := Fixtures.make_document(KEY_A, ID_A, "Crash Recovery A")
	assert(BuildService.approve_for_runtime(doc_a).ok)
	var candidate_a := BuildService.build_candidate(doc_a)
	assert(candidate_a.ok, str(candidate_a.get("errors", [])))
	var hash_a := str(candidate_a.build_sha256)
	Bridge.test_override_release_registry_path(REG_A)
	var published_a := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path), ID_A, candidate_a.document_binding, REG_A
	)
	assert(bool(published_a.get("success", false)), str(published_a))
	var formal_a := BuildService.default_runtime_path(KEY_A)
	var file_hash_a := Fixtures.file_sha256(formal_a)
	assert(file_hash_a != "", "published formal artifact must exist")
	assert(
		str(Bridge.load_map(ID_A).get("build_sha256", "")) == hash_a
	)

	# Crash between backup rename and promote rename: formal missing, .bak=A.
	assert(
		DirAccess.rename_absolute(_global(formal_a), _global(formal_a) + ".bak") == OK
	)
	assert(
		not FileAccess.file_exists(formal_a),
		"crash state must leave the formal artifact missing"
	)
	# A crash kills the process; the next process starts with cold caches.
	Bridge.invalidate_release_registry()
	assert(
		not Bridge.is_formal_playable(ID_A),
		"half-published state must fail closed instead of serving a mix"
	)

	Fixtures.mutate_and_bake(doc_a)
	var candidate_b := BuildService.build_candidate(doc_a)
	assert(candidate_b.ok, str(candidate_b.get("errors", [])))

	# Retry with an in-process promote failure. The seam fires after the
	# backup handling, exactly like any real promote failure in the window.
	BuildService.test_fail_runtime_promote = true
	var retry := BuildService.publish_runtime_release(
		str(candidate_b.candidate_path), ID_A, candidate_b.document_binding, REG_A
	)
	BuildService.test_fail_runtime_promote = false
	assert(
		str(retry.get("reason", "")) == "runtime_promote_failed",
		str(retry)
	)
	# The old release A must survive a failed retry (recoverable on disk):
	# either the formal artifact or the .bak still holds release A's bytes.
	# After a recovery-aware retry the .bak has been consumed back into the
	# formal path, so a missing .bak with an intact formal artifact is the
	# expected recovered shape.
	var survived_formal := Fixtures.file_sha256(formal_a)
	var backup_survives := FileAccess.file_exists(formal_a + ".bak")
	var survived_backup := (
		Fixtures.file_sha256(formal_a + ".bak") if backup_survives else ""
	)
	assert(
		survived_formal == file_hash_a or survived_backup == file_hash_a,
		"failed retry destroyed the last complete release (formal and .bak both gone or mutated)"
	)
	# Restart recovery: the consumer must serve release A again.
	Bridge.invalidate_release_registry()
	assert(
		Bridge.is_formal_playable(ID_A),
		"old release must be playable again after the failed retry"
	)
	assert(
		str(Bridge.load_map(ID_A).get("build_sha256", "")) == hash_a,
		"recovered artifact must be release A"
	)

	# ---- Scenario 2: registry crash window ----
	BuildService.test_formal_runtime_root_override = "user://p0_3r_crash_formal_b/"
	Fixtures.write_registry(REG_B, [])
	var doc_b := Fixtures.make_document(KEY_B, ID_B, "Crash Recovery B")
	assert(BuildService.approve_for_runtime(doc_b).ok)
	var candidate_a2 := BuildService.build_candidate(doc_b)
	assert(candidate_a2.ok, str(candidate_a2.get("errors", [])))
	Bridge.test_override_release_registry_path(REG_B)
	var published_a2 := BuildService.publish_runtime_release(
		str(candidate_a2.candidate_path), ID_B, candidate_a2.document_binding, REG_B
	)
	assert(bool(published_a2.get("success", false)), str(published_a2))
	var formal_b := BuildService.default_runtime_path(KEY_B)
	var hash_a2 := str(candidate_a2.build_sha256)
	assert(Fixtures.file_sha256(formal_b) != "")

	# Crash between registry backup rename and registry promote rename:
	# registry missing, registry .bak = complete old registry.
	assert(
		DirAccess.rename_absolute(_global(REG_B), _global(REG_B) + ".bak") == OK
	)
	assert(not FileAccess.file_exists(REG_B))

	# The next publish must recover the registry and proceed (restart recovery).
	Fixtures.mutate_and_bake(doc_b)
	var candidate_b2 := BuildService.build_candidate(doc_b)
	assert(candidate_b2.ok, str(candidate_b2.get("errors", [])))
	var retry_b := BuildService.publish_runtime_release(
		str(candidate_b2.candidate_path), ID_B, candidate_b2.document_binding, REG_B
	)
	assert(
		bool(retry_b.get("success", false)),
		"publish must recover the crashed registry from .bak and proceed: %s" % str(retry_b)
	)
	assert(Bridge.is_formal_playable(ID_B))
	assert(
		str(Bridge.load_map(ID_B).get("build_sha256", ""))
		== str(candidate_b2.build_sha256),
		"after recovery the published release must be the new candidate"
	)

	# ---- Scenario 3: artifact new + registry old must fail closed ----
	# Simulate promote-done/registry-not-committed: artifact bytes = A2 while
	# the registry (recovered, then updated above) advertises B2. Rebuild that
	# state by copying the A2 candidate over the formal artifact.
	assert(
		DirAccess.copy_absolute(
			_global(str(candidate_a2.candidate_path)), _global(formal_b)
		)
		== OK
	)
	Bridge.invalidate_release_registry()
	assert(
		not Bridge.is_formal_playable(ID_B),
		"mismatched artifact/registry hash must fail closed, never serve a mix"
	)
	# Restoring consistency via a normal publish must work.
	var republish := BuildService.publish_runtime_release(
		str(candidate_b2.candidate_path), ID_B, candidate_b2.document_binding, REG_B
	)
	assert(bool(republish.get("success", false)), str(republish))
	assert(Bridge.is_formal_playable(ID_B))
	assert(
		str(Bridge.load_map(ID_B).get("build_sha256", ""))
		== str(candidate_b2.build_sha256)
	)

	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = ""
	print("MAP_PUBLISH_RESTART_RECOVERY_PASS")
	get_tree().quit(0)
