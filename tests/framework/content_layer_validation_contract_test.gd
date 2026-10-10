extends Node

const Guard := preload("res://scripts/features/compilation/code_preparation_envelope_guard.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const OverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const SOURCE := "res://scripts/features/compilation/code_preparation_envelope_guard.gd"

class Consumer extends Control:
	var generation := 1
	var loading_phase := true
	func is_code_preparation_generation_current(value: int) -> bool:
		return loading_phase and generation == value
	func is_code_preparation_loading_phase_current(value: int) -> bool:
		return loading_phase and generation == value
	func _exit_tree() -> void:
		if ContentLayers.has_method("cancel_internal_code_owner"):
			ContentLayers.cancel_internal_code_owner(self, generation)

var proof := Proof.new()

func _check(condition: bool, label: String) -> void:
	proof.record(condition, label)
	if not condition:
		push_error("Content validation contract: " + label)

func _ready() -> void:
	await _run_real_envelope_checks()
	var failures := 0
	for item: Dictionary in proof.records:
		if not bool(item.passed):
			failures += 1
	var receipt_ok := proof.write_receipt("content_layer_validation_contract_test", proof.records.size(), failures)
	if not receipt_ok:
		failures += 1
	print("CONTENT_LAYER_VALIDATION_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _run_real_envelope_checks() -> void:
	# An enabled package with a declared data path must fail closed when its
	# manifest cannot be read. This exercises the production consumer instead
	# of a duplicated Python interpretation of the package contract.
	var missing_diagnostics: Array = []
	ContentLayers._apply_expansion_package(
		{},
		{"id": "fixture_required", "data": "res://assets/data/expansions/__missing__/manifest.json"},
		missing_diagnostics,
	)
	_check(missing_diagnostics.size() == 1 and str(missing_diagnostics[0]).begins_with("ERROR:content_package_data_missing:"), "required package data failure is explicit")

	# These two declarations are intentionally valid without table merges:
	# later_176_content is a metadata-only switch and user_equipment.json is a
	# user-authored equipment metadata document.
	var metadata_diagnostics: Array = []
	ContentLayers._apply_expansion_package({}, {"id": "later_176_content"}, metadata_diagnostics)
	ContentLayers._apply_expansion_package({}, {"id": "user_equipment", "data": "res://assets/data/expansions/user_equipment.json"}, metadata_diagnostics)
	_check(metadata_diagnostics.is_empty(), "metadata-only expansion declarations remain valid")

	# A data-backed package without a table declaration is damaged content, not
	# a metadata package. Likewise, a non-object row must not disappear from a
	# required table while the package remains active.
	_write_user_json("user://v109_missing_tables_manifest.json", {"packageId":"fixture_missing_tables"})
	var missing_tables_diagnostics: Array = []
	ContentLayers._apply_expansion_package(
		{}, {"id":"fixture_missing_tables", "data":"user://v109_missing_tables_manifest.json"}, missing_tables_diagnostics)
	_check(missing_tables_diagnostics.size() == 1 and str(missing_tables_diagnostics[0]).begins_with("ERROR:content_package_tables_missing:"), "required package without tables is rejected")
	_write_user_json("user://v109_invalid_record_manifest.json", {"packageId":"fixture_invalid_record", "tables":{"items":"v109_invalid_record_items.json"}})
	_write_user_json("user://v109_invalid_record_items.json", {"records":[{"id":"valid"}, 7]})
	var invalid_record_diagnostics: Array = []
	ContentLayers._apply_expansion_package(
		{"items":[]}, {"id":"fixture_invalid_record", "data":"user://v109_invalid_record_manifest.json"}, invalid_record_diagnostics)
	_check(invalid_record_diagnostics.size() == 1 and str(invalid_record_diagnostics[0]).begins_with("ERROR:content_package_record_invalid:"), "required table invalid record is explicit")

	# Exercise the public prepare path: a required package data failure must
	# reject the candidate before GameData can be committed, while the active
	# expansion/catalog state remains byte-equivalent to its preflight snapshot.
	var before_expansions: Dictionary = ContentLayers.enabled_expansions.duplicate(true)
	var before_database: Dictionary = ContentLayers.merged_database.duplicate(true)
	var before_manifest: Dictionary = ContentLayers.manifests["expansion_layer"].duplicate(true)
	var expansion_manifest: Dictionary = ContentLayers.manifests["expansion_layer"].duplicate(true)
	var manifest_packages: Array = expansion_manifest.get("packages", []).duplicate(true)
	manifest_packages.append({"id": "fixture_required", "data": "res://assets/data/expansions/__missing__/manifest.json", "defaultEnabled": false})
	expansion_manifest["packages"] = manifest_packages
	ContentLayers.manifests["expansion_layer"] = expansion_manifest
	ContentLayers.enabled_expansions["fixture_required"] = false
	var requested := ContentLayers.enabled_expansions.duplicate(true)
	requested["fixture_required"] = true
	var prepared_expansion: RefCounted = ContentLayers.prepare_expansion_configuration(requested)
	_check(prepared_expansion == null, "required expansion data failure rejects public prepare")
	_check(str(ContentLayers.last_expansion_error).begins_with("content_package_data_missing:"), "public prepare reports required data failure")
	ContentLayers.manifests["expansion_layer"] = before_manifest
	ContentLayers.enabled_expansions.erase("fixture_required")
	_check(ContentLayers.enabled_expansions == before_expansions and ContentLayers.merged_database == before_database, "failed expansion prepare preserves active state")

	# Repeat the public preparation boundary for a present but structurally
	# incomplete required manifest. The active package set/database must remain
	# unchanged after this rejection as well.
	var before_missing_tables_expansions: Dictionary = ContentLayers.enabled_expansions.duplicate(true)
	var before_missing_tables_database: Dictionary = ContentLayers.merged_database.duplicate(true)
	var missing_tables_manifest: Dictionary = ContentLayers.manifests["expansion_layer"].duplicate(true)
	var missing_tables_packages: Array = missing_tables_manifest.get("packages", []).duplicate(true)
	missing_tables_packages.append({"id":"fixture_missing_tables", "data":"user://v109_missing_tables_manifest.json", "defaultEnabled":false})
	missing_tables_manifest["packages"] = missing_tables_packages
	ContentLayers.manifests["expansion_layer"] = missing_tables_manifest
	ContentLayers.enabled_expansions["fixture_missing_tables"] = false
	var missing_tables_requested := ContentLayers.enabled_expansions.duplicate(true)
	missing_tables_requested["fixture_missing_tables"] = true
	var missing_tables_prepared: RefCounted = ContentLayers.prepare_expansion_configuration(missing_tables_requested)
	_check(missing_tables_prepared == null, "required manifest without tables rejects public prepare")
	_check(str(ContentLayers.last_expansion_error).begins_with("content_package_tables_missing:"), "public prepare reports missing table declaration")
	ContentLayers.manifests["expansion_layer"] = before_manifest
	ContentLayers.enabled_expansions.erase("fixture_missing_tables")
	_check(ContentLayers.enabled_expansions == before_missing_tables_expansions and ContentLayers.merged_database == before_missing_tables_database, "missing table rejection preserves active state")

	var lf := PackedByteArray([123, 10, 125, 10])
	var crlf := PackedByteArray([123, 13, 10, 125, 13, 10])
	var record := {"bytes": lf.size(), "sha256": _sha(lf)}
	_check(Guard._checkout_bytes_match_fingerprint(lf, record), "LF source matches its published fingerprint")
	_check(Guard._checkout_bytes_match_fingerprint(crlf, record), "CRLF checkout matches the normalized published fingerprint")
	var edited := PackedByteArray([123, 13, 10, 124, 13, 10, 125, 13, 10])
	_check(not Guard._checkout_bytes_match_fingerprint(edited, record), "normalized content edits remain rejected")

	# Exercise the real published envelope and terminal resource predicates. A
	# plan is only accepted through ContentLayers; no hand-built plan can certify
	# the Script/Shader identities below.
	var consumer := Consumer.new()
	add_child(consumer)
	var overlay: Control = OverlayScript.new()
	consumer.add_child(overlay)
	overlay.begin_loading("content.validation")
	await overlay.transition_covered
	var prepared: Dictionary = await ContentLayers.prepare_internal_code_entry("framework.code.caster_animation.v1", overlay, consumer, consumer.generation)
	_check(bool(prepared.get("success", false)), "formal code envelope prepares through ContentLayers")
	if not bool(prepared.get("success", false)):
		consumer.queue_free()
		return
	var plan: RefCounted = prepared.get("plan")
	var lease: RefCounted = prepared.get("lease")
	var script_result: Dictionary = await ContentLayers.request_internal_prepared_script(prepared, consumer, consumer.generation)
	var script: Script = script_result.get("resource") as Script
	_check(bool(script_result.get("success", false)) and script != null, "formal target Script is admitted")
	if script != null:
		var target_bytes := FileAccess.get_file_as_bytes(plan.target_path())
		var target_text := target_bytes.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
		var target_file := FileAccess.open(plan.target_path(), FileAccess.WRITE)
		target_file.store_buffer(target_text.replace("\n", "\r\n").to_utf8_buffer())
		target_file.close()
		_check(bool(plan.valid_target(script)), "valid_target accepts an autocrlf Script with identical content")
		var tampered := target_text.replace("extends ", "extends  ")
		target_file = FileAccess.open(plan.target_path(), FileAccess.WRITE)
		target_file.store_buffer(tampered.replace("\n", "\r\n").to_utf8_buffer())
		target_file.close()
		_check(not bool(plan.valid_target(script)), "valid_target rejects normalized content tampering")
		target_file = FileAccess.open(plan.target_path(), FileAccess.WRITE)
		target_file.store_buffer(target_bytes)
		target_file.close()
	for path: String in plan.paths():
		var shader := lease.resource_at(path) as Shader
		_check(shader != null and bool(plan.valid_asset(path, shader)), "valid_asset accepts resident Shader: " + path)
	if is_instance_valid(consumer):
		consumer.queue_free()

func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _write_user_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
