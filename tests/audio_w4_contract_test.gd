extends Node

const AudioServiceScript := preload("res://scripts/audio_runtime_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var service = AudioServiceScript.new()
	add_child(service)
	await get_tree().process_frame
	service.stop_all_audio("w4_contract_setup")
	service.set_sfx_enabled(true)
	service.set_clock_for_test(1000)
	service.reset_metrics_for_test(true)

	var config: Dictionary = service.state_snapshot().get("runtime_config", {})
	assert(float(config.get("sfx_gain_linear", 0.0)) == 0.5, "W4工程SFX缩放初值必须为线性0.5")
	assert(int(config.get("event_pool_size", 0)) == 24, "音频事件池初值必须固定为24")
	var monster_config: Dictionary = config.get("monster", {})
	assert(int(monster_config.get("polyphony_limit", 0)) == 6, "怪物并发预算初值必须为6")
	assert(float(monster_config.get("combat_prompt_rate_per_second", 0.0)) == 3.0, "战斗提示预算初值必须为3/s")
	assert(float(monster_config.get("attack_rate_per_second", 0.0)) == 12.0, "怪物攻击预算初值必须为12/s")

	# The six active monster voices fill the monster budget. The seventh request
	# must be rejected before stream lookup, so this remains a meaningful guard
	# even when a candidate file is absent in a cold cache.
	for index in range(6):
		var admitted := service.play_monster_event(
			21,
			"attack_start",
			{
				"audio_owner_key": "poly-owner-%d" % index,
				"release_id": "release-%d" % index,
			},
		)
		assert(admitted.get("status", "") == "played", "六个怪物攻击声应填满并发预算")
	var before_polyphony_metrics: Dictionary = service.metrics_snapshot()
	service._stream_cache.clear()
	var polyphony_rejected := service.play_monster_event(
		21,
		"attack_start",
		{"audio_owner_key": "poly-owner-6", "release_id": "release-6"},
	)
	assert(polyphony_rejected.get("status", "") == "monster_polyphony_limit", "第七个怪物声必须被怪物并发预算拒绝")
	assert(
		int(service.metrics_snapshot().get("stream_lookup_attempts", 0))
			== int(before_polyphony_metrics.get("stream_lookup_attempts", 0)),
		"并发预算拒绝必须发生在取资源之前",
	)
	service.prewarm_runtime_streams()

	# Attack starts have their own one-second rate budget. Stop each admitted
	# player so the rate test cannot be mistaken for the polyphony test.
	service.stop_all_events("attack_rate_setup")
	service.reset_metrics_for_test(true)
	service.set_clock_for_test(2000)
	for index in range(12):
		var admitted := service.play_monster_event(
			21,
			"attack_start",
			{
				"audio_owner_key": "rate-owner-%d" % index,
				"release_id": "rate-release-%d" % index,
			},
		)
		assert(admitted.get("status", "") == "played", "12/s预算内的怪物攻击声应播放")
		service.stop_all_events("attack_rate_step")
	var before_attack_rate_metrics: Dictionary = service.metrics_snapshot()
	service._stream_cache.clear()
	var rate_rejected := service.play_monster_event(
		21,
		"attack_start",
		{"audio_owner_key": "rate-owner-12", "release_id": "rate-release-12"},
	)
	assert(rate_rejected.get("status", "") == "monster_attack_rate_limit", "第13个同秒攻击声必须被速率预算拒绝")
	assert(
		int(service.metrics_snapshot().get("stream_lookup_attempts", 0))
			== int(before_attack_rate_metrics.get("stream_lookup_attempts", 0)),
		"攻击速率拒绝必须发生在取资源之前",
	)
	service.prewarm_runtime_streams()

	# Combat prompts use a separate rate budget and still admit after a new
	# one-second window. Each owner is a distinct real actor session.
	service.stop_all_events("prompt_rate_setup")
	service.reset_metrics_for_test(true)
	service.set_clock_for_test(4000)
	for index in range(3):
		var prompt := service.play_monster_combat_prompt(
			21,
			"prompt-owner-%d" % index,
			{"session_id": "prompt-session-%d" % index},
		)
		assert(prompt.get("status", "") == "played", "3/s预算内的战斗提示应播放")
		service.stop_all_events("prompt_rate_step")
	var before_prompt_rate_metrics: Dictionary = service.metrics_snapshot()
	service._stream_cache.clear()
	var prompt_rejected := service.play_monster_combat_prompt(
		21,
		"prompt-owner-3",
		{"session_id": "prompt-session-3"},
	)
	assert(prompt_rejected.get("status", "") == "monster_prompt_rate_limit", "第4个同秒战斗提示必须被速率预算拒绝")
	assert(
		int(service.metrics_snapshot().get("stream_lookup_attempts", 0))
			== int(before_prompt_rate_metrics.get("stream_lookup_attempts", 0)),
		"战斗提示速率拒绝必须发生在取资源之前",
	)
	service.prewarm_runtime_streams()

	# A new window admits again, proving the rate limiter does not permanently
	# silence an actor after a previous burst.
	service.set_clock_for_test(5001)
	var next_window_prompt := service.play_monster_combat_prompt(
		21,
		"prompt-owner-next-window",
		{"session_id": "prompt-session-next-window"},
	)
	assert(next_window_prompt.get("status", "") == "played", "新的预算窗口必须恢复战斗提示准入")

	print("AUDIO_W4_CONTRACT_PASS：预算/并发/资源前拒绝、战斗提示速率与新窗口恢复通过")
	service.stop_all_audio("w4_contract_done")
	service.clear_clock_override_for_test()
	get_tree().quit(0)
