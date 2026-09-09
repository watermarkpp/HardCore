extends Node

const AudioServiceScript := preload("res://scripts/audio_runtime_service.gd")
const SAMPLE_REPETITIONS := 32
const ACTOR_COUNTS := [0, 10, 20, 50]


func _ready() -> void:
	_run.call_deferred()


func _percentile(samples: Array[float], percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var ordered := samples.duplicate()
	ordered.sort()
	var index := clampi(
		ceili(percentile * float(ordered.size())) - 1,
		0,
		ordered.size() - 1,
	)
	return float(ordered[index])


func _run_condition(service: Node, actor_count: int, enabled: bool) -> Dictionary:
	service.stop_all_events("w4_perf_condition")
	service.set_sfx_enabled(enabled)
	service.reset_metrics_for_test(true)
	var samples: Array[float] = []
	for sample_index in SAMPLE_REPETITIONS:
		var started_usec := Time.get_ticks_usec()
		for actor_index in actor_count:
			# Advance the isolated service clock per actor so this synthetic probe
			# measures the route/pool path without intentionally tripping the 12/s
			# gameplay budget. No gameplay, AI or monster count is changed.
			service.set_clock_for_test(
				sample_index * 100000 + actor_index * 1001,
			)
			service.play_monster_event(
				21,
				"attack_start",
				{
					"audio_owner_key": "perf:%s:%d:%d" % ["on" if enabled else "off", sample_index, actor_index],
					"release_id": "attack:%d:%d" % [sample_index, actor_index],
				},
			)
			service.stop_all_events("w4_perf_step")
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		samples.append(float(elapsed_usec) / 1000.0)
	var metrics: Dictionary = service.metrics_snapshot()
	return {
		"actor_count": actor_count,
		"sfx_enabled": enabled,
		"sample_repetitions": SAMPLE_REPETITIONS,
		"p50_ms": _percentile(samples, 0.50),
		"p95_ms": _percentile(samples, 0.95),
		"p99_ms": _percentile(samples, 0.99),
		"min_ms": samples.min() if not samples.is_empty() else 0.0,
		"max_ms": samples.max() if not samples.is_empty() else 0.0,
		"audio_metrics": metrics,
	}


func _run() -> void:
	var service = AudioServiceScript.new()
	add_child(service)
	await get_tree().process_frame
	service.prewarm_runtime_streams()
	var runs: Array[Dictionary] = []
	for enabled in [true, false]:
		for actor_count in ACTOR_COUNTS:
			runs.append(_run_condition(service, actor_count, enabled))
	service.clear_clock_override_for_test()
	service.set_sfx_enabled(true)
	service.stop_all_audio("w4_perf_done")
	var report := {
		"contract_id": "audio.runtime_budget.v1",
		"probe": "headless_console",
		"conditions": runs,
		"legacy_old_on": {
			"status": "not_available_in_current_head",
			"reason": "旧实现不与新服务并存，避免以不同代码路径伪造同条件对照",
		},
		"headless_limitations": [
			"仅测Godot headless控制台内事件准入、池和服务CPU路径",
			"未测真实扬声器混音延迟、硬件音频线程和Android设备",
			"未改变怪物数量、AI频率、战斗随机数或地图内容",
		],
	}
	print("AUDIO_W4_PERF_JSON=" + JSON.stringify(report))
	print("AUDIO_W4_PERF_PASS：同代码SFX on/off与0/10/20/50固定条件采样完成；旧实现对照按当前HEAD不可执行记录")
	get_tree().quit(0)
