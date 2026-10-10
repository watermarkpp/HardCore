extends Node

## This fixture uses a test-owned malformed ResourceLoader input.  The native
## FAILED result is expected evidence for the negative branch; the test only
## passes when the ordinary Root pump transfers that result to the visual
## registry and a later valid admission can recover the same path.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const VisualEffectScript := preload("res://scripts/caster_skill_visual_effect.gd")

var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var path := ""

func check(value: bool, label: String) -> void:

	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _wait_for_failed_terminal_admission() -> Dictionary:

	var admitted := false
	var status_history: Array[int] = []
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		admitted = admitted or game._frame_texture_threaded.has(path)
		var status := int(ResourceLoader.load_threaded_get_status(path))
		if status_history.is_empty() or status_history[-1] != status:
			status_history.append(status)
		if admitted and not game._frame_texture_threaded.has(path):
			break
	return {
		"admitted": admitted,
		"status_history": status_history,
		"tracked_after": game._frame_texture_threaded.has(path),
		"native_status_after": int(ResourceLoader.load_threaded_get_status(path)),
	}

func _wait_for_resident() -> bool:

	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if CasterSkillVisualRegistry.frame_texture_is_resident(path):
			return true
	return false

func _run() -> void:

	check(
		not PlayerState.test_mode
		and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"terminal failure fixture owns isolated production user data"
	)
	PlayerState.begin_startup_save_upgrade()
	check(
		PlayerState.finish_startup_save_upgrade()
		and PlayerState.create_character("视觉失败边界", "hc.profession.wizard").is_empty(),
		"ordinary startup reaches a distinct mapped profile"
	)
	if not failures.is_empty():
		_finish()
		return

	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "ordinary Root reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return
	var player: Node2D = game.get("player") as Node2D
	check(is_instance_valid(player), "ordinary Root exposes the production player owner")
	if not is_instance_valid(player):
		_finish()
		return

	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	path = "user://caster_terminal_failure_%s.res" % nonce
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "test-owned malformed visual resource opens")
	if file == null:
		_finish()
		return
	file.store_buffer("OWNED_TERMINAL_FAILURE".to_utf8_buffer())
	file.flush()
	check(file.get_error() == OK, "malformed visual resource is written completely")
	file.close()

	var serial_before_failure := CasterSkillVisualRegistry.current_failure_serial()
	CasterSkillVisualRegistry.queue_sequence_warm([path])
	var failed := await _wait_for_failed_terminal_admission()
	check(bool(failed.get("admitted", false)), "actual ResourceLoader request is admitted")
	check(
		int(failed.get("native_status_after", -1)) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"accepted malformed request ends with the native invalid-resource status"
	)
	var failure_reason := CasterSkillVisualRegistry.frame_texture_terminal_failure(path)
	check(failure_reason == "failed", "Root transfers actual THREAD_LOAD_FAILED to the visual registry")
	check(
		CasterSkillVisualRegistry.sequence_terminal_failure_after([path], serial_before_failure) == failure_reason,
		"an existing waiter sees the monotonic failure history"
	)

	# Explicit admission is the only operation allowed to clear the current
	# block.  The historical serial still terminates the old sequence, while a
	# new baseline is allowed to retry this exact path.
	CasterSkillVisualRegistry.queue_sequence_warm([path], true)
	var retry_baseline := CasterSkillVisualRegistry.current_failure_serial()
	check(
		CasterSkillVisualRegistry.frame_texture_terminal_failure(path).is_empty(),
		"explicit new admission clears only the current failure"
	)
	check(
		CasterSkillVisualRegistry.sequence_terminal_failure_after([path], serial_before_failure) == failure_reason,
		"old sequence remains terminal after a new admission clears current state"
	)
	check(
		CasterSkillVisualRegistry.sequence_terminal_failure_after([path], retry_baseline).is_empty(),
		"new sequence baseline is not poisoned by the old failure"
	)

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	check(ResourceSaver.save(texture, path) == OK, "same owned path is repaired with valid Texture2D bytes")
	texture = null
	image = null
	CasterSkillVisualRegistry.queue_sequence_warm([path], true)
	check(await _wait_for_resident(), "new explicit admission reaches resident visual state")
	check(
		CasterSkillVisualRegistry.frame_texture_terminal_failure(path).is_empty(),
		"successful retention clears current terminal state"
	)

	# Component contract: real effects install real AnimationPlayer children and
	# receive terminal failure through the connected signal. The malformed path
	# is injected only into the selected child sequence after setup; the native
	# accepted FAILED and the ordinary production effect construction remain real.
	var one_shot := VisualEffectScript.new()
	var injected_paths: Array[String] = [path]
	one_shot.setup(player.global_position, "wizard.ice_storm", 72.0, 5.0, Vector2.DOWN, player)
	add_child(one_shot)
	check(one_shot._sprites.size() == 1, "one-shot effect installs one real animation child")
	if one_shot._sprites.size() == 1:
		var one_player: Node = one_shot._sprites[0]
		one_player.call("_release_sequence_lease")
		one_player.set("_sequence_paths", injected_paths.duplicate())
		var leased := CasterSkillVisualRegistry.acquire_sequence_lease([path])
		check(leased, "one-shot component owns a real resident sequence lease")
		one_player.set("_sequence_lease_held", leased)
		one_player.set("_failure_baseline_serial", serial_before_failure)
		check(one_player.get("_sequence_paths") == injected_paths, "one-shot injection retains the typed selected path")
		check(CasterSkillVisualRegistry.sequence_terminal_failure_after(one_player.get("_sequence_paths"), int(one_player.get("_failure_baseline_serial"))) == failure_reason, "one-shot retry input resolves the old native terminal result")
		one_player.call("_retry_after_warm")
		check(bool(one_player.call("has_terminal_failure")), "one-shot animation enters terminal failure through registry history")
		check(one_shot.is_queued_for_deletion(), "one-shot parent retires through the animation failure signal")
		check(not bool(one_player.get("_sequence_lease_held")), "one-shot terminal result releases its actual lease")

	player.call("apply_magic_shield", 30.0, 0.3)
	var shield_before: Dictionary = (player.call("magic_shield_snapshot") as Dictionary).duplicate(true)
	var shield_effect := VisualEffectScript.new()
	shield_effect.setup(player.global_position, "wizard.magic_shield", 72.0, 30.0, Vector2.DOWN, player)
	add_child(shield_effect)
	check(shield_effect._sprites.size() == 1, "persistent shield effect installs one real animation child")
	if shield_effect._sprites.size() == 1:
		var shield_player: Node = shield_effect._sprites[0]
		shield_player.call("_release_sequence_lease")
		shield_player.set("_sequence_paths", injected_paths.duplicate())
		var leased := CasterSkillVisualRegistry.acquire_sequence_lease([path])
		check(leased, "shield component owns a real resident sequence lease")
		shield_player.set("_sequence_lease_held", leased)
		shield_player.set("_failure_baseline_serial", serial_before_failure)
		check(shield_player.get("_sequence_paths") == injected_paths, "shield injection retains the typed selected path")
		check(CasterSkillVisualRegistry.sequence_terminal_failure_after(shield_player.get("_sequence_paths"), int(shield_player.get("_failure_baseline_serial"))) == failure_reason, "shield retry input resolves the old native terminal result")
		shield_player.call("_retry_after_warm")
		check(bool(shield_player.call("has_terminal_failure")), "shield animation enters terminal failure through registry history")
		check(shield_effect.is_queued_for_deletion(), "shield parent retires through the animation failure signal")
		check(not bool(shield_player.get("_sequence_lease_held")), "shield terminal result releases its actual lease")
	check(
		(player.call("magic_shield_snapshot") as Dictionary) == shield_before,
		"terminal shield visual cleanup leaves the real player buff unchanged"
	)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	CasterSkillVisualRegistry.clear_frame_texture_cache()
	var retiring_owner: WeakRef = weakref(game)
	game.queue_free()
	game = null
	for index in 4:
		await get_tree().process_frame
	check(
		not is_instance_valid(retiring_owner.get_ref()),
		"Root retirement is allowed to release its own retrieval claims"
	)
	check(
		ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"retired visual path has no remaining native retrieval claim"
	)
	var trace := FileAccess.open("res://outputs/test_logs/framework/caster_visual_terminal_failure_contract_trace.json", FileAccess.WRITE)
	check(trace != null, "terminal failure trace opens")
	if trace != null:
		trace.store_string(JSON.stringify({
			"run_id": nonce,
			"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"fixture_path": path,
			"failure_reason": failure_reason,
			"scope": "actual accepted ResourceLoader failure, monotonic old/new admission boundary, and same-path valid recovery; native negative remains separately classified",
		}))
		trace.flush()
		check(trace.get_error() == OK, "terminal failure trace writes completely")
		trace.close()
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var written := proof.write_receipt(
		"caster_visual_terminal_failure_contract_20261009_test",
		proof.records.size(),
		failures.size()
	)
	print(
		"CASTER_VISUAL_TERMINAL_FAILURE_",
		"PASS" if written and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(),
		" failures=", failures
	)
	get_tree().quit(0 if written and failures.is_empty() else 1)
