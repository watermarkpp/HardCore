extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
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
	var target := await Fixture.prepare_target(self,game,game.player,19,"feature_release_identity")
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
	var cooldown: int = game.player.skill_cooldown_remaining_ms("wizard.ice_storm")
	var bad: Dictionary = game._execute_canonical_skill("冰咆哮",game.player.global_position,Vector2.RIGHT,0,
		{"release_id":"player:old:action:0"},true,false,lease)
	check(not bool(bad.get("accepted",false)),"wrong old action ID is a business refusal at the actual Root entry")
	check(game.player.current_mp == mp and target.current_hp == hp and game._rng.state == rng and target._rng.state == actor_rng,
		"wrong callback preserves resources, both RNG owners and HP before any commit")
	check(game.player.skill_cooldown_remaining_ms("wizard.ice_storm") == cooldown and lease.valid_for_release(game._action_configuration_identity()),
		"refusal preserves accepted cooldown and does not consume the valid pending release right")
	game.observed_releases = 0
	deadline = Time.get_ticks_msec()+3000
	while game.observed_releases == 0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and bool(game.observed_execution.get("accepted",false)) and target.current_hp < hp,
		"the original Player callback still performs exactly one legitimate base release")
	var runtime: RefCounted = game._feature_effect_runtime
	for index in 120:
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.active_count() == 1 and runtime.pending_count() == 0 and runtime.errors.is_empty(),"the valid base hit retains its one promised derived state")
	hp = target.current_hp; mp = game.player.current_mp; rng = game._rng.state
	var old: Dictionary = game._execute_canonical_skill("冰咆哮",game.player.global_position,Vector2.RIGHT,0,
		{"release_id":"player:%d:action:%d" % [game.player.get_instance_id(),game.player._combat_action_sequence]},true,false,lease)
	check(not bool(old.get("accepted",false)) and target.current_hp == hp and game.player.current_mp == mp and game._rng.state == rng,
		"even the correct old ID cannot reopen the consumed configuration")
	game.queue_free(); await get_tree().process_frame
	_finish()
func _finish() -> void:
	if not proof.write_receipt("feature_release_identity_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("FEATURE_RELEASE_IDENTITY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
