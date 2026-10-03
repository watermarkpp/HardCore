extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const REGISTRY := "res://assets/data/features/validation/publication_lifecycle_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _rejected_without_change(id: String, label: String) -> void:
	var configuration := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	check(not ContentLayers.set_feature_module_enabled(id, true), label)
	check(is_same(configuration.catalog, ContentLayers.feature_configuration().catalog) \
		and configuration.enabled_modules == ContentLayers.feature_configuration().enabled_modules \
		and is_same(bundle, PlayerState.feature_bundle()) and stats == PlayerState.computed_stats,
		label + ": preserves directory and actual player")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = ""
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(REGISTRY), "register startup and world-ready definitions before world attachment")
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", true), "startup package may enable without a live world")
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", false), "startup grant may withdraw before a world")
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual mapped world becomes READY even for an unsaved profile")
	if not game.gameplay_input_is_enabled():
		game.queue_free()
		await get_tree().process_frame
		_finish()
		return
	_rejected_without_change("hc.publication_probe", "startup-only package cannot activate inside the live world")
	var before := ContentLayers.feature_configuration()
	var old_bundle := PlayerState.feature_bundle()
	check(not ContentLayers.reload_feature_catalog(), "live world cannot replace its package directory through reload")
	check(is_same(before.catalog, ContentLayers.feature_configuration().catalog) and is_same(old_bundle, PlayerState.feature_bundle()),
		"rejected live directory replacement leaves the accepted configuration intact")
	game._acquire_gameplay_input_lock(&"feature_publication_fixture")
	_rejected_without_change("hc.ignite", "world-ready activation refuses the actual locked input boundary")
	game._release_gameplay_input_lock(&"feature_publication_fixture")
	get_tree().paused = true
	_rejected_without_change("hc.ignite", "paused world cannot publish a new grant")
	get_tree().paused = false
	var unknown_owner := Node.new()
	add_child(unknown_owner)
	PlayerState.register_profile_gameplay_owner(unknown_owner)
	_rejected_without_change("hc.ignite", "an additional owner without a READY contract cannot be bypassed")
	PlayerState.unregister_profile_gameplay_owner(unknown_owner)
	unknown_owner.free()
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "prepared world-ready package enables at a READY boundary")
	var target := await Fixture.prepare_target(self, game, game.player, 19, "feature_publication_lifecycle")
	check(target != null, "real skill receiver is prepared through the formal fixture")
	if target != null:
		game.set_process(false)
		game.set_physics_process(false)
		game.player.set_physics_process(false)
		for actor: Node in get_tree().get_nodes_in_group("enemies"):
			actor.set_physics_process(false)
		target.max_hp = 10000
		target.current_hp = 10000
		target.direct_spell_anti_magic_points = 0
		target.direct_spell_magic_defense_min = 0
		target.direct_spell_magic_defense_max = 0
		target.direct_spell_stats_valid = true
		game.player.current_mp = 100
		game._skill_cast_target = target
		game._set_magic_locked_target(target, true)
		var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
		check(lease != null, "real skill configuration is captured before acceptance")
		if lease != null:
			check(game.player.request_skill("hc.skill.wizard.ice_storm", target.get_instance_id(), lease), "actual player accepts the prepared skill")
			check(lease.is_accepted() and lease.effect_reservation() != null, "accepted skill owns its nonempty extension reservation")
			check(bool(game.player.combat_action_snapshot().active), "accepted action remains active during the real windup")
			_rejected_without_change("hc.numeric_fixture", "another world-ready grant cannot enter during the accepted action")
			check(ContentLayers.set_feature_module_enabled("hc.ignite", false), "stopping future admissions remains legal during accepted work")
			deadline = Time.get_ticks_msec() + 3000
			while game.observed_releases == 0 and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			check(game.observed_releases == 1 and is_same(game.observed_configuration, lease) and target.current_hp < 10000,
				"withdrawal preserves one real release and its committed base damage")
			check(game._feature_effect_runtime.pending_count() > 0,
				"already accepted derived facts survive the package withdrawal")
	game.queue_free()
	_rejected_without_change("hc.publication_probe", "queued world still owns its shutdown barrier")
	await get_tree().process_frame
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", true), "finished world retirement releases the startup boundary")
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", false), "startup grant can be stopped after retirement")
	check(ContentLayers.reload_feature_catalog() and PlayerState.feature_errors.is_empty(), "default publication is restored after world retirement")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_publication_lifecycle_test", checks, failures.size()):
		failures.append("receipt")
	print(("FRAMEWORK_FEATURE_PUBLICATION_LIFECYCLE_PASS" if failures.is_empty() else "FRAMEWORK_FEATURE_PUBLICATION_LIFECYCLE_FAIL") \
		+ " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
