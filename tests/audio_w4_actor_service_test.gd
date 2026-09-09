extends Node

const AudioServiceScript := preload("res://scripts/audio_runtime_service.gd")
const EnemyScript := preload("res://scripts/enemy.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var service = AudioServiceScript.new()
	service.name = "AudioRuntimeService"
	add_child(service)
	await get_tree().process_frame
	service.set_clock_for_test(1000)
	service.reset_metrics_for_test(true)

	var enemy = EnemyScript.new()
	enemy.name = "W4ActorServiceFixture"
	enemy.monster_id = 31
	enemy.monster_data = {"monster_id": 31}
	enemy.display_name = "W4测试怪物"
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.global_position = Vector2(32.0, 32.0)
	add_child(enemy)
	await get_tree().process_frame
	var target := Node2D.new()
	target.name = "W4CombatTarget"
	target.global_position = Vector2(64.0, 32.0)
	add_child(target)
	await get_tree().process_frame

	# The existing actor target edge enters one actual service session. Repeating
	# the target observation must not replay the prompt.
	enemy.target = target
	await get_tree().process_frame
	var first_metrics: Dictionary = service.metrics_snapshot()
	assert(int(first_metrics.get("monster_prompt_admitted", 0)) == 1, "真实Enemy target进入必须只启动一次战斗提示")
	assert(str(service.state_snapshot().get("last_event", {}).get("source_semantic_event", "")) == "ambient", "真实服务必须用同ID ambient作为无专属提示源")
	var owner_key := enemy._audio_owner_key_for_actor()
	assert(bool(service.monster_combat_session_snapshot(owner_key).get("active", false)), "真实Enemy提示必须持有活动会话")
	enemy._audio_try_enter_combat_session()
	enemy._audio_try_enter_combat_session()
	assert(int(service.metrics_snapshot().get("monster_prompt_admitted", 0)) == 1, "重复target观察不得重开真实战斗提示")

	# A confirmed attack action uses the attack source path. Monster 31 has both
	# attack_start and attack_frame mappings; an observed frame is sent only after
	# the accepted start.
	enemy._play_attack_animation(1.0)
	var after_attack_start: Dictionary = service.metrics_snapshot()
	assert(int(after_attack_start.get("monster_attack_admitted", 0)) == 1, "真实Enemy攻击动作必须启动攻击声")
	enemy.visual.current_state = "attack"
	enemy.visual.current_frame = 0
	enemy._audio_observe_visual_state()
	enemy.visual.current_frame = 2
	enemy._audio_observe_visual_state()
	assert(int(service.metrics_snapshot().get("played", 0)) >= 3, "真实服务应播放提示、攻击起点和攻击帧")

	# Walk/turn observation and positive monster damage do not enter the W4
	# production whitelist.
	var played_before_silent_edges := int(service.metrics_snapshot().get("played", 0))
	enemy.visual.current_state = "walk"
	enemy.visual.current_frame = 0
	enemy._audio_observe_visual_state()
	enemy._audio_observe_visual_state()
	enemy.take_damage(5)
	assert(int(service.metrics_snapshot().get("played", 0)) == played_before_silent_edges, "追击环境声和怪物受击不得播放")

	# LOS interruption is transient: the service session remains active and the
	# actor's next observation does not generate another prompt.
	var los_result := service.notify_monster_los_interrupted(owner_key)
	assert(los_result.get("reason", "") == "transient_los", "真实服务必须忽略短暂LOS中断")
	enemy._audio_try_enter_combat_session()
	assert(int(service.metrics_snapshot().get("monster_prompt_admitted", 0)) == 1, "短暂LOS中断后真实Enemy不得重播提示")

	# A real disengagement ends the session. After the configured debounce, a
	# fresh target edge may open one new session.
	enemy._audio_end_combat_session("explicit_disengage")
	assert(not bool(service.monster_combat_session_snapshot(owner_key).get("active", false)), "真实脱战必须结束Enemy音频会话")
	service.set_clock_for_test(1751)
	var replacement_target := Node2D.new()
	replacement_target.name = "W4ReplacementTarget"
	replacement_target.global_position = Vector2(96.0, 32.0)
	add_child(replacement_target)
	await get_tree().process_frame
	enemy.target = replacement_target
	await get_tree().process_frame
	assert(int(service.metrics_snapshot().get("monster_prompt_admitted", 0)) == 2, "真实脱战后新目标应允许一次新提示")

	# Death closes a live session without synthesizing an unproven monster death
	# sample.
	enemy.current_hp = 0
	enemy._death_pending = false
	enemy._begin_death()
	assert(int(service.metrics_snapshot().get("monster_prompt_admitted", 0)) == 2, "死亡边界不得伪造额外怪物音效")
	assert(not bool(service.monster_combat_session_snapshot(owner_key).get("active", false)), "死亡边界必须释放Enemy音频会话")

	print("AUDIO_W4_ACTOR_SERVICE_PASS：真实Enemy/AudioRuntimeService入战一次、攻击起手/帧、LOS保持、脱战重入、非白名单静音通过")
	service.stop_all_audio("w4_actor_service_done")
	service.clear_clock_override_for_test()
	get_tree().quit(0)
