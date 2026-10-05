extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/feature_batch_failure_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.set_profession_identity("hc.profession.wizard")
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"formal world ready")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,19,"feature_batch_failure")
	check(target != null,"actual selected receiver exists")
	if target == null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp = 10000; target.current_hp = 10000
	target.direct_spell_anti_magic_points = 0; target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	target.direct_spell_stats_valid = true
	PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	game.player.current_mp = 100; game._skill_cast_target = target; game._set_magic_locked_target(target,true)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"actual default-off module enabled")
	var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(game.player.request_skill("hc.skill.wizard.ice_storm",target.get_instance_id(),lease),"formal Player accepts the pending action")
	check(lease.effect_reservation() != null and game.observed_releases == 0,"actual capacity ticket exists before the legitimate release callback")
	var mp: int = game.player.current_mp
	var hp: int = target.current_hp
	var rng: int = game._rng.state
	var actor_rng: int = target._rng.state
	var accepted_cooldown: int = game.player.skill_cooldown_remaining_ms("wizard.ice_storm")
	check(accepted_cooldown > 0,"failure comparison begins after the original accepted cooldown")
	deadline = Time.get_ticks_msec()+3000
	while game.observed_releases == 0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and game.failed_batch_attempts == 1,"original Player callback reaches the explicit batch-creation failure exactly once")
	check(not bool(game.observed_execution.get("accepted",true)) and game.observed_execution.get("reason") == "feature_batch_unavailable","missing promised batch is an explicit Root business refusal")
	check(game.planner_entries == 0 and game._canonical_cast_serial == 0,"batch refusal never enters the existing planning body or requests a canonical seed")
	check(game.player.current_mp == mp and target.current_hp == hp and game._rng.state == rng and target._rng.state == actor_rng,"after acceptance, failed release changes no MP, target HP, Root RNG or target RNG")
	var runtime: RefCounted = game._feature_effect_runtime
	check(lease._producer_closed and int(runtime.reservation_snapshot().actions) == 0,"real Player callback tail closes the failed producer and returns unused capacity")
	check(runtime.pending_count() == 0 and runtime.active_count() == 0 and runtime.errors.is_empty(),"failed promised batch leaves no effect work or hidden runtime error")
	game.queue_free(); await get_tree().process_frame
	_finish()
func _finish() -> void:
	if not proof.write_receipt("feature_batch_failure_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("FEATURE_BATCH_FAILURE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
