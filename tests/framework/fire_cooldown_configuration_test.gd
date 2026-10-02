extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Catalog := preload("res://scripts/features/compilation/feature_catalog.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const MODULE := "hc.cooldown_probe"
const FIRE := "hc.skill.warrior.fire_sword"
var proof := Proof.new()
var failures: Array[String] = []
var measurements: Array = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {FIRE: 3}
	PlayerState.recalculate_stats(false)
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual mapped world is READY")
	if not game.gameplay_input_is_enabled():
		game.queue_free()
		_finish()
		return
	var target := await Fixture.prepare_target(self, game, game.player, 19, "fire_cooldown_configuration")
	check(target != null, "real exact-ID melee receiver is available")
	if target == null:
		game.queue_free()
		_finish()
		return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	# A legal compiled fixture replaces only the in-memory content input. Real
	# qualification, activation, accepted lease, planner, HP and cooldown execute.
	var module: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/numeric_fixture.json"))
	module.module_id = MODULE
	module.capabilities = ["skills.modify"]
	module.mechanics = [{"mechanic_id": "hc.cooldown_probe.fire", "kind": "skill", "tags": [],
		"operations": [{"skill_id": FIRE, "field": "timing.cooldown_ms", "op": "multiply", "value": 0.5}]}]
	var authority := Authority.build()
	var candidate := Catalog.new()
	check(candidate.publish([module], [], authority), "cooldown x0.5 is legal under the actual compiler and authority")
	if candidate.catalog().is_empty():
		game.queue_free()
		_finish()
		return
	ContentLayers._feature_catalog = candidate
	ContentLayers._feature_authority = authority
	ContentLayers._feature_bindings = Graph.capture([{"module_id": MODULE, "kind": "skill", "skill_id": FIRE,
		"mechanic_id": "hc.cooldown_probe.fire"}]).value
	ContentLayers._enabled_feature_modules = []
	ContentLayers.feature_catalog_changed.emit()
	check(PlayerState.feature_bundle().sources.is_empty(), "default-OFF fixture makes no contribution")
	await _attack(game, target, "empty extension", false, false, false)
	await _attack(game, target, "legal half cooldown", true, false, false)
	await _attack(game, target, "accepted half cooldown then module OFF", true, true, false)
	await _attack(game, target, "accepted half cooldown then cast speed changes", true, false, true)
	check(ContentLayers.reload_feature_catalog(), "actual authoring catalog restored after fixture")
	game.queue_free()
	await get_tree().process_frame
	_finish()

func _attack(game: Node, target: EnemyActor, label: String, enabled: bool, disable_after: bool, speed_after: bool) -> void:
	var state := ContentLayers.feature_configuration()
	if state.enabled_modules.has(MODULE) != enabled:
		check(ContentLayers.set_feature_module_enabled(MODULE, enabled), label + ": activate through actual content owner")
	PlayerState.recalculate_stats(false)
	game.player.fire_sword_enabled = true
	game.player.half_moon_enabled = false
	game.player.thrusting_enabled = false
	game.player._skill_cooldown_remaining.clear()
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game.player.current_mp = 100
	game.observed_releases = 0
	var lease: RefCounted = game._capture_melee_configuration()
	check(lease != null, label + ": accepted candidate has a configuration owner")
	if lease == null: return
	var definition: Dictionary = lease.definition_for(FIRE)
	var base_cooldown := int(Loader.skill(FIRE).timing.cooldown_ms)
	var expected_definition := int(base_cooldown * 0.5) if enabled else base_cooldown
	check(int(definition.timing.cooldown_ms) == expected_definition,
		label + ": real qualified definition contains the declared cooldown")
	var before_hp := target.current_hp
	var expected_ms := ceili(float(expected_definition) / game.player._cast_speed_multiplier)
	check(game.player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id(), lease)
		and lease.is_accepted(), label + ": natural melee input accepts this lease")
	if disable_after:
		check(ContentLayers.set_feature_module_enabled(MODULE, false), label + ": content changes after acceptance")
	if speed_after:
		PlayerState.computed_stats["cast_speed_percent"] = 2.0
		PlayerState.profile_changed.emit()
		check(is_equal_approx(game.player._cast_speed_multiplier, 3.0), label + ": real profile consumer updates live speed")
	var deadline := Time.get_ticks_msec() + 3000
	while game.observed_releases == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.observed_releases == 1 and is_same(game.observed_configuration, lease),
		label + ": same configuration reaches the real planner once")
	check(target.current_hp < before_hp, label + ": actual target HP was committed")
	var actual_ms: int = game.player.skill_cooldown_remaining_ms("warrior.fire_sword")
	check(actual_ms == expected_ms, label + ": final cooldown equals the accepted configuration")
	measurements.append({"case": label, "base_cooldown_ms": base_cooldown, "accepted_cooldown_ms": expected_definition,
		"expected_committed_ms": expected_ms, "actual_committed_ms": actual_ms,
		"actual_hp_loss": before_hp - target.current_hp, "remaining_mp": game.player.current_mp})

func _finish() -> void:
	proof.write_receipt("fire_cooldown_configuration_test", proof.records.size(), failures.size())
	print("FIRE_COOLDOWN_CONFIGURATION_%s checks=%d measurements=%s failures=%s" % [
		"PASS" if failures.is_empty() else "FAIL", proof.records.size(), JSON.stringify(measurements), str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
