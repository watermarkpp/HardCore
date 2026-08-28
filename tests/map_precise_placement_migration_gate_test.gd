extends Node


const REGISTRY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const AUDIT_PATH := "res://assets/data/map_design/map_precise_placement_migration_authority_v1.json"
const RELEASE_REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const SANDBOX_PATH := "res://map_editor_workspace/sandbox_64/sandbox_64.editor.json"
const EXPECTED_FORMAL_MAP_COUNT := 67
const EXPECTED_MONSTER_COUNT := 1607
const EXPECTED_BOSS_COUNT := 273
const EXPECTED_TOTAL_COUNT := 1880
const EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256 := "768BA7F180B2657C3FA114BB00E44FB4701CC945DF98C4020685E2E570EE90B5"
const EXPECTED_RELEASE_REGISTRY_SHA256 := "3EEFA27BA2C12D09C4817EDF4BA60C57C8F18E044502E55EDF4E2FC10EE40D4D"
const SPECIAL_NORMAL_IDS := [39, 57, 74, 77, 90, 121, 137, 142]
const ZERO_GAP_FIELDS := [
	"unknown_monster_count",
	"disabled_monster_count",
	"illegal_layer_placement_count",
	"missing_authority_count",
	"missing_semantic_count",
	"missing_spawn_group_count",
	"semantic_duplicate_count",
	"spawn_group_duplicate_count",
	"non_identity_diff_count",
	"target_non_spawn_diff_count",
	"sandbox_migrated_count",
]


func _ready() -> void:
	_run.call_deferred()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _raw_file_sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(65536, file.get_length() - file.get_position())))
	file.close()
	return context.finish().hex_encode().to_upper()


func _fail(message: String) -> void:
	push_error("MAP_PRECISE_PLACEMENT_MIGRATION_FAIL " + message)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	var registry_value: Variant = _load_json(REGISTRY_PATH)
	if not _check(registry_value is Dictionary, "identity registry is not an object"):
		return
	var registry: Dictionary = registry_value
	var mappings_value: Variant = registry.get("maps", [])
	if not _check(mappings_value is Array, "identity registry maps is not an array"):
		return
	var mappings: Array = mappings_value
	if not _check(mappings.size() == EXPECTED_FORMAL_MAP_COUNT, "formal map count mismatch"):
		return

	var audit_value: Variant = _load_json(AUDIT_PATH)
	if not _check(audit_value is Dictionary, "migration authority manifest is not an object"):
		return
	var audit: Dictionary = audit_value
	var summary_value: Variant = audit.get("summary", {})
	var checks_value: Variant = audit.get("checks", {})
	if not _check(summary_value is Dictionary and checks_value is Dictionary, "audit summary/checks missing"):
		return
	var summary: Dictionary = summary_value
	var checks: Dictionary = checks_value
	if not _check(int(summary.get("formal_map_count", -1)) == EXPECTED_FORMAL_MAP_COUNT, "audit formal map count mismatch"):
		return
	if not _check(int(summary.get("monster_spawn", -1)) == EXPECTED_MONSTER_COUNT, "audit monster count mismatch"):
		return
	if not _check(int(summary.get("boss_spawn", -1)) == EXPECTED_BOSS_COUNT, "audit boss count mismatch"):
		return
	if not _check(int(summary.get("total", -1)) == EXPECTED_TOTAL_COUNT, "audit total count mismatch"):
		return
	for field: String in ZERO_GAP_FIELDS:
		if not _check(int(checks.get(field, -1)) == 0, "audit zero-gap field is nonzero: " + field):
			return
	if not _check(int(checks.get("release_registry_entry_count", -1)) == 11, "release registry entry count mismatch"):
		return
	if not _check(bool(checks.get("release_registry_unchanged", false)), "release registry unchanged gate failed"):
		return

	var expected_release := {
		"runtime_release_fingerprint_sha256": EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256,
		"registry_raw_sha256": EXPECTED_RELEASE_REGISTRY_SHA256,
	}
	var release_value: Variant = audit.get("release_freeze", {})
	if not _check(release_value is Dictionary, "release freeze is not an object"):
		return
	var release: Dictionary = release_value
	if not _check(release.get("baseline_expected", {}) == expected_release, "release expected baseline mismatch"):
		return
	if not _check(release.get("baseline_actual", {}) == expected_release, "release actual baseline mismatch"):
		return
	if not _check(str(release.get("canonical_sha256", "")).to_upper() == EXPECTED_RELEASE_RUNTIME_FINGERPRINT_SHA256, "release canonical hash mismatch"):
		return
	if not _check(str(release.get("registry_sha256", "")).to_upper() == EXPECTED_RELEASE_REGISTRY_SHA256, "release registry hash mismatch"):
		return
	# The authority above records that the placement-only migration preserved
	# the then-current 11-map release. This later integration phase is expected
	# to publish the 67 canonical maps, so current runtime state is checked by
	# identity/count rather than against the historical raw registry hash.
	var current_release_value: Variant = _load_json(RELEASE_REGISTRY_PATH)
	if not _check(current_release_value is Dictionary, "current release registry invalid"):
		return
	var current_release_maps: Variant = current_release_value.get("maps", [])
	if not _check(
		current_release_maps is Array
		and current_release_maps.size() == EXPECTED_FORMAL_MAP_COUNT,
		"current formal release registry must contain 67 maps"
	):
		return

	var semantics: Dictionary = {}
	var groups: Dictionary = {}
	var counts := {"monster_spawn": 0, "boss_spawn": 0}
	var special_found: Dictionary = {}
	var formal_seen: Dictionary = {}
	for mapping_value: Variant in mappings:
		if not _check(mapping_value is Dictionary, "identity mapping is not an object"):
			return
		var mapping: Dictionary = mapping_value
		var formal_map_id := str(mapping.get("map_id", ""))
		if not _check(not formal_map_id.is_empty(), "formal map ID is empty"):
			return
		if not _check(not formal_seen.has(formal_map_id), "formal map ID is duplicated: " + formal_map_id):
			return
		formal_seen[formal_map_id] = true
		var target_path := "res://map_editor_workspace/%s/%s.editor.json" % [formal_map_id, formal_map_id]
		var target_value: Variant = _load_json(target_path)
		if not _check(target_value is Dictionary, "formal target cannot be loaded: " + formal_map_id):
			return
		var target: Dictionary = target_value
		if not _check(str(target.get("map_id", "")) == formal_map_id, "target map_id mismatch: " + formal_map_id):
			return
		var layers_value: Variant = target.get("layers", {})
		if not _check(layers_value is Dictionary, "target layers missing: " + formal_map_id):
			return
		var layers: Dictionary = layers_value
		for layer: String in ["monster_spawn", "boss_spawn"]:
			var rows_value: Variant = layers.get(layer, [])
			if not _check(rows_value is Array, "target layer is not an array: %s:%s" % [formal_map_id, layer]):
				return
			var rows: Array = rows_value
			counts[layer] += rows.size()
			for row_value: Variant in rows:
				if not _check(row_value is Dictionary, "target spawn row is not an object: %s:%s" % [formal_map_id, layer]):
					return
				var row: Dictionary = row_value
				if not _check(str(row.get("kind", "")) == layer, "target row layer kind mismatch: %s:%s" % [formal_map_id, layer]):
					return
				var authority_value: Variant = row.get("authority_ref", {})
				if not _check(authority_value is Dictionary, "target authority_ref missing: " + formal_map_id):
					return
				var authority: Dictionary = authority_value
				if not _check(str(authority.get("map_id", "")) == formal_map_id, "target authority map mismatch: " + formal_map_id):
					return
				var semantic := str(row.get("semantic_id", ""))
				var semantic_prefix := "mse.placement.v1.%s.%s." % [formal_map_id, layer]
				if not _check(not semantic.is_empty() and semantic.begins_with(semantic_prefix), "target semantic ID invalid: " + formal_map_id):
					return
				if not _check(not semantics.has(semantic), "duplicate target semantic ID: " + semantic):
					return
				semantics[semantic] = true
				var group := str(row.get("spawn_group_id", ""))
				var group_prefix := "mse.group.v1.%s.%s." % [formal_map_id, layer]
				if not _check(not group.is_empty() and group.begins_with(group_prefix), "target spawn group ID invalid: " + formal_map_id):
					return
				if not _check(not groups.has(group), "duplicate target spawn group ID: " + group):
					return
				groups[group] = true
				if layer == "monster_spawn" and SPECIAL_NORMAL_IDS.has(int(row.get("monster_id", -1))):
					var special_id := int(row.get("monster_id", -1))
					if not _check(not special_found.has(special_id), "duplicate special_normal placement: %d" % special_id):
						return
					if not _check(int(row.get("count", -1)) == 1 and int(row.get("max_alive", -1)) == 1, "special_normal count/max_alive mismatch: %d" % special_id):
						return
					special_found[special_id] = true

	if not _check(counts["monster_spawn"] == EXPECTED_MONSTER_COUNT, "target monster count mismatch"):
		return
	if not _check(counts["boss_spawn"] == EXPECTED_BOSS_COUNT, "target boss count mismatch"):
		return
	if not _check(counts["monster_spawn"] + counts["boss_spawn"] == EXPECTED_TOTAL_COUNT, "target total count mismatch"):
		return
	if not _check(semantics.size() == EXPECTED_TOTAL_COUNT and groups.size() == EXPECTED_TOTAL_COUNT, "target identity cardinality mismatch"):
		return
	if not _check(special_found.size() == SPECIAL_NORMAL_IDS.size(), "special_normal target placement count mismatch"):
		return

	var special_value: Variant = audit.get("special_normal", {})
	if not _check(special_value is Dictionary, "special_normal audit missing"):
		return
	var special: Dictionary = special_value
	if not _check(int(special.get("placement_count", -1)) == SPECIAL_NORMAL_IDS.size(), "special_normal audit count mismatch"):
		return
	var audit_special_ids_value: Variant = special.get("canonical_ids", [])
	if not _check(audit_special_ids_value is Array, "special_normal audit IDs mismatch"):
		return
	var audit_special_id_rows: Array = audit_special_ids_value
	if not _check(audit_special_id_rows.size() == SPECIAL_NORMAL_IDS.size(), "special_normal audit ID count mismatch"):
		return
	var audit_special_ids: Dictionary = {}
	for value: Variant in audit_special_id_rows:
		audit_special_ids[int(value)] = true
	for expected_id: int in SPECIAL_NORMAL_IDS:
		if not _check(audit_special_ids.has(expected_id), "special_normal audit ID missing: %d" % expected_id):
			return
	var effective_value: Variant = special.get("effective_runtime_contract", [])
	if not _check(effective_value is Array and effective_value.size() == SPECIAL_NORMAL_IDS.size(), "special_normal effective contract missing"):
		return
	var effective_contract: Array = effective_value
	var effective_ids: Dictionary = {}
	for contract_value: Variant in effective_contract:
		if not _check(contract_value is Dictionary, "special_normal effective contract row is not an object"):
			return
		var contract: Dictionary = contract_value
		var contract_id := int(contract.get("monster_id", -1))
		if not _check(SPECIAL_NORMAL_IDS.has(contract_id) and not effective_ids.has(contract_id), "special_normal effective ID mismatch"):
			return
		effective_ids[contract_id] = true
		if not _check(
			str(contract.get("layer", "")) == "monster_spawn"
			and str(contract.get("runtime_effective_spawn_classification", "")) == "special_normal"
			and str(contract.get("runtime_effective_respawn_policy_id", "")) == "special_normal"
			and int(contract.get("runtime_effective_respawn_seconds", -1)) == 900
			and int(contract.get("source_row_count", -1)) == 1
			and int(contract.get("source_row_max_alive", -1)) == 1
			and bool(contract.get("source_row_respawn_policy_preserved", false)),
			"special_normal effective contract field mismatch: %d" % contract_id
		):
			return
	if not _check(effective_ids.size() == SPECIAL_NORMAL_IDS.size(), "special_normal effective ID cardinality mismatch"):
		return
	var sandbox_value: Variant = _load_json(SANDBOX_PATH)
	if not _check(sandbox_value is Dictionary, "sandbox target cannot be loaded"):
		return
	var sandbox: Dictionary = sandbox_value
	var sandbox_layers_value: Variant = sandbox.get("layers", {})
	if not _check(sandbox_layers_value is Dictionary, "sandbox layers missing"):
		return
	var sandbox_layers: Dictionary = sandbox_layers_value
	var sandbox_monsters_value: Variant = sandbox_layers.get("monster_spawn", [])
	var sandbox_bosses_value: Variant = sandbox_layers.get("boss_spawn", [])
	if not _check(sandbox_monsters_value is Array and sandbox_bosses_value is Array, "sandbox spawn layers are invalid"):
		return
	if not _check((sandbox_monsters_value as Array).size() == 45 and (sandbox_bosses_value as Array).size() == 0, "sandbox target count changed"):
		return
	var sandbox_audit_value: Variant = audit.get("sandbox_excluded", {})
	if not _check(sandbox_audit_value is Dictionary, "sandbox audit missing"):
		return
	var sandbox_audit: Dictionary = sandbox_audit_value
	if not _check(int(sandbox_audit.get("migrated_count", -1)) == 0, "sandbox migrated count is nonzero"):
		return
	if not _check(_raw_file_sha256(ProjectSettings.globalize_path(SANDBOX_PATH)) == str(sandbox_audit.get("target_document_sha256_after", "")).to_upper(), "sandbox target bytes changed"):
		return

	print("MAP_PRECISE_PLACEMENT_MIGRATION_GATE_PASS maps=67 monster_spawn=1607 boss_spawn=273 total=1880 sandbox_migrated=0 special_normal=8")
	get_tree().quit(0)
