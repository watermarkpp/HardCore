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
	# A. The map editor catalog must parse the single canonical monster catalog
	# once per build, and must not reopen the legacy monster/boss/service tables.
	Catalog.reset_source_parse_counts()
	var monsters := Catalog.entries("monster_spawn")
	_assert_single_canonical_source(Catalog.source_parse_counts())
	Catalog.reset_source_parse_counts()
	var bosses := Catalog.entries("boss_spawn")
	_assert_single_canonical_source(Catalog.source_parse_counts())
	Catalog.reset_source_parse_counts()
	var special := Catalog.entries("special_monster")
	_assert_single_canonical_source(Catalog.source_parse_counts())

	# B/C/D. Classification maps to the canonical editor kind.
	assert(_kind_of(monsters, "monster.64") == "ordinary", "64 must be ordinary")
	assert(_kind_of(bosses, "boss.73") == "elite", "73 must be elite")
	assert(_kind_of(bosses, "boss.76") == "boss", "76 must be boss")

	# E. monster_id=39 is a special variant whose formal placement_kind is
	# boss_spawn; its content_id must remain boss.39 (never monster.39).
	var w39 := Catalog.find("special_monster", "boss.39")
	assert(str(w39.get("classification", "")) == "special", "39 classification drifted")
	assert(str(w39.get("placement_kind", "")) == "boss_spawn", "39 placement_kind drifted")
	assert(Catalog.find("monster_spawn", "monster.39").is_empty(), "39 leaked into ordinary catalog")
	assert(Catalog.find("boss_spawn", "boss.39").is_empty(), "39 leaked into boss catalog")

	# F. Woma Taurus (76) exposes its full canonical drop profile, including
	# 沃玛号角, read from drop_profile_id -> drop_profiles (no legacy merge).
	var taurus := Catalog.find("boss_spawn", "boss.76")
	assert(int(taurus.get("drop_entry_count", 0)) == 107, "76 drop count drifted")
	assert(_has_drop_raw(taurus, "沃玛号角"), "76 drop rows lost 沃玛号角")
	assert(not (taurus.get("drop_entries", []) as Array).is_empty(), "76 full drop rows missing")

	# G. A version-difference / no-drop variant must report empty drops.
	var no_drop := Catalog.find("special_monster", "monster.78")
	assert(int(no_drop.get("drop_entry_count", -1)) == 0, "78 must have zero drops")
	assert(str(no_drop.get("drop_summary", "")).contains("为空"), "78 drop summary must be empty")

	# H/I. Saved maps only carry stable numeric monster_id; the bridge resolves
	# them without any name matching, and never rewrites the source map.
	var runtime := {
		"design": {"design_size": [50, 50]},
		"semantics": {
			"monster_spawn": [{"monster_id": "monster.41", "display_name": "saved hidden", "tile": [10, 11], "count": 2, "max_alive": 2, "radius_tiles": 3, "respawn_seconds": 60}],
			"boss_spawn": [{"boss_id": "boss.159", "display_name": "saved exact", "tile": [20, 21], "count": 1, "max_alive": 1, "radius_tiles": 0, "respawn_seconds": 1800, "spawnGroupId": "boss_spawn_test"}],
			"safe_area": [], "npc_points": [], "door_points": [], "map_exit_points": [],
		},
	}
	var content := RuntimeBridge.game_content_from_runtime(runtime)
	assert(content.spawns.size() == 1 and content.bosses.size() == 1)
	assert(int(content.spawns[0].get("monster_id", -1)) == 41, "monster 41 id lost")
	assert(int(content.bosses[0].get("monster_id", -1)) == 159, "boss 159 id lost")
	assert(str(content.bosses[0].get("spawnGroupId", "")) == "boss_spawn_test", "spawn group lost")

	print("MAP_EDITOR_BOSS_CATALOG_RUNTIME_PASS ordinary=%d boss=%d special=%d taurus_drops=107" % [monsters.size(), bosses.size(), special.size()])
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


func _assert_single_canonical_source(counts: Dictionary) -> void:
	assert(int(counts.get(CANONICAL_SOURCE, 0)) == 1, "canonical catalog parsed %s times" % counts.get(CANONICAL_SOURCE, 0))
	for legacy: String in LEGACY_SOURCES:
		assert(int(counts.get(legacy, 0)) == 0, "legacy source parsed: %s" % legacy)
