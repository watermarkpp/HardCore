extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Beam := preload("res://scripts/caster_skill_beam_visual_effect.gd")
const SkyStrike := preload("res://scripts/caster_skill_sky_strike_visual_effect.gd")

var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var player: Node2D
var malformed_path := ""
var failure_baseline_serial := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _wait_for_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return game.gameplay_input_is_enabled()

func _wait_for_resident() -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if CasterSkillVisualRegistry.frame_texture_is_resident(malformed_path):
			return true
	return false

func _visual_context(skill_id: String) -> Dictionary:
	return {"visual_profile": CasterSkillVisualRegistry.visual_profile(skill_id)}

func _setup_effect(effect: Node) -> void:
	if effect is Beam:
		effect.setup(player.global_position, "wizard.laser", 72.0, 5.0, Vector2.RIGHT, player, "", _visual_context("wizard.laser"))
	elif effect is SkyStrike:
		effect.setup(player.global_position, "wizard.lightning", 72.0, 5.0, Vector2.RIGHT, player, "", _visual_context("wizard.lightning"))

func _check_normal_lifecycle(effect: Node, label: String) -> void:
	_setup_effect(effect)
	add_child(effect)
	await get_tree().process_frame
	check(effect._sprites.size() == 1, "%s installs one normal animation child" % label)
	check(bool(effect.visual_loaded), "%s normal visual loads once" % label)
	check(not effect.is_queued_for_deletion(), "%s normal visual remains live" % label)
	effect.queue_free()
	await get_tree().process_frame

func _inject_terminal_failure(effect: Node, label: String) -> void:
	_setup_effect(effect)
	add_child(effect)
	await get_tree().process_frame
	check(effect._sprites.size() == 1, "%s installs one failure candidate child" % label)
	if effect._sprites.size() != 1:
		effect.queue_free()
		return
	var animation: Node = effect._sprites[0]
	var injected_paths: Array[String] = [malformed_path]
	animation.call("_release_sequence_lease")
	animation.set("_sequence_paths", injected_paths.duplicate())
	var leased := CasterSkillVisualRegistry.acquire_sequence_lease(injected_paths)
	check(leased, "%s owns one selected failure sequence lease" % label)
	# The valid resident path now transitions through the formal Registry
	# terminal state after the owner has acquired its lease, reproducing the
	# known terminal result without faking the animation signal or parent.
	CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(malformed_path, "failed")
	animation.set("_sequence_lease_held", leased)
	animation.set("_failure_baseline_serial", failure_baseline_serial)
	check(
		CasterSkillVisualRegistry.sequence_terminal_failure_after(
			animation.get("_sequence_paths"),
			int(animation.get("_failure_baseline_serial"))
		) == "failed",
		"%s child sees historical terminal failure before retry" % label
	)
	check(
		animation.is_connected("animation_terminal_failure", Callable(effect, "_on_animation_terminal_failure")),
		"%s child is bound to parent terminal cleanup" % label
	)
	animation.call("_retry_after_warm")
	check(bool(animation.call("has_terminal_failure")), "%s child enters terminal failure" % label)
	check(effect.is_queued_for_deletion(), "%s parent receives terminal failure and retires" % label)
	check(not bool(animation.get("_sequence_lease_held")), "%s terminal failure releases lease once" % label)
	effect.queue_free()
	await get_tree().process_frame

func _run() -> void:
	check(
		not PlayerState.test_mode
		and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"subclass terminal fixture owns isolated production user data"
	)
	PlayerState.begin_startup_save_upgrade()
	check(
		PlayerState.finish_startup_save_upgrade()
		and PlayerState.create_character("施法终态边界", "hc.profession.wizard").is_empty(),
		"ordinary startup reaches a distinct mapped profile"
	)
	if not failures.is_empty():
		_finish()
		return

	game = Root.new()
	add_child(game)
	check(await _wait_for_ready(), "ordinary Root reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return
	player = game.get("player") as Node2D
	check(is_instance_valid(player), "ordinary Root exposes production player owner")
	if not is_instance_valid(player):
		_finish()
		return

	await _check_normal_lifecycle(
		Beam.new(),
		"beam"
	)
	await _check_normal_lifecycle(
		SkyStrike.new(),
		"sky strike"
	)

	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	malformed_path = "user://caster_subclass_terminal_failure_%s.res" % nonce
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	check(ResourceSaver.save(texture, malformed_path) == OK, "test-owned frame resource writes valid bytes")
	texture = null
	image = null
	CasterSkillVisualRegistry.queue_sequence_warm([malformed_path], true)
	check(await _wait_for_resident(), "test-owned frame reaches resident state")
	# Each subclass injection below transitions this accepted resident sequence
	# through the same registry terminal state used by the native warm failure.
	failure_baseline_serial = -1

	await _inject_terminal_failure(
		Beam.new(),
		"beam"
	)
	await _inject_terminal_failure(
		SkyStrike.new(),
		"sky strike"
	)

	if FileAccess.file_exists(malformed_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
	CasterSkillVisualRegistry.clear_frame_texture_cache()
	var retiring_owner: WeakRef = weakref(game)
	game.queue_free()
	game = null
	for _index in 4:
		await get_tree().process_frame
	check(not is_instance_valid(retiring_owner.get_ref()), "Root retirement releases its own retrieval claims")
	check(
		int(CasterSkillVisualRegistry.frame_texture_cache_diagnostics().get("leased_sequence_refcount_total", -1)) == 0,
		"retired subclass visuals leave no sequence lease claims"
	)
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var written := proof.write_receipt(
		"v109_caster_subclass_terminal_failure_test",
		proof.records.size(),
		failures.size()
	)
	print(
		"V109_CASTER_SUBCLASS_TERMINAL_FAILURE_",
		"PASS" if written and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(),
		" failures=", failures
	)
	get_tree().quit(0 if written and failures.is_empty() else 1)
