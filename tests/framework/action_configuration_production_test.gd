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
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"雷电术":3}
	PlayerState.recalculate_stats(false)
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "mapped production world becomes READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return
	var target := await Fixture.prepare_target(self, game, game.player, 19, "framework_action_config")
	check(target != null and target.projection_ready(), "formal exact-ID receiver ready")
	if target == null:
		_finish()
		return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true), "activate declared configuration through content owner")
	var stale: RefCounted = game._capture_action_configuration("wizard.lightning")
	check(stale != null, "production graph creates immutable action lease")
	if stale == null:
		_finish()
		return
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false), "change configuration before acceptance")
	var rng_before: int = game._rng.state
	var mana_before: int = game.player.current_mp
	var action_before: int = game.player._combat_action_sequence
	var serial_before: int = game._canonical_cast_serial
	check(not game.player.request_skill("雷电术", target.get_instance_id(), stale), "stale request fails before acceptance")
	check(game._rng.state == rng_before and game.player.current_mp == mana_before and game._canonical_cast_serial == serial_before
		and game.player._combat_action_sequence == action_before and not stale.is_accepted(), "stale rejection changes no MP, RNG, action permit or release identity")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true), "reactivate exact module for accepted cast")
	PlayerState.computed_stats["magic_min"] = 100
	PlayerState.computed_stats["magic_max"] = 100
	var accepted: RefCounted = game._capture_action_configuration("hc.skill.wizard.lightning")
	game.player.current_mp = 100
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	check(game.player.request_skill("hc.skill.wizard.lightning", target.get_instance_id(), accepted), "formal ID natural player request accepts lease before windup")
	check(accepted.is_accepted() and game.observed_releases == 0, "accepted delayed action has not yet released")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false), "content changes during accepted windup")
	PlayerState.learned_skills = {"雷电术":1}
	PlayerState.level = 45
	PlayerState.recalculate_stats(false)
	var mana_at_release: int = game.player.current_mp
	var hp_before: int = target.current_hp
	deadline = Time.get_ticks_msec() + 3000
	while game.observed_releases == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.observed_releases == 1 and is_same(game.observed_configuration, accepted), "actual player signal transports the same accepted lease once")
	var result: Dictionary = game.observed_execution
	check(bool(result.get("accepted", false)) and target.current_hp < hp_before, "actual single planner commits damage through production receiver")
	var plan: Dictionary = result.get("canonical_plan", {})
	check(int(plan.get("effective_rank", -1)) == 3, "accepted rank survives later skill downgrade")
	check(int(plan.get("resource_cost", {}).get("mp_cost", -1)) == 16 and game.player.current_mp == mana_at_release - 16,
		"input configuration, router quote and actual MP commit use old rank3 plus declared cost")
	check(plan.get("cooldown_contract", {}) == accepted.definition_for("wizard.lightning").timing,
		"canonical timing uses accepted definition")
	check(int(game.observed_target_context.get("primary_stat_roll", -1)) == 100, "formula reads accepted stat bounds at the old release RNG boundary")
	check(bool(result.get("plan_immutable", {}).get("valid", false)), "accepted plan remains immutable after application")
	check(game.player.begin_combat_transition("framework-life-invalidation"), "formal lifecycle transition starts")
	check(game.player.finish_combat_transition("framework-life-invalidation"), "formal lifecycle transition completes")
	rng_before = game._rng.state
	serial_before = game._canonical_cast_serial
	hp_before = target.current_hp
	var rejected := game._execute_canonical_skill("雷电术", game.player.global_position, Vector2.RIGHT, 999,
		{}, true, true, accepted)
	check(not bool(rejected.accepted) and game._rng.state == rng_before and game._canonical_cast_serial == serial_before
		and target.current_hp == hp_before, "old-life accepted lease is rejected before RNG and HP write")
	game.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	if not proof.write_receipt("action_configuration_production_test", checks, errors.size()):
		errors.append("receipt failed")
	print(("FRAMEWORK_ACTION_CONFIGURATION_PRODUCTION_PASS" if errors.is_empty() else "FRAMEWORK_ACTION_CONFIGURATION_PRODUCTION_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
