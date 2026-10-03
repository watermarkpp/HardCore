extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var healing_releases := 0
var attack_releases := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _skill_release(name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
	if Loader.entity_skill_id(name) == "hc.skill.taoist.healing": healing_releases += 1

func _attack_release(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
	attack_releases += 1

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "道士"
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.taoist.healing":3}
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/delayed_release_registry.json"), "trusted default-off timing test package registers before world")
	check(ContentLayers.set_feature_module_enabled("hc.delayed_release_probe", true), "legal test-only timing contribution enables before world")
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 18000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "production world reaches input READY")
	if not game.gameplay_input_is_enabled():
		game.queue_free()
		await get_tree().process_frame
		_finish()
		return
	var target := await Fixture.prepare_target(self, game, game.player, 19, "delayed_producer_publication")
	check(target != null, "formal mapped target fixture establishes controlled combat location")
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.skill_requested.connect(_skill_release)
	game.player.attack_requested.connect(_attack_release)
	game.player.current_hp = game.player.max_hp - 50
	game.player.current_mp = game.player.max_mp
	var lease: RefCounted = game._capture_action_configuration("hc.skill.taoist.healing")
	check(lease != null, "A captures actual production configuration")
	if lease == null:
		game.queue_free()
		await get_tree().process_frame
		_finish()
		return
	var timing: Dictionary = lease.definition_for("hc.skill.taoist.healing").timing
	check(int(timing.effect_resolve_ms_from_cast_start) == 5000 and int(timing.body_cast_ms) == 600 and int(timing.total_action_lock_ms) == 1500, "test contribution delays only release, retaining original body and action lock")
	check(game.player.request_skill("hc.skill.taoist.healing", game.player.get_instance_id(), lease) and lease.is_accepted(), "A enters the real accepted healing path")
	var action_a: int = game.player.combat_action_snapshot().action_id
	deadline = Time.get_ticks_msec() + 3000
	while not game.player.can_start_attack() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.player.can_start_attack() and healing_releases == 0 and lease.valid_for_release(game.player.hc_action_configuration_identity.call()), "original action lock permits B while accepted A is still pending")
	var attack_lease: RefCounted = game._capture_melee_configuration()
	check(attack_lease != null and game.player.request_attack(false, 0, attack_lease), "B is a real legally accepted short attack")
	var action_b: int = game.player.combat_action_snapshot().action_id
	check(action_b != action_a and action_b > action_a, "B supersedes the presentation slot with its own identity")
	deadline = Time.get_ticks_msec() + 1800
	while bool(game.player.combat_action_snapshot().active) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not bool(game.player.combat_action_snapshot().active) and attack_releases == 1 and healing_releases == 0, "real B completes once before old A release")
	check(game.gameplay_input_is_enabled() and lease.valid_for_release(game.player.hc_action_configuration_identity.call()), "READY input plus inactive latest slot still has legitimate older producer")
	var before := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	var published: bool = ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true)
	check(not published, "world-ready publication refuses every pending accepted producer including superseded A")
	check(is_same(before.catalog, ContentLayers.feature_configuration().catalog) and before.enabled_modules == ContentLayers.feature_configuration().enabled_modules and is_same(bundle, PlayerState.feature_bundle()) and PlayerState.computed_stats == stats, "refused publication preserves the full current configuration")
	print("DELAYED_PRODUCER_GAP action_a=" + str(action_a) + " action_b=" + str(action_b) + " latest_active=" + str(game.player.combat_action_snapshot().active) + " old_valid=" + str(lease.valid_for_release(game.player.hc_action_configuration_identity.call())) + " published=" + str(published))
	deadline = Time.get_ticks_msec() + 4000
	while healing_releases == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(healing_releases == 1 and attack_releases == 1 and game.observed_releases >= 1 and is_same(game.observed_configuration, lease), "original superseded A reaches actual Root planner once")
	check(not lease.valid_for_release(game.player.hc_action_configuration_identity.call()), "completed A closes its production lease")
	check(not game.player.has_pending_combat_release(), "all producers retire independently of the newest body slot")
	if published: ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false)
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true), "world-ready publication resumes after all real producers finish")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false), "published grant can withdraw independently")
	await get_tree().create_timer(0.2).timeout
	check(healing_releases == 1 and attack_releases == 1, "publication never replays either release")
	var cancelled: RefCounted = game._capture_action_configuration("hc.skill.taoist.healing")
	check(cancelled != null and game.player.request_skill("hc.skill.taoist.healing", game.player.get_instance_id(), cancelled), "another actual accepted A owns a new delayed producer")
	check(game.player.has_pending_combat_release(), "accepted producer is visible before any visual or delayed callback")
	get_tree().paused = true
	check(game.player.begin_combat_transition("delayed_producer_retirement"), "existing lifecycle owner starts transition while paused")
	check(not game.player.has_pending_combat_release() and not cancelled.valid_for_release(game.player.hc_action_configuration_identity.call()), "paused transition immediately closes producers without waiting for wall clock timer")
	check(game.player.finish_combat_transition("delayed_producer_retirement"), "original transition owner completes normally")
	get_tree().paused = false
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", true), "cancelled old identity cannot block a legal READY publication")
	check(ContentLayers.set_feature_module_enabled("hc.numeric_fixture", false), "post-transition grant withdrawal remains legal")
	await get_tree().create_timer(5.2).timeout
	check(healing_releases == 1 and not game.player.has_pending_combat_release(), "old timer after transition cannot deliver or retain producer")
	var retiring: RefCounted = game._capture_action_configuration("hc.skill.taoist.healing")
	var retiring_identity: Dictionary = game.player.hc_action_configuration_identity.call()
	check(retiring != null and game.player.request_skill("hc.skill.taoist.healing", game.player.get_instance_id(), retiring) and game.player.has_pending_combat_release(), "world teardown begins with actual accepted producer pending")
	game.queue_free()
	await get_tree().process_frame
	check(not retiring.valid_for_release(retiring_identity), "world retirement closes producer before its timer can deliver")
	check(ContentLayers.reload_feature_catalog(), "catalog restores after complete world retirement")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_delayed_producer_publication_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_DELAYED_PRODUCER_PUBLICATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
