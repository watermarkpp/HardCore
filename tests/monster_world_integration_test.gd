extends Node

const BridgeScript := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)
const DomainRuntimeServicesScript := preload(
	"res://scripts/layers/runtime/domain_runtime_services.gd"
)
const RuntimeMapServiceScript := preload(
	"res://scripts/map_editor/map_editor_runtime_map_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.ensure_loaded(), "GameData canonical catalog failed to load")
	var counts := GameData.canonical_monster_counts()
	assert(
		str(counts.get("contract_id", ""))
		== "monster.catalog.runtime_counts.v1",
		"canonical count contract drifted"
	)
	assert(int(counts.get("catalog_identity_count", 0)) == 214, "catalog identity count drifted")
	assert(int(counts.get("catalog_runtime_allowed_count", 0)) == 37, "catalog runtime policy count drifted")
	assert(
		int(counts.get("runtime_spawnable_count", -1)) == GameData.monsters.size(),
		"runtime spawnable count is not the GameData runtime view"
	)
	assert(
		int(counts.get("runtime_rejected_count", -1))
		== int(counts.get("catalog_runtime_allowed_count", 0))
		- int(counts.get("runtime_spawnable_count", 0)),
		"runtime rejection count drifted"
	)
	assert(int(counts.get("runtime_spawnable_count", 0)) == 37, "final runtime monster count drifted")
	assert(int(counts.get("runtime_rejected_count", -1)) == 0, "final catalog retains runtime drop rejection")

	for monster_id: int in [64, 66, 68, 69, 73, 76]:
		var entry := GameData.get_monster_by_id(monster_id)
		assert(not entry.is_empty(), "canonical runtime ID rejected: %d" % monster_id)
		assert(int(entry.get("monster_id", -1)) == monster_id, "ID drifted")
		var drops := GameData.get_canonical_monster_drop_profile(monster_id)
		assert(not drops.is_empty(), "runtime hostile has no drop profile: %d" % monster_id)
		assert(not (drops.get("entries", []) as Array).is_empty(), "runtime hostile has empty drops: %d" % monster_id)
	var entries_by_id: Dictionary = GameData.canonical_monster_catalog.get(
		"entries_by_id", {}
	)
	assert(not entries_by_id.is_empty(), "canonical entries_by_id missing")
	for raw_entry: Variant in entries_by_id.values():
		if not raw_entry is Dictionary or not bool(raw_entry.get("runtime_allowed", false)):
			continue
		var catalog_entry: Dictionary = raw_entry
		if str(catalog_entry.get("classification", "")) in ["non_hostile", "script_object"]:
			continue
		var runtime_id := int(catalog_entry.get("monster_id", -1))
		var closure := GameData.canonical_monster_runtime_drop_closure(runtime_id)
		if int(closure.get("resolved_non_gold_count", 0)) > 0:
			assert(bool(closure.get("allowed", false)), "resolved hostile item closure rejected ID=%d" % runtime_id)
			assert(not GameData.get_monster_by_id(runtime_id).is_empty(), "resolved hostile missing from runtime ID=%d" % runtime_id)
		else:
			assert(not bool(closure.get("allowed", true)), "zero-resolution hostile entered runtime ID=%d" % runtime_id)
			assert(str(closure.get("reason", "")) == "drop_items_unresolved", "zero-resolution hostile lacks stable reason ID=%d" % runtime_id)
			assert(GameData.get_monster_by_id(runtime_id).is_empty(), "zero-resolution hostile escaped runtime gate ID=%d" % runtime_id)
	var non_hostile_194 := GameData.get_monster_by_id(194)
	assert(not non_hostile_194.is_empty(), "non_hostile ID 194 was treated as hostile")
	assert(
		str(non_hostile_194.get("classification", "")) == "non_hostile",
		"non_hostile classification token drifted"
	)

	_test_runtime_no_drop_rejection()

	for rejected: Variant in [0, -1, "", "64", "abc", "64x", 78, 239, 999999]:
		var monster_id := GameData.canonical_monster_id(rejected)
		if rejected in [78, 239, 999999]:
			monster_id = int(rejected)
		assert(
			GameData.get_monster_by_id(monster_id).is_empty(),
			"invalid/unresolved monster escaped runtime gate: %s" % str(rejected)
		)
	assert(GameData.get_monster("沃玛战士").is_empty(), "name-only lookup must fail closed")
	assert(
		GameData.get_bosses_for_map({"name": "沃玛教主大殿"}).is_empty(),
		"map-name Boss matching must remain retired"
	)
	assert(
		GameData.get_drops_for_boss(76)
		== GameData.get_calibrated_drops(76),
		"numeric Boss drop compatibility API bypassed canonical drops"
	)
	assert(
		GameData.get_canonical_monster_entry(64, "unknown_context").is_empty(),
		"unknown GameData context bypassed runtime policy"
	)

	var canonical_64 := GameData.get_monster_by_id(64)
	var wrong_display_payload := canonical_64.duplicate(true)
	wrong_display_payload["canonical_name"] = "WRONG DISPLAY NAME"
	wrong_display_payload["name"] = "WRONG LEGACY NAME"
	assert(
		int(GameData.get_monster_by_id(64).get("monster_id", -1)) == 64,
		"display text changed canonical identity"
	)

	_test_bridge_contract()
	_test_formal_runtime_bridge_projection()
	_test_region_content_contract()
	_test_loot_contract()
	await _test_game_root_spawn(wrong_display_payload)
	_test_source_contract()

	print(
		"MONSTER_WORLD_INTEGRATION_PASS: canonical_ids=6 "
		+ "bridge_fail_closed=1 loot_rows_76=107 game_root_id_only=1"
	)
	get_tree().quit(0)


func _test_bridge_contract() -> void:
	var runtime := {"design": {"design_size": [50, 50]}}
	var ordinary := BridgeScript._combat_spawn(runtime, {
		"monster_id": 64,
		"display_name": "WRONG DISPLAY NAME",
		"tile": [5, 6],
	}, "monster_spawn")
	assert(int(ordinary.get("monster_id", -1)) == 64, "bridge rejected canonical ordinary")
	assert(not ordinary.has("monsterId"), "bridge emitted retired monsterId field")
	assert(
		str(ordinary.get("name", ""))
		== str(GameData.get_monster_by_id(64).get("canonical_name", "")),
		"bridge trusted authored display name"
	)
	var json_numeric := BridgeScript._combat_spawn(runtime, {
		"monster_id": 64.0,
		"tile": [5, 6],
	}, "monster_spawn")
	assert(
		int(json_numeric.get("monster_id", -1)) == 64,
		"bridge rejected integral JSON numeric ID"
	)
	var elite := BridgeScript._combat_spawn(runtime, {
		"monster_id": 73,
		"tile": [7, 8],
	}, "boss_spawn")
	assert(int(elite.get("monster_id", -1)) == 73, "bridge rejected canonical elite")
	assert(not bool(elite.get("is_boss", true)), "elite was promoted to boss")
	var boss := BridgeScript._combat_spawn(runtime, {
		"monster_id": 76,
		"tile": [7, 8],
	}, "boss_spawn")
	assert(int(boss.get("monster_id", -1)) == 76, "bridge rejected canonical boss")
	assert(bool(boss.get("is_boss", false)), "canonical boss lost boss identity")
	for malformed: Dictionary in [
		{"monster_id": 0, "tile": [0, 0]},
		{"monster_id": 64.5, "tile": [0, 0]},
		{"monster_id": true, "tile": [0, 0]},
		{"monster_id": "abc", "tile": [0, 0]},
		{"monster_id": "monster.64x", "tile": [0, 0]},
		{"monster_id": "monster.64", "tile": [0, 0]},
		{"boss_id": 76, "tile": [0, 0]},
		{"content_id": 64, "tile": [0, 0]},
		{"monster_id": 64, "boss_id": 76, "tile": [0, 0]},
		{"monster_id": 64, "monsterId": 64, "tile": [0, 0]},
		{"name": "沃玛战士", "tile": [0, 0]},
		{"monster_id": 78, "tile": [0, 0]},
		{"boss_id": "boss.239", "tile": [0, 0]},
		{"monster_id": 64, "tile": [0, 0]},
	]:
		var raw_monster_id: Variant = malformed.get("monster_id", null)
		var placement := (
			"boss_spawn"
			if raw_monster_id is int and int(raw_monster_id) == 64
			else "monster_spawn"
		)
		assert(
			BridgeScript._combat_spawn(runtime, malformed, placement).is_empty(),
			"bridge accepted malformed/unresolved identity: %s" % str(malformed)
		)


func _test_formal_runtime_bridge_projection() -> void:
	var raw_total := 0
	var projected_total := 0
	for runtime_map_id: int in BridgeScript.released_map_ids():
		var loaded := RuntimeMapServiceScript.load_runtime(
			BridgeScript.runtime_path(runtime_map_id)
		)
		assert(bool(loaded.get("ok", false)), "formal runtime failed validation: %d" % runtime_map_id)
		var runtime: Dictionary = loaded.get("runtime", {})
		var semantics: Dictionary = runtime.get("semantics", {})
		var raw_spawns: Array = semantics.get("monster_spawn", [])
		var raw_bosses: Array = semantics.get("boss_spawn", [])
		var projected := BridgeScript.game_content_for_map(runtime_map_id)
		var projected_spawns: Array = projected.get("spawns", [])
		var projected_bosses: Array = projected.get("bosses", [])
		assert(
			projected_spawns.size() == raw_spawns.size(),
			"bridge lost canonical ordinary spawns on map %d" % runtime_map_id
		)
		assert(
			projected_bosses.size() == raw_bosses.size(),
			"bridge lost canonical elite/boss spawns on map %d" % runtime_map_id
		)
		raw_total += raw_spawns.size() + raw_bosses.size()
		projected_total += projected_spawns.size() + projected_bosses.size()
	assert(raw_total == 107, "formal canonical spawn total drifted")
	assert(projected_total == raw_total, "bridge dropped canonical formal spawns")


func _test_loot_contract() -> void:
	var loot_runtime := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260815
	var wooma_boss := loot_runtime.roll_monster_drops(76, rng, 6)
	assert(bool(wooma_boss.get("configured", false)), "ID 76 drop profile not configured")
	assert(int(wooma_boss.get("source_entry_count", 0)) == 107, "ID 76 must expose all 107 source rows")
	assert(int(wooma_boss.get("resolution_attempted_count", 0)) == 107, "ID 76 rows did not enter item resolution")
	assert(int(wooma_boss.get("resolved_entry_count", 0)) > 0, "ID 76 is configured but can never produce an item")
	assert(
		int(wooma_boss.get("resolved_entry_count", -1))
		+ (wooma_boss.get("rejected_entries", []) as Array).size()
		== 107,
		"every ID 76 row must resolve or carry a stable rejection"
	)
	for monster_id: int in [68, 69]:
		var ordinary_roll := loot_runtime.roll_monster_drops(
			monster_id, rng, 6
		)
		assert(
			bool(ordinary_roll.get("configured", false)),
			"ID %d drops not configured" % monster_id
		)
		assert(
			int(ordinary_roll.get("resolved_entry_count", 0)) > 0,
			"ID %d has no resolvable drop" % monster_id
		)
	for rejected: Variant in [0, 78, 239, 999999]:
		var rejected_roll := loot_runtime.roll_monster_drops(int(rejected), rng, 6)
		assert(not bool(rejected_roll.get("configured", false)), "rejected monster rolled drops")
		assert(not str(rejected_roll.get("reason", "")).is_empty(), "rejected roll has no reason")
	var bad_item := GameData.resolve_canonical_drop_item({
		"chance": "1/1",
		"item": "definitely-not-a-canonical-item",
	})
	assert(not bool(bad_item.get("ok", false)), "unknown item token escaped authority")
	assert(str(bad_item.get("reason", "")) == "unknown_item_token", "bad item reason drifted")


func _test_region_content_contract() -> void:
	var migrated := RegionContent._canonical_combat_entry({
		"monster_id": 64,
		"name": "WRONG LEGACY NAME",
		"position": Vector2.ZERO,
	})
	assert(int(migrated.get("monster_id", -1)) == 64, "canonical numeric ID was not projected")
	assert(not migrated.has("monsterId"), "RegionContent leaked retired monsterId")
	assert(
		str(migrated.get("name", ""))
		== str(GameData.get_monster_by_id(64).get("canonical_name", "")),
		"RegionContent trusted legacy display text"
	)
	for rejected: Dictionary in [
		{"name": "沃玛战士"},
		{"monsterId": 64},
		{"monsterId": "64"},
		{"monster_id": "monster.64"},
		{"monster_id": 64, "monsterId": 64},
		{"monster_id": 64, "content_id": "monster.64"},
		{"monster_id": 64, "boss_id": "boss.76"},
		{"monster_id": 64.5},
		{"monster_id": 78},
	]:
		assert(
			RegionContent._canonical_combat_entry(rejected).is_empty(),
			"RegionContent accepted non-canonical record: %s" % str(rejected)
		)
	var map_content := RegionContent.get_map_content(4)
	assert(not map_content.is_empty(), "RegionContent map 4 missing")
	for layer_name: String in ["spawns", "bosses"]:
		for raw_entry: Variant in map_content.get(layer_name, []):
			assert(raw_entry is Dictionary, "RegionContent combat row invalid")
			var entry: Dictionary = raw_entry
			assert(int(entry.get("monster_id", -1)) > 0, "RegionContent row has no stable ID")
			assert(not entry.has("monsterId"), "RegionContent map leaked monsterId")
			assert(not entry.has("is_boss"), "RegionContent emitted redundant is_boss")
			assert(not GameData.get_monster_by_id(int(entry.monster_id)).is_empty(), "RegionContent row bypassed runtime gate")
	var domain_runtime := DomainRuntimeServicesScript.new()
	var spawn_rules := domain_runtime.spawn_rules(4)
	assert(
		spawn_rules.get("spawns", []) == map_content.get("spawns", []),
		"DomainRuntimeServices bypassed RegionContent canonical spawns"
	)
	assert(
		spawn_rules.get("bosses", []) == map_content.get("bosses", []),
		"DomainRuntimeServices bypassed RegionContent canonical bosses"
	)


func _test_runtime_no_drop_rejection() -> void:
	# The final catalog is expected to close every runtime hostile drop table.
	# Temporarily replace one already-built closure to exercise the real public
	# GameData, bridge and LootRuntime rejection paths without inventing a test
	# monster or changing the generated catalog.
	var saved_closure: Dictionary = GameData._monster_runtime_drop_closure.get(
		64, {}
	).duplicate(true)
	GameData._monster_runtime_drop_closure[64] = {
		"allowed": false,
		"reason": "drop_items_unresolved",
		"resolved_non_gold_count": 0,
	}
	assert(GameData.get_monster_by_id(64).is_empty(), "no-drop GameData gate failed")
	var bridge_result := BridgeScript._combat_spawn(
		{"design": {"design_size": [50, 50]}},
		{"monster_id": 64, "tile": [0, 0]},
		"monster_spawn"
	)
	assert(bridge_result.is_empty(), "no-drop bridge gate failed")
	var rng := RandomNumberGenerator.new()
	var roll := LootRuntimeScript.new().roll_monster_drops(64, rng, 6)
	assert(not bool(roll.get("configured", false)), "no-drop loot was configured")
	assert(
		str(roll.get("reason", "")) == "drop_items_unresolved",
		"no-drop loot reason drifted"
	)
	GameData._monster_runtime_drop_closure[64] = saved_closure


func _test_game_root_spawn(wrong_display_payload: Dictionary) -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.current_map_id = -1
	assert(
		GameData.canonical_monster_id(wrong_display_payload.get("monster_id")) == 64,
		"test payload lost canonical ID"
	)
	assert(
		not GameData.get_monster_by_id(64).is_empty(),
		"GameData lost canonical ID after GameRoot ready"
	)
	var enemy: EnemyActor = game._spawn_enemy(
		wrong_display_payload,
		Vector2(160, 80),
		true,
		180.0,
		{"spawn_slot_id": "canonical:test:64"}
	)
	assert(enemy != null, "GameRoot rejected valid canonical ID")
	assert(enemy.monster_id == 64, "GameRoot identity drifted")
	assert(not enemy.is_boss, "caller boss flag overrode canonical classification")
	assert(
		enemy.display_name
		== str(GameData.get_monster_by_id(64).get("canonical_name", "")),
		"GameRoot/Enemy trusted wrong display text"
	)
	assert(
		game._spawn_enemy({"monster_id": 78}, Vector2.ZERO, false) == null,
		"GameRoot spawned runtime-disabled ID"
	)
	assert(
		game._spawn_enemy({"name": "沃玛战士"}, Vector2.ZERO, false) == null,
		"GameRoot accepted name-only spawn"
	)
	for rejected: Dictionary in [
		{"monsterId": 64},
		{"monster_id": "64"},
		{"monster_id": "monster.64"},
		{"monster_id": 64.5},
		{"monster_id": 64, "monsterId": 64},
		{"monster_id": 64, "content_id": "monster.64"},
	]:
		assert(
			game._spawn_enemy(rejected, Vector2.ZERO, false) == null,
			"GameRoot accepted non-canonical spawn: %s" % str(rejected)
		)
	game.queue_free()


func _test_source_contract() -> void:
	var bridge_source := FileAccess.get_file_as_string(
		"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
	)
	assert(
		'"monsterId"' not in bridge_source,
		"bridge retains retired monsterId transport output"
	)
	var game_root_source := FileAccess.get_file_as_string(
		"res://scripts/game_root.gd"
	)
	assert(
		'.get("monsterId"' not in game_root_source,
		"GameRoot retains retired monsterId transport fallback"
	)
	var region_source := FileAccess.get_file_as_string(
		"res://scripts/region_content.gd"
	)
	assert(
		'.get("monsterId"' not in region_source,
		"RegionContent retains runtime monsterId conversion"
	)
	var domain_source := FileAccess.get_file_as_string(
		"res://scripts/layers/runtime/domain_runtime_services.gd"
	)
	assert(
		"var content := map_content(map_id)" not in domain_source,
		"domain spawn_rules still exposes raw WorldContent"
	)
	assert(
		"var content := RegionContent.get_map_content(map_id)" in domain_source,
		"domain spawn_rules lost canonical RegionContent boundary"
	)
	for path: String in [
		"res://scripts/game_root.gd",
		"res://scripts/region_content.gd",
		"res://scripts/layers/runtime/domain_runtime_services.gd",
		"res://scripts/layers/runtime/loot_runtime_service.gd",
		"res://scripts/layers/runtime/map_editor_runtime_bridge.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		for forbidden: String in [
			"GameData.get_monster(",
			"WorldContent.monster_drops(",
			"baseName",
		]:
			assert(forbidden not in source, "%s retains production fallback %s" % [path, forbidden])
	var map_panel_source := FileAccess.get_file_as_string(
		"res://scripts/map_panel.gd"
	)
	assert(
		"GameData.get_bosses_for_map(" not in map_panel_source,
		"map panel still guesses Bosses from legacy map/name metadata"
	)
