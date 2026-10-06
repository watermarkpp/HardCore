extends Node
## F4 minimal contrast probe (GPT-Pro review directive, fixed ad29a835e).
## The legacy bich_area_test stays untouched as the RED record. This probe
## keeps test_mode=false through the travel so _should_animate_map_transition
## returns true and _begin_map_transition owns the real staged birth-plan
## collection window (begin_actor_collection -> _load_zone spawns -> seal),
## waits for the real READY, prints the acceptance trail, then runs the
## ORIGINAL count/boss/portal assertions with the editor-authored expectations
## unchanged. No expectation is lowered, no spawn permission is injected and
## no authored monster table is modified.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()
func check(value: bool, label: String) -> void:
	checks += 1; proof.record(value, label)
	if not value: errors.append(label)

func _ready() -> void: _run.call_deferred()
func _finish(ok: bool, label: String) -> void:
	if not label.is_empty(): check(false, label)
	check(proof.write_receipt("bich_formal_transition_probe_test", checks, errors.size()), "receipt")
	print("BICH_FORMAL_PROBE_RESULT_", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _run() -> void:
	# Same formal first arrival as the legacy fixture, still test_mode=false.
	PlayerState.test_mode = false
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var bootstrap_deadline := Time.get_ticks_msec() + 60000
	while (
		(game._world_bootstrap_in_progress or game._map_transition_in_progress)
		and Time.get_ticks_msec() < bootstrap_deadline
	):
		await get_tree().process_frame
	if game._world_bootstrap_in_progress or game._map_transition_in_progress:
		_finish(false, "initial bootstrap did not settle within 60s"); return
	if not game.gameplay_input_is_enabled():
		_finish(false, "initial world never reached gameplay-ready"); return
	print("BICH_FORMAL_PROBE initial_ready map=%d generation=%d" % [game.current_map_id, game._zone_generation])
	# The contrast: travel WITH the formal transition window active. test_mode
	# stays false, so _request_map_travel must route through
	# _begin_map_transition (the real plan collection + seal), not the
	# synchronous _travel_to_map_immediate shortcut. travel_to_map returns
	# void, so "started" is observed as the transition flag actually rising.
	game.travel_to_map(911001)
	var travel_started := false
	var transition_deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < transition_deadline:
		await get_tree().process_frame
		if game._map_transition_in_progress:
			travel_started = true
			break
	while game._map_transition_in_progress and Time.get_ticks_msec() < transition_deadline:
		await get_tree().process_frame
	var transition_settled: bool = not game._map_transition_in_progress and Time.get_ticks_msec() <= transition_deadline
	var ready: bool = transition_settled and game.gameplay_input_is_enabled()
	var expected: int = _runtime_enemy_count(911001)
	var actual: int = get_tree().get_nodes_in_group("enemies").size()
	var bound: Dictionary = game.feature_world_capacity_bound()
	print("BICH_FORMAL_PROBE travel_started=%s settled=%s ready=%s map=%d zone=%s generation=%d" % [
		str(travel_started), str(transition_settled), str(ready), game.current_map_id, str(game.current_zone), game._zone_generation])
	print("BICH_FORMAL_PROBE enemies=%d expected=%d bosses=%d canonical_bosses=%d sealed=%s staged_failure_reason=%s" % [
		actual, expected, _boss_count(), _canonical_boss_placement_count(911001),
		str(bool(bound.get("sealed", false))), str(game._staged_actor_spawn_failure_reason)])
	if not travel_started:
		_finish(false, "formal travel was refused outright"); return
	if not transition_settled:
		_finish(false, "formal transition did not settle within 60s"); return
	if not ready:
		_finish(false, "formal transition settled but never reached gameplay-ready"); return
	check(travel_started, "formal travel routed through the real transition window")
	check(transition_settled, "formal transition settled within 60s")
	check(ready, "formal transition reached gameplay-ready")
	check(bool(bound.get("sealed", false)), "formal plan sealed the world capacity bound")
	check(str(game._staged_actor_spawn_failure_reason).is_empty(), "no staged spawn failure reason recorded")
	# ORIGINAL assertions, editor-authored expectations unchanged.
	check(game.current_zone == "兽人古墓一层", "未进入兽人古墓一层")
	check(actual == expected, "一层编辑器怪物配置未完整加载 (actual=%d expected=%d)" % [actual, expected])
	check(_boss_count() == _canonical_boss_placement_count(911001), "一层Boss身份与canonical分类不一致")
	check(_zone_portal_count() == MapEditorRuntimeBridge.game_content_for_map(911001).portals.size(), "一层双向门点不完整")
	_finish(errors.is_empty(), "")

func _boss_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			count += 1
	return count

func _canonical_boss_placement_count(map_id: int) -> int:
	var count := 0
	for placement: Dictionary in MapEditorRuntimeBridge.game_content_for_map(map_id).get("bosses", []):
		var monster := GameData.get_monster_by_id(int(placement.get("monster_id", -1)))
		if str(monster.get("classification", "")) == "boss":
			count += maxi(1, mini(
				int(placement.get("count", 1)),
				int(placement.get("max_alive", placement.get("count", 1)))
			))
	return count

func _runtime_enemy_count(map_id: int) -> int:
	var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
	var count: int = content.get("bosses", []).size()
	for spawn: Dictionary in content.get("spawns", []):
		count += maxi(1, mini(
			int(spawn.get("count", 1)),
			int(spawn.get("max_alive", spawn.get("count", 1)))
		))
	return count

func _zone_portal_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal:
			count += 1
	return count
