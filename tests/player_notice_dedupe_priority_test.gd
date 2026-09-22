extends Node

## Notice dedupe/priority/queue acceptance (R2).
## Repeated same-key notices refresh in place (no spam), errors preempt
## lower priorities, info cannot flush errors, the queue is bounded, and
## equal keys merge both when visible and when queued.

const NoticeScript := preload("res://scripts/ui_player_notice.gd")

var failures: Array[String] = []


func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func settle() -> void:
	for _index in range(4):
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await settle()
	var presenter := hud.notice_presenter
	expect(presenter != null, "notice presenter exists")
	if presenter == null:
		get_tree().quit(1)
		return
	presenter.set_process(false)

	# --- 1. Ten identical errors collapse into one notice --------------------
	presenter.clear_for_test()
	for _index in range(10):
		hud.show_error_message("魔法不足")
	expect(presenter.queue_size() == 0, "repeated errors never queue")
	expect(hud.error_label.text == "魔法不足", "single visible error text")
	expect(str(presenter.current_notice().get("dedupe_key", "")) == "msg:魔法不足", "same key keeps one notice")
	expect(presenter.current_notice().get("priority", 0) == NoticeScript.PRIORITY_ERROR, "error priority mapped")

	# --- 2. Same key refreshes the timer instead of stacking -----------------
	presenter.clear_for_test()
	hud.show_error_message("技能动作或冷却尚未结束", 2.0)
	presenter._process(1.5)
	expect(hud.error_label.text == "技能动作或冷却尚未结束", "error still visible at 1.5s")
	hud.show_error_message("技能动作或冷却尚未结束", 2.0)
	presenter._process(1.5)
	expect(hud.error_label.text == "技能动作或冷却尚未结束", "refreshed notice survives past the original expiry")
	presenter._process(0.6)
	expect(hud.error_label.text.is_empty(), "refreshed notice expires after its own full window")

	# --- 3. Lower-priority notices queue; the queue is bounded ----------------
	presenter.clear_for_test()
	hud.show_error_message("错误一", 2.0)
	for name in ["成功二", "成功三", "成功四", "成功五", "成功六"]:
		hud.show_success_message(name)
	expect(hud.error_label.text == "错误一", "error keeps the overlay while lower notices wait")
	expect(presenter.queue_size() == NoticeScript.MAX_QUEUE, "queue holds at most %d" % NoticeScript.MAX_QUEUE)
	expect(not presenter.queue_dedupe_keys().has("msg:成功二"), "oldest overflow dropped when all priorities tie")
	expect(presenter.queue_dedupe_keys().has("msg:成功三"), "remaining queue keeps later entries")
	presenter._process(2.0)
	expect(hud.error_label.text == "成功三", "next queued notice shows after expiry")

	# --- 4. Same key inside the queue merges ---------------------------------
	presenter.clear_for_test()
	hud.show_error_message("错误一", 2.0)
	hud.show_success_message("成功二", 2.0)
	hud.show_success_message("成功二", 2.0)
	expect(presenter.queue_size() == 1, "queued duplicate merged")
	expect(str(presenter.queue_dedupe_keys()[0]) == "msg:成功二", "merged entry keeps the key")

	# --- 5. Higher AND equal priority replace; lower waits -------------------
	presenter.clear_for_test()
	hud.show_success_message("已装备 屠龙", 2.0)
	hud.show_error_message("材料不足", 2.0)
	expect(hud.error_label.text == "材料不足", "error preempts success")
	presenter.clear_for_test()
	hud.show_error_message("错误甲", 2.0)
	hud.show_error_message("错误乙", 2.0)
	expect(hud.error_label.text == "错误乙", "equal priority: the latest error replaces (latest wins)")
	expect(presenter.queue_size() == 0, "equal priority never queues")
	presenter.clear_for_test()
	hud.show_error_message("错误甲", 2.0)
	hud.show_warning_message("警告乙", 2.0)
	expect(hud.error_label.text == "错误甲" and presenter.queue_size() == 1, "warning queues behind error")

	# --- 6. Contract-level priority table ------------------------------------
	expect(NoticeScript.priority_for("error") == 100 and NoticeScript.priority_for("warning") == 70, "error/warning priority mapping")
	expect(NoticeScript.priority_for("success") == 40 and NoticeScript.priority_for("info") == 20, "success/info priority mapping")
	expect(NoticeScript.priority_for("unknown-kind") == NoticeScript.PRIORITY_INFO, "invalid kinds fall back to info")
	var normalized := NoticeScript.normalize({"kind": "error", "message": "x", "duration": 0})
	expect(float(normalized["duration"]) >= 0.1, "duration clamped positive")
	for invalid_duration: float in [NAN, INF, -INF]:
		var invalid := NoticeScript.normalize({"duration": invalid_duration})
		expect(is_finite(float(invalid.duration)) and float(invalid.duration) > 0.0, "invalid duration cannot pin the notice forever")

	# A queued operation can become an error before the current warning ends.
	# Dedupe must not swallow that escalation or later replay its stale copy.
	presenter.clear_for_test()
	hud.show_warning_message("当前警告", 2.0)
	hud.show_notice({"kind": "info", "message": "操作处理中", "dedupe_key": "operation"})
	hud.show_notice({"kind": "error", "message": "操作失败", "dedupe_key": "operation"})
	expect(presenter.full_text() == "操作失败", "queued error escalation immediately preempts warning")
	expect(presenter.queue_size() == 0, "escalated notice removed from queue")

	hud.queue_free()
	await settle()
	if failures.is_empty():
		print("PLAYER_NOTICE_DEDUPE_PRIORITY_PASS: dedupe, refresh, bounded queue, preemption, priority table")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("PLAYER_NOTICE_DEDUPE_PRIORITY_FAIL: " + failure)
		get_tree().quit(1)
