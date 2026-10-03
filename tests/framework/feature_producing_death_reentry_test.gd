extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var game: Node
var target: EnemyActor
var lease: RefCounted
var runtime: RefCounted
var callback_count := 0
var committed_hp := 10000
var producing_before := false
var retained_after_death := false

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _on_resource_change(_hp: int, _max_hp: int, _mp: int, _max_mp: int) -> void:
	if callback_count > 0 or target.current_hp >= 10000: return
	callback_count += 1
	game.player.resources_changed.disconnect(_on_resource_change)
	committed_hp = target.current_hp
	var sequence: int = lease.effect_reservation().sequence()
	producing_before = runtime._reservations.has(sequence) and runtime._reservations[sequence].stage == "producing"
	# The observed hit has already used the production HP writer. This formal
	# death reenters before Root seals/transfers that same captured batch.
	game.player.take_damage(game.player.max_hp * 10, false)
	retained_after_death = runtime._reservations.has(sequence) and runtime._reservations[sequence].stage == "producing"

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.warrior.fire_sword":3}
	PlayerState.recalculate_stats(false)
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "real mapped world READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	target = await Fixture.prepare_target(self, game, game.player, 19, "feature_producing_death_reentry")
	check(target != null and target.projection_ready(), "formal mapped receiver")
	if target == null: _finish(); return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp = 10000
	target.current_hp = 10000
	target.direct_spell_anti_magic_points = 0
	target.direct_spell_magic_defense_min = 0
	target.direct_spell_magic_defense_max = 0
	target.direct_spell_stats_valid = true
	game.player.attack_min = 100
	game.player.attack_max = 100
	game.player.current_mp = 100
	game.player.current_hp = maxi(1, game.player.max_hp / 2)
	game.player.fire_sword_enabled = true
	game.player.half_moon_enabled = false
	game.player.thrusting_enabled = false
	# Existing production lifesteal, only its fixture numeric input is fixed.
	PlayerState.computed_stats["life_steal_percent"] = 100
	game._skill_cast_target = target
	game._set_magic_locked_target(target, true)
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "formal ignite source enabled")
	# Publication recomputes original stats, so set the existing lifesteal
	# input after it and before the real accepted action snapshot.
	PlayerState.computed_stats["life_steal_percent"] = 100
	lease = game._capture_melee_configuration()
	print("PRODUCING_DEATH_CONFIGURATION " + JSON.stringify({"lease_present":lease != null, "profession":PlayerState.profession, "learned":PlayerState.learned_skills, "feature_errors":PlayerState.feature_errors, "events":PlayerState.feature_bundle().get("event_index", {}).keys()}))
	check(lease != null and not lease.event_bindings_for("hc.skill.warrior.fire_sword").is_empty(), "real melee configuration includes ignite")
	if lease == null: _finish(); return
	game.player.resources_changed.connect(_on_resource_change)
	var accepted: bool = game.player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id(), lease)
	check(accepted and lease.effect_reservation() != null, "formal player input accepts nonempty capacity ticket")
	runtime = game._feature_effect_runtime
	deadline = Time.get_ticks_msec() + 3000
	while game.observed_releases == 0 and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and is_same(game.observed_configuration, lease), "same single release reaches real canonical planner")
	check(callback_count == 1 and producing_before, "one actual lifesteal notification observes HP commit and producing stage")
	check(game.player._dead and game.player.current_hp == 0, "formal take_damage commits player death in synchronous callback")
	check(retained_after_death, "captured batch retains promised capacity through player death")
	check(target.current_hp == committed_hp and committed_hp > 0 and committed_hp < 10000, "base target HP was committed once without rollback or repeated hit")
	check(runtime.pending_count() == 1 and runtime.active_count() == 0, "captured fact transfers after callback before derived processing")
	for index in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.active_count() == 1, "until-expired ignite installs from already committed hit despite source death")
	var loss := 10000 - committed_hp
	for second in range(1, 5):
		game._time_domains.advance_simulation(float(second * 1000000 - game._time_domains.simulation_usec()) / 1000000.0)
		for index in range(120):
			runtime.pump()
			if not runtime.has_due(): break
			await get_tree().process_frame
		check(target.current_hp == committed_hp - second * roundi(float(loss) * 0.05), "committed actual loss delivers exactly one periodic tick " + str(second))
	check(not runtime.has_work() and runtime.reservation_snapshot().actions == 0 and runtime.reservation_snapshot().receipts == 0, "terminal consumers retire capacity and receipts without leaks")
	check(runtime.errors.is_empty(), "committed work never becomes hidden transfer failure")
	print("PRODUCING_DEATH_OBSERVATION " + JSON.stringify({"callback_count":callback_count, "producing_before":producing_before, "retained_after_death":retained_after_death, "committed_hp":committed_hp, "metrics":runtime.metrics(), "reservations":runtime.reservation_snapshot(), "errors":runtime.errors}))
	game.queue_free()
	await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(), "world retires before restoring catalog")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_producing_death_reentry_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_PRODUCING_DEATH_REENTRY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
