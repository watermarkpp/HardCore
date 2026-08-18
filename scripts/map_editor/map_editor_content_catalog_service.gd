class_name MapEditorContentCatalogService
extends RefCounted

const NPCServiceIdentityScript := preload("res://scripts/npc_service_identity.gd")
const CANONICAL_MONSTER_CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const NPC_PATH := "res://assets/data/vanilla_176/npcs.json"
const EXPANSION_NPC_PATH := "res://assets/data/expansions/personal_expansion_001/npcs.json"
const NORMAL_RESPAWN_SECONDS := 60
const ELITE_RESPAWN_SECONDS := 900
const BOSS_RESPAWN_SECONDS := 1800
const SPECIAL_RESPAWN_SECONDS := 60

static var _source_parse_counts: Dictionary = {}
static var _canonical_cache: Dictionary = {}


static func reset_source_parse_counts() -> void:
	_source_parse_counts.clear()
	_canonical_cache.clear()


static func source_parse_counts() -> Dictionary:
	return _source_parse_counts.duplicate()


const MONSTER_BROWSE_KINDS := [
	"monster_spawn", "boss_spawn", "special_monster", "unresolved_monster",
]


static func entries(kind: String, preferred_map_id := 4) -> Array[Dictionary]:
	if kind == "npc":
		return _npc_entries(preferred_map_id)
	if kind not in MONSTER_BROWSE_KINDS:
		return []
	var source := _canonical_source()
	var result: Array[Dictionary] = []
	for record: Dictionary in source.get("entries", []):
		var classification := str(record.get("classification", ""))
		var catalog_kind := _catalog_kind_for_classification(classification)
		if catalog_kind != kind:
			continue
		var entry := _canonical_entry(record, source, catalog_kind)
		if not entry.is_empty():
			result.append(entry)
	return _sort_catalog_entries(result)


static func find(kind: String, content_id: String) -> Dictionary:
	for entry: Dictionary in entries(kind, 4):
		if str(entry.get("content_id", "")) == content_id:
			return entry
		if kind == "npc" and content_id in entry.get("legacy_content_ids", []):
			return entry
	return {}


static func find_by_monster_id(kind: String, monster_id: int) -> Dictionary:
	if kind not in MONSTER_BROWSE_KINDS or monster_id <= 0:
		return {}
	for entry: Dictionary in entries(kind, 4):
		if int(entry.get("monster_id", -1)) == monster_id:
			return entry
	return {}


static func find_any_monster(monster_id: int) -> Dictionary:
	if monster_id <= 0:
		return {}
	for kind: String in MONSTER_BROWSE_KINDS:
		var entry := find_by_monster_id(kind, monster_id)
		if not entry.is_empty():
			return entry
	return {}


static func canonicalize_document_npc_labels(document: Dictionary) -> int:
	var layers: Dictionary = document.get("layers", {})
	var npc_points: Array = layers.get("npc_points", [])
	var changed := 0
	for index in npc_points.size():
		var entry: Dictionary = npc_points[index]
		var npc_id := str(entry.get("npc_id", entry.get("content_id", "")))
		var catalog_entry := find("npc", npc_id)
		var identity := NPCServiceIdentityScript.resolve(
			str(entry.get("display_name", catalog_entry.get("display_name", "NPC"))),
			str(entry.get("service_role", catalog_entry.get("service_role", "dialogue"))),
			str(catalog_entry.get("stock", ""))
		)
		var identity_id := str(identity.get("id", ""))
		if identity_id.is_empty():
			continue
		var canonical_name := str(identity.get("display_name", "NPC"))
		if (
			str(entry.get("display_name", "")) != canonical_name
			or str(entry.get("service_identity_id", "")) != identity_id
		):
			changed += 1
		entry["display_name"] = canonical_name
		entry["service_identity_id"] = identity_id
		npc_points[index] = entry
	layers["npc_points"] = npc_points
	document["layers"] = layers
	return changed


static func _catalog_kind_for_classification(classification: String) -> String:
	match classification:
		"ordinary":
			return "monster_spawn"
		"elite", "boss":
			return "boss_spawn"
		"special", "version_difference", "non_hostile":
			return "special_monster"
		"unresolved":
			return "unresolved_monster"
	# Any future/unknown classification lands in the review-only browse group,
	# never silently disguised as a placeable formal kind.
	return "unresolved_monster"


static func _canonical_entry(record: Dictionary, source: Dictionary, catalog_kind: String) -> Dictionary:
	var numeric_id := int(record.get("monster_id", -1))
	if numeric_id <= 0:
		return {}
	var classification := str(record.get("classification", ""))
	var placement: Dictionary = record.get("editor_placement", {})
	var placement_kind := str(placement.get("placement_kind", ""))
	if placement_kind not in ["monster_spawn", "boss_spawn"]:
		placement_kind = "boss_spawn" if classification in ["elite", "boss"] else "monster_spawn"
	var drop_policy: Dictionary = record.get("drop_policy", {})
	var drop_count := int(drop_policy.get("entry_count", 0))
	var drop_profile_id := str(record.get("drop_profile_id", ""))
	var drop_profile: Dictionary = source.get("drop_profiles", {}).get(drop_profile_id, {})
	var drop_entries: Array = drop_profile.get("entries", [])
	var appearance_profile_id := str(record.get("appearance_profile_id", ""))
	var appearance_profile: Dictionary = source.get("appearance_profiles", {}).get(appearance_profile_id, {})
	var appearance_status := str(appearance_profile.get("status", ""))
	var combat: Dictionary = record.get("combat", {})
	var stats: Dictionary = combat.get("stats", {})
	var ai: Dictionary = combat.get("ai", {})
	# P3B: canonical catalog 只包含 214 个 active 记录（retired 已排除），
	# 全部允许地图编辑器布置。authoring 不再由 classification、
	# variantCode 或 editor_placement 限制。
	var authoring_allowed := numeric_id > 0
	# Runtime readiness (can this monster safely enter the live game?) only
	# checks the real data closure: runtime gate, appearance and drop policy.
	# placement policy / version_difference / variant suffix never block it.
	var runtime_reasons: Array[String] = []
	if not bool(record.get("runtime_allowed", false)):
		runtime_reasons.append("运行时未允许")
	if appearance_status != "formal":
		runtime_reasons.append("正式战斗美术未闭环")
	if bool(drop_policy.get("hostile_requires_non_empty", false)) and drop_count <= 0:
		runtime_reasons.append("主源掉落为空")
	var runtime_ready := runtime_reasons.is_empty()
	var source_drop: Dictionary = _first_drop_source(drop_profile)
	var attrs_verified := _combat_attributes_verified(record)
	var display_name := str(record.get("canonical_name", numeric_id))
	var content_prefix := "boss" if placement_kind == "boss_spawn" else "monster"
	var map_codes: Array = placement.get("map_codes", [])
	var drop_summary := "主源掉落 %d 项" % drop_count if drop_count > 0 else "主源掉落为空"
	var evidence_status := str(source_drop.get("tier", "unverified"))
	if evidence_status == "primary":
		evidence_status = "primary_audited"
	return {
		"content_id": "%s.%d" % [content_prefix, numeric_id],
		"display_name": display_name,
		"editor_display_name": display_name,
		"base_name": display_name,
		"variant_code": str(record.get("variant_code", "")),
		"numeric_id": numeric_id,
		"monster_id": numeric_id,
		"classification": classification,
		"editor_catalog_kind": catalog_kind,
		"placement_kind": placement_kind,
		"authoring_allowed": authoring_allowed,
		"runtime_ready": runtime_ready,
		"runtime_rejection_reason": ";".join(runtime_reasons),
		"source_status": str(record.get("status", "")),
		"runtime_allowed": bool(record.get("runtime_allowed", false)),
		"attributes_verified": attrs_verified,
		"level": stats.get("level", null),
		"hp": stats.get("hp", null),
		"attack_min": stats.get("attack_min", null),
		"attack_max": stats.get("attack_max", null),
		"defense_min": stats.get("defense", null),
		"defense_max": stats.get("defense", null),
		"magic_defense_min": stats.get("magic_defense", null),
		"magic_defense_max": stats.get("magic_defense", null),
		"experience": stats.get("exp", null),
		"ai_code": ai.get("ai_code", null),
		"appearance_profile_id": appearance_profile_id,
		"appearance_status": appearance_status,
		"appearance_verified": appearance_status == "formal",
		"drop_profile_id": drop_profile_id,
		"drop_summary": drop_summary,
		"drop_entries": drop_entries,
		"drop_rows": drop_entries,
		"drop_entry_count": drop_count,
		"drop_status": str(drop_profile.get("status", "")),
		"drop_source": str(source_drop.get("distribution", "")),
		"evidence_status": evidence_status,
		"location_summary": ", ".join(map_codes),
		"map_codes": map_codes,
		"spawn_contexts": record.get("spawn_contexts", []),
		"default_respawn_seconds": _default_respawn_seconds(classification),
		"boss_class": classification,
		"source_evidence": record.get("source_evidence", {}),
	}


static func _combat_attributes_verified(record: Dictionary) -> bool:
	var combat: Dictionary = record.get("combat", {})
	var stats: Dictionary = combat.get("stats", {})
	var ai: Dictionary = combat.get("ai", {})
	if stats.is_empty():
		return false
	var resolution := str(ai.get("resolution_status", ""))
	return resolution not in ["", "unresolved", "unresolved_project_fallback"]


static func _first_drop_source(drop_profile: Dictionary) -> Dictionary:
	var evidence: Dictionary = drop_profile.get("source_evidence", {})
	var sources: Array = evidence.get("sources", [])
	if not sources.is_empty() and sources[0] is Dictionary:
		return sources[0]
	return {}


static func _default_respawn_seconds(classification: String) -> int:
	match classification:
		"ordinary": return NORMAL_RESPAWN_SECONDS
		"elite": return ELITE_RESPAWN_SECONDS
		"boss": return BOSS_RESPAWN_SECONDS
		"special": return SPECIAL_RESPAWN_SECONDS
	return 0


static func _sort_catalog_entries(entries_to_sort: Array[Dictionary]) -> Array[Dictionary]:
	entries_to_sort.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("numeric_id", 0)) < int(b.get("numeric_id", 0))
	)
	return entries_to_sort


static func _canonical_source() -> Dictionary:
	if not _canonical_cache.is_empty():
		return _canonical_cache
	var payload := _read_canonical_source()
	var records: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for raw: Dictionary in payload.get("entries", []):
		var numeric_id := int(raw.get("monster_id", -1))
		if numeric_id <= 0:
			continue
		records.append(raw)
		by_id[str(numeric_id)] = raw
	var drop_profiles: Dictionary = payload.get("drop_profiles", {})
	var appearance_profiles: Dictionary = payload.get("appearance_profiles", {})
	_canonical_cache = {
		"entries": records,
		"entries_by_id": by_id,
		"drop_profiles": drop_profiles,
		"appearance_profiles": appearance_profiles,
	}
	return _canonical_cache


static func _read_canonical_source() -> Dictionary:
	_source_parse_counts[CANONICAL_MONSTER_CATALOG_PATH] = int(_source_parse_counts.get(CANONICAL_MONSTER_CATALOG_PATH, 0)) + 1
	return _read(CANONICAL_MONSTER_CATALOG_PATH)


static func _npc_entries(preferred_map_id: int) -> Array[Dictionary]:
	var preferred: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for group: Dictionary in _read(NPC_PATH).get("records", []):
		var map_id := int(group.get("mapId", 0))
		var index := 0
		for record: Dictionary in group.get("records", []):
			index += 1
			var item := {
				"content_id": "npc.%d.%03d" % [map_id, index], "display_name": str(record.get("name", "NPC")),
				"map_id": map_id, "service_role": str(record.get("kind", "dialogue")),
				"stock": str(record.get("stock", "")), "source": "vanilla_176",
			}
			if map_id == preferred_map_id: preferred.append(item)
			else: others.append(item)
	for record: Dictionary in _read(EXPANSION_NPC_PATH).get("records", []):
		var item := {
			"content_id": str(record.get("npcId", "")), "display_name": str(record.get("name", "NPC")),
			"map_id": int(record.get("mapId", 0)), "service_role": str(record.get("kind", "dialogue")),
			"stock": str(record.get("stock", "")), "source": str(record.get("source", "personal_expansion")),
		}
		if int(record.get("mapId", 0)) == preferred_map_id: preferred.append(item)
		else: others.append(item)
	preferred.append_array(others)

	var canonical: Array[Dictionary] = []
	var canonical_index_by_identity := {}
	for item: Dictionary in preferred:
		var identity := NPCServiceIdentityScript.resolve(
			str(item.get("display_name", "NPC")),
			str(item.get("service_role", "dialogue")),
			str(item.get("stock", ""))
		)
		var identity_id := str(identity.get("id", ""))
		item["display_name"] = str(identity.get("display_name", item.get("display_name", "NPC")))
		item["service_identity_id"] = identity_id
		item["legacy_content_ids"] = [str(item.get("content_id", ""))]
		if identity_id.is_empty():
			canonical.append(item)
			continue
		if canonical_index_by_identity.has(identity_id):
			var canonical_index := int(canonical_index_by_identity[identity_id])
			var aliases: Array = canonical[canonical_index].get("legacy_content_ids", [])
			aliases.append(str(item.get("content_id", "")))
			canonical[canonical_index]["legacy_content_ids"] = aliases
			continue
		canonical_index_by_identity[identity_id] = canonical.size()
		canonical.append(item)
	return canonical


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}
