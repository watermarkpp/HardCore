extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Game := preload("res://scripts/game_root.gd")
const BASELINE := "res://outputs/v115_multicore/world_skill_migration/ORIGINAL_WORLD_INPUT_BASELINE.json"

const WorldRuntime := preload("res://scripts/gameplay/world/world_skill_runtime.gd")
const WorldFields := preload("res://scripts/gameplay/world/world_skill_fields.gd")
const LegacyPorts := preload("res://scripts/gameplay/world/legacy_world_skill_ports.gd")
const ProfileModel := preload("res://scripts/gameplay/profile/profile_model.gd")

class RecordedInputs extends RefCounted:
	# Owner-local replay of values recorded from real M Input. The traced
	# methods require no actor or release; all other production families
	# remain outside this input-ledger witness.
	var frame: Dictionary = {}
	func is_action_pressed(_action: StringName) -> bool: return bool(frame.get("pressed", false))
	func is_action_just_pressed(_action: StringName) -> bool: return bool(frame.get("just_pressed", false))
	func has_button_lifecycle_snapshot() -> bool: return false
	func has_button_lifecycle_owner() -> bool: return false
	func now_msec() -> int: return 1
	func player() -> Object: return null
	func locked_target() -> Object: return null

static func foreign_input_probe(core: RefCounted) -> Dictionary:
	var before: int = core._allocate_synthetic_attack_token()
	core._next_synthetic_attack_token = -99
	return {"query_rejected": before == 0, "snapshot_rejected": core.attack_action_lifecycle_snapshot().is_empty()}

static func owner_input_replay(frames: Array) -> Dictionary:
	var core := WorldRuntime.new()
	var fields := WorldFields.new()
	var inputs := RecordedInputs.new()
	var profile := ProfileModel.new()
	var unused_execution := RefCounted.new()
	var unconfigured_rejects := core._allocate_synthetic_attack_token() == 0 and core.attack_action_lifecycle_snapshot().is_empty()
	core._next_synthetic_attack_token = -77
	var bindings := {"fields":fields, "profile":profile, "input":inputs,
		"clock":inputs, "actors":inputs, "execution":unused_execution, "presentation":unused_execution}
	var configured := core.configure_ports(bindings)
	if not configured: return {"configured":false}
	var rejected_repeat := not core.configure_ports(bindings)
	var trace: Array = []
	var steps := script_steps()
	for index in steps.size():
		inputs.frame = frames[index]
		var step: Array = steps[index]
		trace.append([core.callv(step[1],step[2]), normalized(core.attack_action_lifecycle_snapshot())])
	var tail := ledger_tail(core)
	var before: int = core._next_synthetic_attack_token
	var foreign := Thread.new()
	var started := foreign.start(foreign_input_probe.bind(core)) == OK
	var foreign_result: Dictionary = foreign.wait_to_finish() if started else {}
	return {"configured":true,"unconfigured_rejects":unconfigured_rejects,
		"rejected_repeat":rejected_repeat,"owner_thread":OS.get_thread_caller_id(),
		"result_sha256":digest([trace,tail]),"foreign_started":started,
		"foreign_query_rejected":foreign_result.get("query_rejected",false),
		"foreign_snapshot_rejected":foreign_result.get("snapshot_rejected",false),
		"foreign_write_rejected":core._next_synthetic_attack_token == before,
		"trace":trace,"tail":tail}

var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

static func normalized(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	for event: Dictionary in result.get("events", []): event.erase("time_ms")
	return result

static func digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()

static func script_steps() -> Array:
	return [
		[true, "_reset_attack_action_lifecycle", [&"fixture_entry"]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[false, "_poll_attack_action_lifecycle", [true]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[false, "_poll_attack_action_lifecycle", [true]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[true, "_poll_attack_action_lifecycle", [false]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[false, "_poll_attack_action_lifecycle", [true]],
		[true, "_poll_attack_action_lifecycle", [true]],
		[true, "_reset_attack_action_lifecycle", [&"fixture_focus_out"]],
		[true, "_poll_attack_action_lifecycle", [true]],
	]

static func ledger_tail(source: Object) -> Array:
	var result: Array = []
	result.append(source._allocate_synthetic_attack_token())
	result.append(source._allocate_synthetic_attack_token())
	source._active_mobile_attack_tokens = {17:{"touch_id":3,"source":&"touch"},18:{"touch_id":4,"source":&"touch"}}
	source._queued_mobile_attack_tickets = [77] as Array[int]
	source._refresh_mobile_attack_held()
	source._on_mobile_attack_input_ended(17, 4, &"touch")
	result.append(normalized(source.attack_action_lifecycle_snapshot()))
	source._on_mobile_attack_input_ended(17, 3, &"touch")
	result.append(normalized(source.attack_action_lifecycle_snapshot()))
	source._on_mobile_attack_input_cancelled(18, 4, &"touch", &"fixture_cancel")
	result.append(normalized(source.attack_action_lifecycle_snapshot()))
	source._queued_mobile_attack_tickets = [88] as Array[int]
	result.append(source._drain_next_mobile_attack_ticket())
	result.append(source._queued_mobile_attack_tickets.duplicate())
	var input_key: String = source._skill_input_key("attack",0,19,5)
	source._active_skill_inputs = {input_key:{"repeatable":false,"sequence":1}}
	source._skill_input_retry_remaining = 0.03
	source._process_skill_input_actions(0.02)
	result.append(source._skill_input_retry_remaining)
	source._process_skill_input_actions(0.02)
	result.append(source._skill_input_retry_remaining)
	source._on_skill_input_ended("attack",0,19,5,&"touch")
	result.append(source._active_skill_inputs.duplicate(true))
	source._keyboard_bound_skill_token = 7
	source._cancel_all_skill_inputs(true)
	result.append([source._keyboard_bound_skill_token,source._skill_input_retry_remaining])
	return result

func _run() -> void:
	var game := Game.new()
	game._register_input_actions()
	Input.action_release("attack")
	await get_tree().process_frame
	var adapted_game := Game.new()
	var legacy_ports := LegacyPorts.new(adapted_game)
	var legacy_core := WorldRuntime.new()
	check(legacy_core.configure_ports({"fields":legacy_ports,"profile":PlayerState._model,
		"input":legacy_ports,"clock":legacy_ports,"actors":legacy_ports,
		"execution":legacy_ports,"presentation":legacy_ports}), "real M ports bind the existing GameRoot state and ProfileModel")
	var adapted_trace: Array = []
	var trace: Array = []
	var frames: Array = []
	for step: Array in script_steps():
		if step[0]: Input.action_press("attack")
		else: Input.action_release("attack")
		frames.append({"pressed":Input.is_action_pressed("attack"),"just_pressed":Input.is_action_just_pressed("attack")})
		trace.append([game.callv(step[1],step[2]), normalized(game.attack_action_lifecycle_snapshot())])
		adapted_trace.append([legacy_core.callv(step[1],step[2]), normalized(legacy_core.attack_action_lifecycle_snapshot())])
	var tail := ledger_tail(game)
	var adapted_tail := ledger_tail(legacy_core)
	var baseline := {"steps":script_steps(),"frames":frames,"trace":trace,"tail":tail,
		"result_sha256":digest([trace,tail]),"game_root_sha256":FileAccess.get_sha256("res://scripts/game_root.gd")}
	if not FileAccess.file_exists(BASELINE):
		var file := FileAccess.open(BASELINE, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(baseline,"  ",true,true))
			file.close()
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	check(digest([adapted_trace,adapted_tail]) == original.result_sha256, "real live M field adapter preserves the original input trace and ledger")
	check(digest([trace,tail]) == original.result_sha256, "actual GameRoot input trace matches its original source witness")
	check(not trace[1][0].active and trace[1][1].events.size() == trace[2][1].events.size(), "inherited pressed action is rejected once per lifecycle")
	check(trace[4][0].started and trace[5][0].active and not trace[5][0].started and trace[6][0].ended, "fresh press continuous hold and release keep the original ownership")
	check(not trace[8][0].active and not trace[9][0].active and not trace[13][0].active, "disabled or focus boundary cannot reanimate the held input")
	check(tail[0] == -1 and tail[1] == -2 and tail[2].active_touch_count == 2 and tail[3].active_touch_count == 1 and tail[4].active_touch_count == 0, "matching touch identity owns release and synthetic tokens preserve their sequence")
	check(tail[5] == false and tail[6].is_empty() and tail[8] == 0.05 and tail[9].is_empty() and tail[10] == [0,0.0], "legacy debt clears and skill retry and cancellation retain original values")
	check(FileAccess.file_exists("res://scripts/gameplay/world/world_skill_runtime.gd"), "WorldSkillRuntime contains the same non Node input method family")
	var worker := Thread.new()
	check(worker.start(owner_input_replay.bind(frames.duplicate(true))) == OK, "input owner is constructed and replayed on a real S Thread")
	var replay: Dictionary = worker.wait_to_finish()
	check(replay.get("configured",false) and replay.get("owner_thread",OS.get_main_thread_id()) != OS.get_main_thread_id(), "world input fields and real ProfileModel are owner-local non Node objects")
	check(replay.get("result_sha256", "") == original.result_sha256, "real S input trace and ledger match the original GameRoot witness")
	check(replay.get("unconfigured_rejects",false) and replay.get("rejected_repeat",false), "world input rejects unconfigured calls and repeat binding")
	check(replay.get("foreign_started",false) and replay.get("foreign_query_rejected",false) and replay.get("foreign_snapshot_rejected",false), "foreign Thread cannot allocate tokens or read lifecycle state")
	check(replay.get("foreign_write_rejected",false), "foreign Thread cannot replace the owner's input token state")
	adapted_game.free()
	game.free()
	Input.action_release("attack")
	proof.write_receipt("multicore_world_skill_input_20261014", proof.records.size(), failures.size())
	print("MULTICORE_WORLD_SKILL_INPUT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), failures])
	get_tree().quit(0 if failures.is_empty() else 1)
