extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.warrior.half_moon":3,"hc.skill.warrior.basic_swordsmanship":3,"hc.skill.warrior.slaying_swordsmanship":3}
	PlayerState.recalculate_stats(false)
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "mapped melee world READY")
	check(game.has_method("_capture_melee_configuration"), "melee has an explicit accepted configuration owner")
	if not game.gameplay_input_is_enabled() or not game.has_method("_capture_melee_configuration"):
		game.queue_free()
		_finish()
		return
	var target := await Fixture.prepare_target(self, game, game.player, 19, "melee_configuration")
	check(target != null, "formal receiver exists")
	if target == null:
		_finish()
		return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.half_moon_enabled = true
	game.player.fire_sword_enabled = false
	game.player.thrusting_enabled = false
	game.player.current_mp = 100
	var lease: RefCounted = game.call("_capture_melee_configuration")
	check(lease != null and lease.definition_for("hc.skill.warrior.half_moon").entity_id == "hc.skill.warrior.half_moon", "formal IDs select the accepted body definition")
	game.player.current_mp = 2
	var underfunded: Dictionary = game.player._build_warrior_attack_context(true, lease)
	check(underfunded.mode == "normal", "unaccepted candidate uses its real definition for input MP eligibility")
	game.player.current_mp = 100
	var stale: RefCounted = game.call("_capture_melee_configuration")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true), "change relevant configuration before melee acceptance")
	var action_before: int = game.player._combat_action_sequence
	var rng_before: int = game.player._rng.state
	var facing_before: Vector2 = game.player.facing
	check(not bool(game.player.call("request_attack_toward", Vector2.UP, true, target.get_instance_id(), stale)) \
		and game.player.current_mp == 100 and game.player._rng.state == rng_before \
		and game.player._combat_action_sequence == action_before and game.player.facing == facing_before, "stale melee rejects before facing, MP, RNG and action ownership")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false), "restore declared configuration before accepted swing")
	lease = game.call("_capture_melee_configuration")
	var before_hp: int = target.current_hp
	check(bool(game.player.call("request_attack_toward", Vector2.RIGHT, true, target.get_instance_id(), lease)), "natural melee input accepts the supplied lease")
	check(lease.is_accepted() and game.observed_releases == 0, "delayed melee accepts before release")
	PlayerState.learned_skills = {"hc.skill.warrior.half_moon":1}
	PlayerState.recalculate_stats(false)
	game.player.half_moon_enabled = false
	deadline = Time.get_ticks_msec() + 3000
	while game.observed_releases == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.observed_releases == 1 and is_same(game.observed_configuration, lease), "same accepted lease reaches the sole melee planner once")
	var plan: Dictionary = game.observed_execution.get("canonical_plan", {})
	check(bool(game.observed_execution.get("accepted", false)) and int(plan.get("effective_rank", -1)) == 3, "mid-windup downgrade and toggle changes do not replace accepted body rank")
	check(game.player.current_mp == 97 and int(plan.get("resource_cost", {}).get("mp_cost", -1)) == 3, "same accepted definition quotes and commits melee MP")
	check(target.current_hp < before_hp, "real receiver commits the accepted melee hit")
	check(lease.melee_context().learned_skills.has("hc.skill.warrior.basic_swordsmanship") and lease.rank_for("hc.skill.warrior.basic_swordsmanship") == 3, "passive configuration belongs to the accepted swing")
	game.queue_free()
	await get_tree().process_frame
	_finish()
func _finish() -> void:
	if not proof.write_receipt("melee_configuration_production_test", checks, errors.size()): errors.append("receipt")
	print(("FRAMEWORK_MELEE_CONFIGURATION_PASS" if errors.is_empty() else "FRAMEWORK_MELEE_CONFIGURATION_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
