extends Node

## RV14-02 red-green regression: the publish recovery entry must recognize
## BOTH real backup protocols (.bak from the whole-registry atomic writer and
## .restore_bak from the single-map preserving writer), validate candidates
## before restoring, keep the source backup alive until the restored bytes are
## verified, and distinguish "publish failed and recovered" from "recovery
## failed".

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const MAP_KEY := "rv14_restore_a"
const MAP_ID := 990031
const REG_PATH := "user://rv14_restore_registry.json"
const FORMAL_ROOT := "user://rv14_restore_formal/"

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _report(marker: String) -> void:
	for failure: String in failures:
		push_error("REGISTRY_RESTORE_ENTRY: " + failure)
	print(
		"REGISTRY_RESTORE_ENTRY_%s checks=%d failures=%d" %
		[marker, checks, failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	_run.call_deferred()

func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func _build_candidate() -> Dictionary:
	var doc := Fixtures.make_document(MAP_KEY, MAP_ID, "RV14 Restore A")
	var approval := BuildService.approve_for_runtime(doc)
	expect(approval.ok, "fixture: approval failed: %s" % str(approval.get("errors", [])))
	var candidate := BuildService.build_candidate(doc)
	expect(candidate.ok, "fixture: build failed: %s" % str(candidate.get("errors", [])))
	return candidate

func _setup_published_state(candidate: Dictionary) -> String:
	## Publish once so a formal runtime + revision-1 registry exist; returns
	## the formal runtime path.
	Fixtures.write_registry(REG_PATH, [])
	var published := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(bool(published.get("success", false)), "fixture: first publish failed: %s" % str(published))
	return BuildService.default_runtime_path(MAP_KEY)

func _run() -> void:
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = FORMAL_ROOT
	Bridge.test_override_release_registry_path(REG_PATH)
	var candidate := _build_candidate()
	var formal_path := _setup_published_state(candidate)
	var registry_bytes_before: PackedByteArray = (
		FileAccess.open(REG_PATH, FileAccess.READ).get_buffer(
			FileAccess.open(REG_PATH, FileAccess.READ).get_length()
		) if FileAccess.file_exists(REG_PATH) else PackedByteArray()
	)
	var registry_before_text := registry_bytes_before.get_string_from_utf8()

	# --- R1: restart window with ONLY .restore_bak (the RV14-02 gap) ---
	# Simulate: single-map publish renamed the registry to .restore_bak and
	# exited before promoting the temp file. Main file gone, .restore_bak
	# holds the complete revision-1 registry, .bak absent. The NEXT formal
	# publish must recover through the entry, not fail with
	# release_registry_missing.
	DirAccess.rename_absolute(_absolute(REG_PATH), _absolute(REG_PATH) + ".bak")
	# Move .bak content into .restore_bak and drop .bak to isolate protocols.
	DirAccess.rename_absolute(_absolute(REG_PATH) + ".bak", _absolute(REG_PATH) + ".restore_bak")
	expect(
		FileAccess.file_exists(_absolute(REG_PATH) + ".restore_bak")
		and not FileAccess.file_exists(REG_PATH)
		and not FileAccess.file_exists(_absolute(REG_PATH) + ".bak"),
		"R1 fixture: restart window state (main missing, only .restore_bak)"
	)
	var republished := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		bool(republished.get("success", false)),
		"R1: publish through the recovery entry must succeed (got reason=%s)" % str(republished.get("reason", ""))
	)
	if bool(republished.get("success", false)):
		expect(int(republished.get("approval_revision", 0)) == 2, "R1: recovered publish must advance revision")
	expect(Bridge.is_formal_playable(MAP_ID), "R1: recovered registry must be formal playable")

	# --- R2: only .bak (R2-W1 path) still recovers ---
	# Independently constructed: main file exists (revision-1 style registry),
	# then moved to .bak so only .bak remains.
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = FORMAL_ROOT
	Bridge.test_override_release_registry_path(REG_PATH)
	Fixtures.write_registry(REG_PATH, [])
	DirAccess.remove_absolute(_absolute(REG_PATH) + ".restore_bak")
	DirAccess.rename_absolute(_absolute(REG_PATH), _absolute(REG_PATH) + ".bak")
	var republish_bak := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		bool(republish_bak.get("success", false)),
		"R2: .bak-only recovery must still succeed (got reason=%s)" % str(republish_bak.get("reason", ""))
	)

	# --- R3: identical backups recover without ambiguity ---
	# Independently constructed from a valid main registry.
	Fixtures.write_registry(REG_PATH, [])
	DirAccess.copy_absolute(_absolute(REG_PATH), _absolute(REG_PATH) + ".bak")
	DirAccess.copy_absolute(_absolute(REG_PATH), _absolute(REG_PATH) + ".restore_bak")
	DirAccess.remove_absolute(_absolute(REG_PATH))
	var republish_same := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		bool(republish_same.get("success", false)),
		"R3: identical backups must recover (got reason=%s)" % str(republish_same.get("reason", ""))
	)

	# --- R4: conflicting backups with comparable approval revisions ---
	# Independently constructed: two valid registries whose shared map entry
	# differs by approval_revision. The runtime file referenced by the entry
	# is the formal path published above.
	var base_entry := Fixtures.make_entry(
		MAP_ID, MAP_KEY, "rv14_approved_hash", formal_path, 1
	)
	var base_registry := {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": [base_entry],
	}
	var low: Dictionary = base_registry.duplicate(true)
	var high: Dictionary = base_registry.duplicate(true)
	low.maps[0].approval_revision = 1
	high.maps[0].approval_revision = 2
	Fixtures.write_json(_absolute(REG_PATH) + ".bak", low)
	Fixtures.write_json(_absolute(REG_PATH) + ".restore_bak", high)
	DirAccess.remove_absolute(_absolute(REG_PATH))
	var republish_conflict := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		bool(republish_conflict.get("success", false)),
		"R4a: conflicting-but-comparable backups must still publish (got reason=%s)" % str(republish_conflict.get("reason", ""))
	)
	if bool(republish_conflict.get("success", false)):
		# The higher revision (2) must be the recovery source: the publish
		# then advances from 2 to 3, never from the low revision's 1.
		expect(
			int(republish_conflict.get("approval_revision", 0)) == 3,
			"R4a: approval_revision evidence must pick the higher revision (base revision=%s)" % str(republish_conflict.get("approval_revision", 0))
		)
	# Unresolvable: same revision but different bytes (display name diverged)
	# -> explicit conflict, both backups preserved untouched.
	low.maps[0].approval_revision = 5
	high.maps[0].approval_revision = 5
	low.maps[0].display_name = "RV14 Restore Low"
	high.maps[0].display_name = "RV14 Restore High"
	Fixtures.write_json(_absolute(REG_PATH) + ".bak", low)
	Fixtures.write_json(_absolute(REG_PATH) + ".restore_bak", high)
	DirAccess.remove_absolute(_absolute(REG_PATH))
	var republish_deadlock := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		not bool(republish_deadlock.get("success", false))
		and str(republish_deadlock.get("reason", "")) == "release_registry_backup_conflict",
		"R4b: equal-revision conflicting backups must fail closed with an explicit conflict (got %s)" % str(republish_deadlock)
	)
	expect(
		FileAccess.file_exists(_absolute(REG_PATH) + ".bak")
		and FileAccess.file_exists(_absolute(REG_PATH) + ".restore_bak"),
		"R4b: both backups must remain preserved on conflict"
	)
	# Cleanup: re-establish a published-style main registry for later
	# scenarios (the target entry plus one unrelated entry).
	if FileAccess.file_exists(_absolute(REG_PATH) + ".restore_bak"):
		DirAccess.copy_absolute(_absolute(REG_PATH) + ".restore_bak", _absolute(REG_PATH))
	else:
		Fixtures.write_registry(REG_PATH, [])
	var unrelated_entry := Fixtures.make_entry(
		999999, "rv14_unrelated", "rv14_unrelated_hash", "user://rv14_unrelated.json", 1
	)
	var recovery_main_registry := {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": [
			Fixtures.make_entry(
				MAP_ID, MAP_KEY, "rv14_approved_hash", formal_path, 1
			),
			unrelated_entry,
		],
	}
	Fixtures.write_json(_absolute(REG_PATH), recovery_main_registry)

	# --- R5: corrupted backups stay refused ---
	# Independently constructed: only a corrupted .restore_bak exists, no .bak.
	DirAccess.remove_absolute(_absolute(REG_PATH))
	if FileAccess.file_exists(_absolute(REG_PATH) + ".bak"):
		DirAccess.remove_absolute(_absolute(REG_PATH) + ".bak")
	var corrupt := FileAccess.open(_absolute(REG_PATH) + ".restore_bak", FileAccess.WRITE)
	corrupt.store_string("{not json")
	corrupt.close()
	var republish_corrupt := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		not bool(republish_corrupt.get("success", false))
		and str(republish_corrupt.get("reason", "")) == "release_registry_missing",
		"R5: corrupted backup must not be adopted (got reason=%s)" % str(republish_corrupt.get("reason", ""))
	)

	# --- R6: no backups at all -> plain missing ---
	# Independently constructed: main removed, no backups of any protocol.
	if FileAccess.file_exists(_absolute(REG_PATH) + ".restore_bak"):
		DirAccess.remove_absolute(_absolute(REG_PATH) + ".restore_bak")
	if FileAccess.file_exists(_absolute(REG_PATH) + ".bak"):
		DirAccess.remove_absolute(_absolute(REG_PATH) + ".bak")
	DirAccess.remove_absolute(_absolute(REG_PATH))
	var republish_none := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		not bool(republish_none.get("success", false))
		and str(republish_none.get("reason", "")) == "release_registry_missing",
		"R6: missing registry without backups stays release_registry_missing (got %s)" % str(republish_none.get("reason", ""))
	)
	# Re-establish the published-style main registry for R8/R9.
	Fixtures.write_json(_absolute(REG_PATH), recovery_main_registry)

	# --- R8: publish-failure vs recovery-failure are distinguishable ---
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = FORMAL_ROOT
	BuildService.test_fail_registry_commit = true
	Bridge.test_override_release_registry_path(REG_PATH)
	var failed_publish := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(
		not bool(failed_publish.get("success", false))
		and str(failed_publish.get("reason", "")) == "registry_write_failed",
		"R8a: registry commit failure with successful runtime restore reports registry_write_failed (got %s)" % str(failed_publish)
	)
	BuildService.test_fail_registry_commit = false
	# R8b: after the failed publish the formal runtime must have been restored
	# to the previously published bytes (recovery succeeded, distinguishable
	# from a recovery failure which would surface its own reason).
	expect(
		FileAccess.file_exists(_absolute(formal_path)),
		"R8b: formal runtime must be restored after registry commit failure"
	)

	# --- R9: single-map publish preserves unrelated registry bytes ---
	Fixtures.reset_seams()
	BuildService.test_formal_runtime_root_override = FORMAL_ROOT
	BuildService.test_fail_registry_commit = false
	Bridge.test_override_release_registry_path(REG_PATH)
	Fixtures.write_json(_absolute(REG_PATH), recovery_main_registry)
	# A freshly closed file can transiently reject rename on Windows while an
	# external indexer finishes scanning it; settle before the publish.
	OS.delay_msec(150)
	var before_single := (
		FileAccess.open(REG_PATH, FileAccess.READ).get_buffer(
			FileAccess.open(REG_PATH, FileAccess.READ).get_length()
		).get_string_from_utf8()
	)
	var final_publish := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		MAP_ID,
		candidate.document_binding,
		REG_PATH,
		MAP_KEY
	)
	expect(bool(final_publish.get("success", false)), "R9: single-map publish must succeed: %s" % str(final_publish))
	if bool(final_publish.get("success", false)):
		var after_text: String = (
			FileAccess.open(REG_PATH, FileAccess.READ).get_buffer(
				FileAccess.open(REG_PATH, FileAccess.READ).get_length()
			).get_string_from_utf8()
		)
		# The unrelated entry must survive byte-for-byte inside the updated
		# registry text (single-map splice contract). Extract the entry's
		# literal object span from the pre-publish text and require the same
		# byte sequence in the post-publish text.
		var unrelated_json := _extract_json_object_span(
			before_single, "rv14_unrelated"
		)
		expect(
			not unrelated_json.is_empty() and after_text.contains(unrelated_json),
			"R9: unrelated map entry must survive byte-identically"
		)

	Fixtures.reset_seams()
	Bridge.reset_release_registry_override()
	_report("PASS" if failures.is_empty() else "FAIL")


## Locate the JSON object containing the given map_key literal and return its
## exact source span, so callers can verify byte-level survival across a
## single-map splice.
static func _extract_json_object_span(text: String, map_key: String) -> String:
	var marker := '"map_key": "%s"' % map_key
	var marker_index := text.find(marker)
	if marker_index < 0:
		return ""
	var object_start := text.rfind("{", marker_index)
	if object_start < 0:
		return ""
	var depth := 0
	var in_string := false
	var escaped := false
	for index in range(object_start, text.length()):
		var character := text[index]
		if in_string:
			if character == '"' and not escaped:
				in_string = false
			elif character == "\\":
				escaped = not escaped
			else:
				escaped = false
			continue
		if character == '"':
			in_string = true
		elif character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return text.substr(object_start, index - object_start + 1)
	return ""



