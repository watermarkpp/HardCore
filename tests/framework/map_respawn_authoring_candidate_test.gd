extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Build := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const Save := preload("res://scripts/map_editor/map_editor_save_service.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Policy := preload("res://scripts/monster_respawn_policy.gd")
const PROPOSAL := "res://outputs/framework_v2/formal_respawn_20261005/RESPAWN_POLICY_PROPOSAL.json"
const REGISTRY := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const OUTPUT := "res://outputs/framework_v2/formal_respawn_20261005/region_policy_candidates_v3/"
@export var map_keys: Array[String] = ["cangyue_bone_cave_f1"]
@export var receipt_scene_id := "map_respawn_authoring_candidate_test"
var proof := Proof.new()
var errors: Array[String] = []

func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> bool:
	proof.record(value, label)
	if not value: errors.append(label)
	return value

func _read(path: String) -> Dictionary:
	return Codec.decode(FileAccess.get_file_as_string(path))

func _write(path: String, value: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir()) != OK: return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	var text := Codec.encode(value)
	file.store_string(text); file.flush(); file.close()
	return FileAccess.get_file_as_string(path) == text and not _read(path).is_empty()

func _run() -> void:
	var proposal := _read(PROPOSAL)
	check(proposal.get("groups") == 203, "fixed proposal contains exactly the 203 missing ordinary groups")
	for key: String in map_keys:
		_build_map(key, proposal)
		await get_tree().process_frame
	Bridge.reset_release_registry_override()
	Build.test_formal_runtime_root_override = ""
	var written := proof.write_receipt(receipt_scene_id, proof.records.size(), errors.size())
	print("MAP_RESPAWN_AUTHORING_CANDIDATE_", "PASS" if written and errors.is_empty() else "FAIL", " checks=", proof.records.size(), " errors=", errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)

func _build_map(key: String, proposal: Dictionary) -> void:
	var targets: Dictionary = {}
	var authoring_path := ""
	var runtime_path := ""
	var map_id := 0
	for row: Dictionary in proposal.targets:
		if row.map_key != key: continue
		targets[row.semantic_id] = row
		authoring_path = "res://" + row.authoring_path
		runtime_path = "res://" + row.runtime_path
		map_id = int(row.map_id)
	if not check(not targets.is_empty(), key + ": explicit stable target list exists"): return
	for source_path: String in [authoring_path, runtime_path]:
		var expected: Dictionary = proposal.sources[source_path.trim_prefix("res://")]
		if not check(FileAccess.get_sha256(source_path) == expected.sha256, key + ": original authority bytes match fixed proposal " + source_path): return
	var document := _read(authoring_path)
	var before := document.duplicate(true)
	var original_runtime := _read(runtime_path)
	if not check(document.design.map_type in ["dungeon_floor", "temple_floor"], key + ": authored area is an underground dungeon/temple"): return
	var found := 0
	for entry: Dictionary in document.layers.monster_spawn:
		var id := str(entry.get("semantic_id", ""))
		if not targets.has(id): continue
		var canonical := GameData.get_monster_by_id(int(entry.get("monster_id", 0)))
		if not check(canonical.get("classification") in ["ordinary", "special"] and str(entry.get("respawn_policy_id", "")).is_empty()
			and int(entry.get("monster_id", 0)) == int(targets[id].monster_id), key + ": exact ordinary identity " + id): return
		# Chests and other canonical special actors are not ordinary monsters.
		# Preserve their accepted five-minute compatibility cadence explicitly.
		var ordinary: bool = canonical.classification == "ordinary"
		entry.respawn_policy_id = Policy.NORMAL_CAVE if ordinary else Policy.BEGINNER_OUTDOOR
		entry.respawn_seconds = Policy.NORMAL_CAVE_SECONDS if ordinary else Policy.BEGINNER_OUTDOOR_SECONDS
		found += 1
	if not check(found == targets.size(), key + ": each declared group changed exactly once"): return
	# Undo only the two authorized fields to prove every gameplay/map field stayed intact.
	var stripped := document.duplicate(true)
	for entry: Dictionary in stripped.layers.monster_spawn:
		var id := str(entry.get("semantic_id", ""))
		if not targets.has(id): continue
		entry.erase("respawn_policy_id")
		entry.respawn_seconds = targets[id].before_legacy_seconds
	if not check(stripped == before, key + ": no layout, identity, count, geometry, elite, boss or unrelated field changed"): return
	document.editor_meta.revision = int(document.editor_meta.get("revision", 1)) + 1
	var approved := Build.approve_for_runtime(document)
	if not check(bool(approved.get("ok", false)), key + ": official authoring approval validates the complete document " + str(approved.get("errors", []))): return
	var destination := OUTPUT + key + "/"
	if not check(not FileAccess.file_exists(destination + "result.json"), key + ": isolated generation does not overwrite prior evidence"): return
	var authored := Save.save_document(document, destination + key + ".editor.json")
	if not check(bool(authored.get("ok", false)), key + ": official save verifies staged authoring " + str(authored)): return
	var candidate := Build.build_candidate(document)
	if not check(bool(candidate.get("ok", false)), key + ": official builder emits a candidate " + str(candidate.get("errors", []))): return
	var rebuilt: Dictionary = candidate.runtime
	var old_static := original_runtime.duplicate(true)
	var new_static := rebuilt.duplicate(true)
	var catalog_sha := FileAccess.get_sha256("res://assets/data/runtime/canonical_monster_catalog.json")
	if not check(str(new_static.collision.navigation.canonical_catalog_sha256) == catalog_sha,
		key + ": official builder binds navigation provenance to the actual current canonical catalogue"): return
	# The previously published map predates the current canonical catalogue.
	# This is the only derived provenance field excluded from the byte-independent
	# geometry comparison; every mesh, polygon and navigation node remains equal.
	old_static.collision.navigation.erase("canonical_catalog_sha256")
	new_static.collision.navigation.erase("canonical_catalog_sha256")
	for value: Dictionary in [old_static, new_static]:
		value.erase("source"); value.erase("semantics"); value.erase("build_sha256")
	if not check(old_static == new_static, key + ": rebuilt collision, instances, ground, projection and asset snapshot equal the existing map"): return
	var expected_semantics: Dictionary = original_runtime.semantics.duplicate(true)
	for entry: Dictionary in expected_semantics.monster_spawn:
		if targets.has(str(entry.get("semantic_id", ""))):
			var ordinary: bool = GameData.get_monster_by_id(int(entry.monster_id)).classification == "ordinary"
			entry.respawn_policy_id = Policy.NORMAL_CAVE if ordinary else Policy.BEGINNER_OUTDOOR
			entry.respawn_seconds = Policy.NORMAL_CAVE_SECONDS if ordinary else Policy.BEGINNER_OUTDOOR_SECONDS
	if not check(expected_semantics == rebuilt.semantics, key + ": generated semantics differ only at authorized ordinary cadence fields"): return
	var registry_copy := destination + "release_registry.json"
	if not check(_write(registry_copy, _read(REGISTRY)), key + ": isolated registry copies the real released-map baseline"): return
	Build.test_formal_runtime_root_override = destination + "formal/"
	Bridge.test_override_release_registry_path(registry_copy)
	var published := Build.publish_runtime_release(candidate.candidate_path, map_id, candidate.document_binding, registry_copy, key)
	if not check(bool(published.get("success", false)), key + ": official precise publish transaction succeeds " + str(published)): return
	check(Bridge.is_formal_playable(map_id), key + ": published candidate is validated by the actual Bridge")
	var generated := Bridge.load_map(map_id)
	check(FileAccess.get_sha256(Build.default_runtime_path(key)) == FileAccess.get_sha256(candidate.candidate_path)
		and generated.get("build_sha256") == candidate.build_sha256 and int(generated.get("runtime_map_id", 0)) == map_id,
		key + ": promoted file is byte-exact and the real loaded Bridge carries its exact approved build and typed map identity")
	var record := {"status": "PASS" if errors.is_empty() else "FAIL", "map_key": key, "map_id": map_id,
		"groups": found, "ordinary_dungeon_seconds": Policy.NORMAL_CAVE_SECONDS, "special_unchanged_seconds": Policy.BEGINNER_OUTDOOR_SECONDS,
		"authoring_path": authored.path, "candidate_path": candidate.candidate_path,
		"formal_path": Build.default_runtime_path(key), "registry_path": registry_copy,
		"document_binding": candidate.document_binding, "build_sha256": candidate.build_sha256}
	check(_write(destination + "result.json", record), key + ": durable owned generation receipt verifies all output paths")
	Bridge.reset_release_registry_override()
	Build.test_formal_runtime_root_override = ""
