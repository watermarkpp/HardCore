extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	var original_buffs: Dictionary = PlayerState.temporary_item_buffs.duplicate(true)
	var original_relic: Dictionary = PlayerState._relic_proc_state.duplicate(true)
	PlayerState.temporary_item_buffs = {"fixture.pause": {"remaining": 20.0}}
	PlayerState._relic_proc_state.remaining = 20.0
	PlayerState._relic_proc_state.cooldown = 20.0
	var completion_count := [0]
	var receipt_during_pause := [false]
	var path := "user://framework_paused_receipt_%d/receipt.json" % Time.get_ticks_usec()
	var job: RefCounted = PlayerState._json_persistence.submit(path,
		{"profile_id": "fixture:pause", "sequence": 1}, {"receipt": 1},
		func(_document: Dictionary) -> Dictionary: return {"valid": true, "terminal": false},
		Callable(), false, null, func(receipt: Dictionary) -> void:
			completion_count[0] += 1
			receipt_during_pause[0] = get_tree().paused
			check(bool(receipt.success) and OS.get_thread_caller_id() == OS.get_main_thread_id(),
				"paused receipt applies once on main after durable success"))
	check(job != null, "existing PlayerState ordered writer accepts the private request")
	get_tree().paused = true
	var buff_before: float = PlayerState.temporary_item_buffs["fixture.pause"].remaining
	var relic_before: float = PlayerState._relic_proc_state.remaining
	var cooldown_before: float = PlayerState._relic_proc_state.cooldown
	var deadline := Time.get_ticks_msec() + 3000
	var frames := 0
	if job != null:
		while not bool(job.response.get("finished", false)) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			frames += 1
		check(bool(job.response.get("finished", false)), "real queued JSON request completes while SceneTree is paused")
	check(completion_count[0] == 1 and receipt_during_pause[0], "pause permits receipts without waiting for gameplay resume")
	check(frames > 0, "test observes actual paused process iterations")
	check(is_equal_approx(float(PlayerState.temporary_item_buffs["fixture.pause"].remaining), buff_before),
		"receipt processing does not advance temporary potion buffs")
	check(is_equal_approx(float(PlayerState._relic_proc_state.remaining), relic_before)
		and is_equal_approx(float(PlayerState._relic_proc_state.cooldown), cooldown_before),
		"receipt processing does not advance relic duration or cooldown")
	get_tree().paused = false
	# Failure cleanup uses the explicit lifecycle barrier only after observing
	# the paused outcome. It cannot manufacture the earlier PASS assertions.
	if job != null and not bool(job.response.get("finished", false)):
		PlayerState._json_persistence.finish(job, true)
	check(PlayerState._json_persistence.pending_count() == 0, "private request and worker tasks drain")
	PlayerState.temporary_item_buffs = original_buffs
	PlayerState._relic_proc_state = original_relic
	if not _proof.write_receipt("paused_persistence_receipt_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_PAUSED_PERSISTENCE_RECEIPT_PASS" if failures.is_empty()
		else "FRAMEWORK_PAUSED_PERSISTENCE_RECEIPT_FAIL") + " checks=" + str(checks)
		+ " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
