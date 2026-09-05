extends Node

const ControllerScript := preload("res://scripts/town_music_controller.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var safe_circle: Array = [{
		"shape": "circle",
		"center_ground_gu": Vector2.ZERO,
		"radius_gu": 9.0,
	}]
	assert(ControllerScript.DELAY_SECONDS == 10.0, "主城BGM延迟契约必须是10秒")
	for map_id in [910001, 910003, 910005, 910006, 910007]:
		assert(ControllerScript.is_main_city_map(map_id), "主城稳定地图ID遗漏：%d" % map_id)
	assert(not ControllerScript.is_main_city_map(910002), "野外地图不得被识别为主城")
	assert(
		not ControllerScript.town_area_at(910001, safe_circle, Vector2.ZERO).is_empty(),
		"比奇安全区内点没有被识别为主城区域",
	)
	assert(
		ControllerScript.town_area_at(910001, safe_circle, Vector2(20.0, 0.0)).is_empty(),
		"整张比奇地图不能被当成城镇",
	)
	assert(
		ControllerScript.town_area_at(910002, safe_circle, Vector2.ZERO).is_empty(),
		"非主城地图即使有安全区也不能启动主城BGM",
	)

	var controller = ControllerScript.new()
	add_child(controller)
	await get_tree().process_frame
	assert(controller.music_player != null, "主城BGM缺少全局AudioStreamPlayer")
	assert(controller.music_player.bus == &"Music", "主城BGM没有路由到Music bus")
	assert(controller.music_player.stream != null, "用户主城BGM OGG没有加载")
	assert(
		controller.music_player.stream is AudioStreamOggVorbis
			and not (controller.music_player.stream as AudioStreamOggVorbis).loop,
		"主城BGM必须每次入城完整播放一遍后安静",
	)
	controller.delay_seconds = 0.05
	var started: Array[Dictionary] = []
	controller.music_started.connect(
		func(request: Dictionary) -> void: started.append(request.duplicate(true))
	)

	# A direct-city map outside its compiled safe area must not arm anything.
	controller.begin_map_transition(910001, "map:city:outside")
	assert(
		not controller.set_map_context(
			910001, safe_circle, Vector2(20.0, 0.0), "map:city:outside"
		),
		"安全区外不能进入主城音乐状态",
	)
	assert(
		controller.on_loading_transition_finished({
			"contract_id": "ui.loading.transition.v1",
			"transition_id": "map:city:outside",
		}),
		"有效Loading结束事件未被接受",
	)
	await get_tree().create_timer(0.08).timeout
	assert(started.is_empty(), "安全区外不应播放主城BGM")

	# Loading-ended is the only clock origin. Before the short test delay the
	# stream must still be stopped; after it exactly one start is observable.
	controller.begin_map_transition(910001, "map:city:001")
	assert(
		controller.set_map_context(910001, safe_circle, Vector2.ZERO, "map:city:001"),
		"比奇安全区内没有建立主城音乐上下文",
	)
	var entry_serial_before_area_repeat: int = int(controller.state_snapshot().entry_serial)
	controller.set_town_presence(true, "safe_area.another-authored-area")
	assert(
		int(controller.state_snapshot().entry_serial) == entry_serial_before_area_repeat,
		"同一主城不同安全区不能被误判为重复入城",
	)
	assert(
		controller.on_loading_transition_finished({
			"contract_id": "ui.loading.transition.v1",
			"transition_id": "map:city:001",
		}),
		"主城Loading结束事件没有启动延迟门闩",
	)
	assert(controller.is_delay_pending(), "Loading结束后没有挂起一次性延迟")
	await get_tree().create_timer(0.02).timeout
	assert(started.is_empty(), "10秒边界之前不应开始主城BGM")
	await get_tree().create_timer(0.06).timeout
	assert(started.size() == 1, "一次入城只能启动一次主城BGM")
	assert(started[0].map_id == 910001 and started[0].transition_id == "map:city:001")
	assert(not controller.on_loading_transition_finished({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": "map:city:001",
	}), "重复Loading结束事件不能重复启动同一次入城")
	await get_tree().process_frame
	assert(started.size() == 1, "重复事件产生了第二次主城BGM启动")
	controller.music_player.stop()
	controller._on_music_finished()
	assert(not controller.is_music_active(), "主城BGM自然结束后不应保持播放")
	assert(started.size() == 1, "主城BGM自然结束后不应自动重播")

	# Leaving the safe area stops the stream and permits a fresh entry only after
	# a new area entry, while a stale transition event remains rejected.
	controller.set_town_presence(false)
	assert(not controller.state_snapshot().in_town, "离开安全区没有清除主城状态")
	controller.set_town_presence(true, "safe_area.910001.0")
	assert(controller.is_delay_pending(), "同图重新入城没有重新计时")
	controller.begin_map_transition(910003, "map:city:002")
	assert(
		not controller.on_loading_transition_finished({
			"contract_id": "ui.loading.transition.v1",
			"transition_id": "map:city:001",
		}),
		"旧地图结束事件串入新地图",
	)
	assert(not controller.is_delay_pending(), "切图后旧延迟仍然存活")

	# Correct destination event arms the new city; a subsequent non-city map
	# invalidates it before timeout, proving no delayed cross-map playback.
	controller.set_map_context(910003, safe_circle, Vector2.ZERO, "map:city:002")
	controller.on_loading_transition_finished({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": "map:city:002",
	})
	assert(controller.is_delay_pending(), "盟重主城没有启动一次性延迟")
	controller.begin_map_transition(910002, "map:wild:001")
	assert(not controller.is_delay_pending(), "离城后仍残留主城延迟")
	await get_tree().create_timer(0.08).timeout
	assert(started.size() == 1, "离城后的过期延迟串播了主城BGM")

	print("TOWN_MUSIC_CONTROLLER_PASS：五主城安全区、Loading结束后延迟、离城取消、重复入城与旧事件隔离契约通过")
	get_tree().quit(0)
