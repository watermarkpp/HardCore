extends Node

const Catalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")

const CANONICAL_SOURCE := "res://assets/data/runtime/canonical_monster_catalog.json"
const LEGACY_SOURCES: Array[String] = [
	"res://assets/data/vanilla_176/monsters.json",
	"res://assets/data/vanilla_176/bosses.json",
	"res://assets/data/service_monster_runtime_catalog.json",
]


func _ready() -> void:
	# A. single parse of the canonical monster catalog, not legacy tables.
	Catalog.reset_source_parse_counts()
	var monsters := Catalog.entries("monster_spawn")
	_assert_single_canonical_source(Catalog.source_parse_counts())
	Catalog.reset_source_parse_counts()
	var bosses := Catalog.entries("boss_spawn")
	_assert_single_canonical_source(Catalog.source_parse_counts())
	Catalog.reset_source_parse_counts()
	var special := Catalog.entries("special_monster")
	_assert_single_canonical_source(Catalog.source_parse_counts())

	# B/C/D. classification -> editor kind.
	assert(_kind_of(monsters, "monster.64") == "ordinary")
	assert(_kind_of(bosses, "boss.73") == "elite")
	assert(_kind_of(bosses, "boss.76") == "boss")

	# E. 39 special, placement_kind=boss_spawn, UI content_id=boss.39.
	var w39 := Catalog.find("special_monster", "boss.39")
	assert(str(w39.get("classification", "")) == "special")
	assert(str(w39.get("placement_kind", "")) == "boss_spawn")
	assert(Catalog.find("monster_spawn", "monster.39").is_empty())
	assert(Catalog.find("boss_spawn", "boss.39").is_empty())

	# F. Woma Taurus (76) full 33-row canonical drop profile, 沃玛号角 visible.
	var taurus := Catalog.find("boss_spawn", "boss.76")
	assert(int(taurus.get("drop_entry_count", 0)) == 33)
	assert(_has_drop_raw(taurus, "沃玛号角"))

	# G. version-difference / no-drop variant reports empty drops.
	var no_drop := Catalog.find("special_monster", "monster.78")
	assert(int(no_drop.get("drop_entry_count", -1)) == 0)
	assert(str(no_drop.get("drop_summary", "")).contains("为空"))

	# Persistence contract: new entries persist only a positive int monster_id.
	var document := MapEditorTypes.new_map("persist_contract", 990102, "Persist", Vector2i(64, 64))
	var ordinary := MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", Vector2i(20, 20), {
		"monster_id": 64, "display_name": "沃玛战士", "count": 1, "max_alive": 1, "respawn_seconds": 60,
	})
	assert(ordinary.ok, "ordinary 64 rejected: %s" % ordinary.get("errors", ""))
	_assert_numeric_id_only(ordinary.entry, 64, "monster_spawn")
	var boss := MapEditorGameplaySemanticService.add_entry(document, "boss_spawn", Vector2i(22, 22), {
		"monster_id": 76, "display_name": "沃玛教主", "count": 1, "max_alive": 1, "respawn_seconds": 1800,
	})
	assert(boss.ok, "boss 76 rejected: %s" % boss.get("errors", ""))
	_assert_numeric_id_only(boss.entry, 76, "boss_spawn")
	var special39 := MapEditorGameplaySemanticService.add_entry(document, "boss_spawn", Vector2i(24, 24), {
		"monster_id": 39, "display_name": "半兽勇士1", "count": 1, "max_alive": 1, "respawn_seconds": 1800,
	})
	assert(special39.ok, "special 39 rejected: %s" % special39.get("errors", ""))
	_assert_numeric_id_only(special39.entry, 39, "boss_spawn")

	# H/I. Runtime bridge resolves numeric monster_id without name matching, and
	# still accepts the legacy "monster.XX"/"boss.XX" transport for old maps.
	var runtime := {
		"design": {"design_size": [50, 50]},
		"semantics": {
			"monster_spawn": [{"monster_id": 64, "tile": [10, 11], "count": 1, "max_alive": 1, "respawn_seconds": 60}, {"monster_id": "monster.41", "tile": [11, 11], "count": 1, "max_alive": 1, "respawn_seconds": 60}],
			"boss_spawn": [{"monster_id": 76, "tile": [20, 21], "count": 1, "max_alive": 1, "respawn_seconds": 1800}, {"boss_id": "boss.159", "tile": [21, 21], "count": 1, "max_alive": 1, "respawn_seconds": 1800}],
			"safe_area": [], "npc_points": [], "door_points": [], "map_exit_points": [],
		},
	}
	var content := RuntimeBridge.game_content_from_runtime(runtime)
	assert(content.spawns.size() == 2 and content.bosses.size() == 2)
	assert(int(content.spawns[0].get("monster_id", -1)) == 64)
	assert(int(content.spawns[1].get("monster_id", -1)) == 41)
	assert(int(content.bosses[0].get("monster_id", -1)) == 76)
	assert(int(content.bosses[1].get("monster_id", -1)) == 159)

	print("MAP_EDITOR_BOSS_CATALOG_RUNTIME_PASS ordinary=%d boss=%d special=%d taurus_drops=33" % [monsters.size(), bosses.size(), special.size()])
	get_tree().quit()


func _kind_of(entries: Array[Dictionary], content_id: String) -> String:
	for entry: Dictionary in entries:
		if str(entry.get("content_id", "")) == content_id:
			return str(entry.get("classification", ""))
	return ""


func _has_drop_raw(entry: Dictionary, token: String) -> bool:
	for row: Variant in entry.get("drop_entries", []):
		if row is Dictionary and str(row.get("raw_text", "")).contains(token):
			return true
	return false


func _assert_numeric_id_only(entry: Dictionary, expected_id: int, layer: String) -> void:
	assert(int(entry.get("monster_id", -1)) == expected_id, "wrong numeric monster_id in %s" % layer)
	assert(entry.get("monster_id") is int or entry.get("monster_id") is float, "monster_id not numeric in %s" % layer)
	assert(not entry.has("content_id"), "persisted entry must not carry content_id in %s" % layer)
	assert(not entry.has("boss_id"), "persisted entry must not carry boss_id in %s" % layer)
	assert(not entry.has("is_boss"), "persisted entry must not carry is_boss in %s" % layer)


func _assert_single_canonical_source(counts: Dictionary) -> void:
	assert(int(counts.get(CANONICAL_SOURCE, 0)) == 1, "canonical catalog parsed %s times" % counts.get(CANONICAL_SOURCE, 0))
	for legacy: String in LEGACY_SOURCES:
		assert(int(counts.get(legacy, 0)) == 0, "legacy source parsed: %s" % legacy)
