extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const Profession := preload("res://scripts/profession_rules.gd")
const ProfessionCore := preload("res://scripts/gameplay/profile/rules/professions_core.gd")
const Factory := preload("res://scripts/gameplay/world/world_skill_timing_port.gd")
const Publisher := preload("res://scripts/gameplay/world/world_skill_timing_publication.gd")
const Catalogs := preload("res://scripts/gameplay/content/published_static_catalogs.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const BASELINE := "res://outputs/v115_multicore/world_skill_migration/ORIGINAL_ACTION_TIMING_BASELINE.json"
const FACTORY_PATH := "res://scripts/gameplay/world/world_skill_timing_port.gd"
const PUBLISHER_PATH := "res://scripts/gameplay/world/world_skill_timing_publication.gd"
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

static func digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()

static func cases() -> Array:
	var result: Array = []
	var names: Array = ["", "unknown", "hc.skill.unknown"]
	for stable_id: String in Profession.SKILL_CATALOG:
		names.append_array([stable_id, "hc.skill." + stable_id, Profession.SKILL_CATALOG[stable_id]])
	for stable_id: String in Profession.EQUIPMENT_GRANTED_SKILLS:
		names.append_array([stable_id, "hc.skill." + stable_id, Profession.EQUIPMENT_GRANTED_SKILLS[stable_id].display_name])
	for skill: String in names:
		var profile := Registry.profile(skill)
		var phases: Array = ["", "unknown_phase"]
		for phase: String in profile.get("animation_phases", {}): phases.append(phase)
		result.append(["is_runtime_ready", [skill]])
		for phase: String in phases:
			for method: String in ["render_policy", "animation_profile", "animation_duration", "primary_action_completion_seconds"]:
				result.append([method, [skill, phase]])
	return result

static func results(source: Object, queries: Array) -> Array:
	var result: Array = []
	for query: Array in queries: result.append(source.callv(query[0], query[1]))
	return result

static func texture_state() -> Array:
	return [Registry._frame_textures.size(), Registry._frame_texture_serial,
		Registry._frame_texture_loads, Registry._frame_texture_hits,
		Registry._sync_decode_calls, Registry._pending_warm_paths.size()]

static func thread_probe(snapshot: Dictionary, queries: Array) -> Dictionary:
	var token: Dictionary = snapshot.catalog_lease
	if not Catalogs.enter_reader(token): return {"entered":false}
	var professions := ProfessionCore.new(snapshot.profession_growth_source_path)
	var owner := Factory.create_owner(snapshot, professions)
	if owner == null:
		Catalogs.leave_reader(token)
		return {"entered":true,"created":false}
	var output := {"entered":true,"created":true,"thread":OS.get_thread_caller_id(),
		"results_sha256":digest(results(owner, queries))}
	var animation: Dictionary = owner.animation_profile("wizard.fireball")
	var original_animation := animation.duplicate(true)
	animation["fixture_owner_edit"] = true
	output.independent_return = owner.animation_profile("wizard.fireball") == original_animation
	var invalid := snapshot.duplicate()
	invalid.profiles_sha256 = "tampered"
	output.hash_rejected = Factory.create_owner(invalid, professions) == null
	invalid = snapshot.duplicate()
	invalid.profiles = {"object":RefCounted.new()}
	output.object_rejected = Factory.create_owner(invalid, professions) == null
	invalid = snapshot.duplicate()
	invalid.catalog_lease = token.duplicate()
	invalid.catalog_lease.generation += 1
	output.stale_rejected = Factory.create_owner(invalid, professions) == null
	owner = null
	professions = null
	output.left = Catalogs.leave_reader(token)
	return output

func _run() -> void:
	check(GameData.ensure_loaded(), "formal data loads before timing census")
	var before := texture_state()
	var queries := cases()
	var values := results(Registry, queries)
	var census := {"cases": queries, "results": values, "cases_sha256": digest(queries),
		"results_sha256": digest(values), "query_count": queries.size(),
		"registry_source_sha256": FileAccess.get_sha256("res://scripts/caster_skill_visual_registry.gd"),
		"manifest_sha256": FileAccess.get_sha256(Registry.MANIFEST_PATH),
		"visual_profile_sha256": FileAccess.get_sha256(Registry.VISUAL_PROFILE_PATH)}
	if not FileAccess.file_exists(BASELINE):
		var file := FileAccess.open(BASELINE, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(census, "  ", true, true))
			file.close()
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	check(queries.size() > 900 and values.size() == queries.size(), "real original timing census covers aliases and actual phase policies")
	check(digest(queries) == original.cases_sha256 and digest(values) == original.results_sha256, "five numeric APIs match the untouched source census")
	check(texture_state() == before, "numeric census does not load or touch texture caches")
	check(FileAccess.file_exists(FACTORY_PATH), "simulation timing owner factory exists")
	check(FileAccess.file_exists(PUBLISHER_PATH), "main publishes an independent numeric timing manifest")
	var lease := Catalogs.acquire()
	check(not lease.is_empty(), "catalogs publish before the S numeric owner is constructed")
	if not lease.is_empty():
		var snapshot := Publisher.publish(lease)
		check(not snapshot.is_empty() and Graph.validate(snapshot).success, "published timing metadata is a pure immutable value graph")
		check(snapshot.get("manifest_sha256") == original.manifest_sha256 and snapshot.get("visual_profile_sha256") == original.visual_profile_sha256, "S numeric manifest binds the same two original source revisions")
		if not snapshot.is_empty():
			var main_professions := ProfessionCore.new(GameData.profession_growth_source_path)
			check(Factory.create_owner(snapshot, main_professions) == null, "main cannot construct an S owner without a reader lease")
			var worker := Thread.new()
			check(worker.start(thread_probe.bind(snapshot, Graph.capture(queries).value)) == OK, "real Godot Thread starts using published numeric values")
			var actual: Dictionary = worker.wait_to_finish()
			check(actual.get("created", false) and actual.get("thread") != OS.get_main_thread_id() and actual.get("left", false), "numeric timing and professions are created and released by their S owner")
			check(actual.get("results_sha256") == original.results_sha256, "all S numeric timing results equal the untouched production source")
			check(actual.get("independent_return", false), "animation query preserves the original mutable independent return contract")
			check(actual.get("hash_rejected", false) and actual.get("object_rejected", false) and actual.get("stale_rejected", false), "factory rejects tampered objects and stale publication input")
			check(texture_state() == before, "S timing queries leave all M texture counters untouched")
		check(Catalogs.release_after_host_quiescence(lease), "isolated fixture releases catalogs only after its sole thread joined")
	proof.write_receipt("multicore_world_skill_action_timing_20261014", proof.records.size(), failures.size())
	print("MULTICORE_WORLD_SKILL_ACTION_TIMING_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), failures])
	get_tree().quit(0 if failures.is_empty() else 1)
