extends Node

## Catches a builder or published map omitting an admitted monster's exact body.
const Body := preload("res://scripts/actor_body_policy.gd")
const Inputs := preload("res://scripts/features/contracts/published_monster_inputs.gd")
const Build := preload("res://scripts/map_editor/polygon/poly_build.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const MapBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Background := preload("res://scripts/world_background.gd")
const SCENE_ID := "published_monster_navigation_coverage_v113_test"
const REGISTRY := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Build.CATALOG_PATH))
	var inventory := Build.collect_radii()
	check(bool(inventory.get("ok", false)), "builder radius inventory resolves")
	_inventory_negative_cases(catalog)
	var monsters: Array[Dictionary] = []
	var required: Dictionary = {}
	for key: String in catalog.entries_by_id:
		var entry: Dictionary = catalog.entries_by_id[key]
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var id := int(key)
		var capture := Inputs.capture(id, {}, {})
		check(capture != null and capture.valid_for(id), "formal inputs monster=%d" % id)
		if capture == null:
			continue
		var view: Dictionary = capture.view()
		var body := Body.resolve_monster_body(id, str(view.entry.classification), view.body)
		check(not body.is_empty(), "identity-bound body monster=%d" % id)
		if body.is_empty():
			continue
		var radius := WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(float(body.screen_radius_px))
		var radius_key := Graph.key_for_radius(radius)
		required[radius_key] = radius
		monsters.append({"monster_id": id, "tier": body.tier, "radius_gu": radius, "radius_key": radius_key})
		check(inventory.get("radii", {}).has(radius_key), "builder covers admitted monster=%d exact_key=%s" % [id, radius_key])
	check(monsters.size() == 156, "v113 complete runtime_allowed inventory 156")
	check(absf(float(monsters.filter(func(row: Dictionary) -> bool: return row.monster_id == 236)[0].radius_gu) - 0.5) < 0.000000000001, "large production body remains nominal 0.5 GU without rounding exact key")
	var body236 := MonsterIdentity.body_profile(236)
	check(Body.resolve_monster_body(236, "boss", {}).is_empty(), "missing body rejected")
	var malformed: Dictionary = body236.duplicate(true)
	malformed.screen_radius_px = "22.627"
	check(Body.resolve_monster_body(236, "boss", malformed).is_empty(), "malformed body rejected")
	check(Body.resolve_monster_body(64, "ordinary", body236).is_empty(), "foreign assignment body rejected")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	var maps: Array = []
	var visual_loader := Background.new()
	for entry: Dictionary in registry.maps:
		if str(entry.get("release_state", "")) != "implemented_playable":
			continue
		var map_id := int(entry.runtime_map_id)
		var runtime := MapBridge.load_map(map_id)
		check(not runtime.is_empty(), "formal approved MapBridge release load map=%d" % map_id)
		if runtime.is_empty():
			maps.append({"map_id": map_id, "formal_load": "FAIL", "coverage": []})
			continue
		var visual: Dictionary = visual_loader._load_editor_runtime_visual(map_id, runtime)
		check(not visual.is_empty(), "formal runtime visual loader accepts map=%d" % map_id)
		if map_id == 918005:
			var missing: Dictionary = runtime.duplicate(true)
			missing.collision.navigation.profiles = []
			check(not Build.validate_monster_coverage(missing).ok, "publication rejects absent required profiles")
			var wrong: Dictionary = runtime.duplicate(true)
			for profile: Dictionary in wrong.collision.navigation.profiles:
				profile.radius_key = "0000000000000000"
			check(not Build.validate_monster_coverage(wrong).ok, "publication rejects foreign or malformed profile keys")
		check(str(runtime.get("build_sha256", "")) == str(entry.approved_build_sha256), "approved build map=%d" % map_id)
		var profiles: Dictionary = {}
		for profile: Dictionary in runtime.get("collision", {}).get("navigation", {}).get("profiles", []):
			profiles[str(profile.get("radius_key", ""))] = profile
		var ready: Dictionary = {}
		for radius_key: String in required:
			if not profiles.has(radius_key):
				continue
			var graph := Graph.new()
			var size_data: Array = runtime.design.design_size
			var result := graph.setup(profiles[radius_key], Vector2i(int(size_data[0]), int(size_data[1])))
			ready[radius_key] = bool(result.ok) and graph.ready
		var rows: Array = []
		for monster: Dictionary in monsters:
			var covered := bool(ready.get(monster.radius_key, false))
			check(covered, "published coverage map=%d monster=%d key=%s" % [map_id, monster.monster_id, monster.radius_key])
			rows.append({"monster_id": monster.monster_id, "radius_key": monster.radius_key, "status": "PASS" if covered else "FAIL"})
		maps.append({"map_id": map_id, "build_sha256": runtime.get("build_sha256", ""), "formal_load": "PASS", "visual_load": "PASS" if not visual.is_empty() else "FAIL", "coverage": rows})
	visual_loader.free()
	check(maps.size() == 67, "v113 all 67 implemented playable maps checked")
	var evidence := {"monsters": monsters, "maps": maps, "failures": failures, "checks": checks}
	FileAccess.open("user://published_monster_navigation_coverage_v113.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	var receipt_ok := proof.write_receipt(SCENE_ID, checks, failures.size())
	print("PUBLISHED_MONSTER_NAVIGATION_COVERAGE_", "PASS" if failures.is_empty() and receipt_ok else "FAIL", " checks=", checks, " failures=", failures.size(), " maps=", maps.size(), " monsters=", monsters.size())
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)

func _inventory_negative_cases(catalog: Dictionary) -> void:
	var entry: Dictionary = catalog.entries_by_id["236"].duplicate(true)
	var sample := {"entries_by_id": {"236": entry}}
	var valid := Build.collect_body_radii(sample)
	check(valid.ok, "build inventory accepts canonical identity-bound body")
	if valid.ok:
		var roundtrip: Dictionary = Codec.decode(Codec.encode({"radii": valid.radii}))
		for key: String in valid.radii:
			check(Graph.key_for_radius(float(roundtrip.radii[key])) == key, "formal JSON roundtrip preserves exact factory radius key=%s" % key)
	for field: String in ["tier", "policy_sha256", "assignment_rule", "screen_radius_px", "ground_radius_gu"]:
		var changed: Dictionary = sample.duplicate(true)
		changed.entries_by_id["236"].combat.body_profile[field] = "invalid"
		check(not Build.collect_body_radii(changed).ok, "build rejects malformed body field=" + field)
	var missing: Dictionary = sample.duplicate(true)
	missing.entries_by_id["236"].combat.erase("body_profile")
	check(not Build.collect_body_radii(missing).ok, "build rejects missing body instead of legacy fallback")
	var unknown: Dictionary = entry.duplicate(true)
	unknown.monster_id = 999999
	check(not Build.collect_body_radii({"entries_by_id": {"999999": unknown}}).ok, "build rejects unknown identity")
	var identity_mismatch: Dictionary = sample.duplicate(true)
	identity_mismatch.entries_by_id["236"].monster_id = 64
	check(not Build.collect_body_radii(identity_mismatch).ok, "build rejects mismatched catalog key and identity")
	var foreign: Dictionary = sample.duplicate(true)
	foreign.entries_by_id["236"].combat.body_profile = MonsterIdentity.body_profile(64)
	check(not Build.collect_body_radii(foreign).ok, "build rejects body from foreign assignment")
	var classification: Dictionary = sample.duplicate(true)
	classification.entries_by_id["236"].classification = "unknown"
	check(not Build.collect_body_radii(classification).ok, "build rejects unknown classification")
