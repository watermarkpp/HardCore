extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const BASELINE_PATH := "res://outputs/v115_multicore/gameplay_migration/HEAD_MONSTER_VISUAL_45170d0.gd.txt"
const BASELINE_SHA := "2027ca7a9ee308802eda38259faef9ab462c5961b648b4da328024e414cce2ed"
var proof := Proof.new()
var errors: Array[String] = []

class ClockProbe extends RefCounted:
	var now_ms := 0
	var now_s := 0.0
	func milliseconds() -> int:
		return now_ms
	func seconds() -> float:
		return now_s

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _snapshot(visual: Object) -> Dictionary:
	var waiting: Array = []
	for index in range(visual._presentation_count):
		var slot: int = (visual._presentation_head + index) % visual.PRESENTATION_QUEUE_CAPACITY
		waiting.append([visual._presentation_kind[slot], visual._presentation_duration[slot], visual._presentation_step_barrier[slot]])
	return {
		"waiting": waiting, "pending": visual._pending_struck_count,
		"head": visual._presentation_head, "tail": visual._presentation_tail,
		"hit": visual._hit_remaining, "hit_duration": visual._hc_m30_hit_duration,
		"attack": visual._attack_remaining, "attack_duration": visual._hc_m30_attack_duration,
		"action_id": visual._attack_action_id,
		"override_id": visual._motion_overridden_attack_action_id,
		"action_duration": visual._action_duration, "elapsed": visual._elapsed,
		"death": visual._death_remaining,
	}

func _run() -> void:
	check(FileAccess.get_sha256(BASELINE_PATH) == BASELINE_SHA, "baseline oracle is the exact pinned HEAD source")
	if not errors.is_empty():
		_finish()
		return
	var source := FileAccess.get_file_as_string(BASELINE_PATH)
	# Only detach the global class registration. All rule bodies remain the
	# exact Git source, loaded as an independent script for this audit.
	check(source.begins_with("class_name MonsterVisual"), "baseline class declaration is the expected one-line adjustment")
	source = source.substr(source.find("\n") + 1)
	var original_script := GDScript.new()
	original_script.source_code = source
	check(original_script.reload() == OK, "original HEAD visual compiles for direct comparison")
	if not errors.is_empty():
		_finish()
		return
	var old_owner := EnemyActor.new()
	var new_owner := EnemyActor.new()
	var old_visual: Object = original_script.new()
	var new_visual := MonsterVisual.new()
	old_visual.setup(old_owner)
	new_visual.setup(new_owner)
	old_visual.visible = false
	new_visual.visible = false
	var clock := ClockProbe.new()
	for visual: Object in [old_visual, new_visual]:
		visual._clock_ms = Callable(clock, "milliseconds")
		visual._start_attack_visual(0.30)
	clock.now_ms = 100
	old_visual._advance_action_timers(0.10)
	new_visual._advance_action_timers(0.10)
	check(old_visual._attack_remaining == 0.0, "pinned HEAD reproduces the sentinel -1 preview failure")
	check(_snapshot(old_visual) == _snapshot(new_visual), "migration preserves the original unbound preview branch")
	print("BASELINE_PREVIEW_WITNESS original=", old_visual._attack_remaining, " candidate=", new_visual._attack_remaining)

	clock.now_s = 0.49
	for owner: EnemyActor in [old_owner, new_owner]:
		owner._attack_action_start_time_s = 0.49
		owner._attack_action_duration_s = 0.46
		owner._attack_action_active = true
	for visual: Object in [old_visual, new_visual]:
		visual._combat_clock_s = Callable(clock, "seconds")
		visual.begin_attack_presentation(0.46, 1, -1, Vector2.RIGHT, 0.49)
		visual.queue_struck(43)
	check(_snapshot(old_visual) == _snapshot(new_visual), "critical admission and queued authored hit match original")
	clock.now_s = 0.59
	check(old_visual.advance_struck_action(0.10) == new_visual.advance_struck_action(0.10), "active attack consumes no hit interval in either implementation")
	check(_snapshot(old_visual) == _snapshot(new_visual), "active attack state agrees")
	clock.now_s = 0.99
	old_owner._attack_action_active = false
	new_owner._attack_action_active = false
	var old_pause: float = old_visual.advance_struck_action(0.40)
	var new_pause: float = new_visual.advance_struck_action(0.40)
	check(is_equal_approx(old_pause, 0.04) and old_pause == new_pause, "original and extracted paths spend only post-attack residual slice")
	check(_snapshot(old_visual) == _snapshot(new_visual), "first struck remainder and render reset match original")
	for visual: Object in [old_visual, new_visual]:
		visual._enqueue_presentation(0, 0.125, 7)
		visual._enqueue_presentation(0, 0.250, 8)
	clock.now_s += 1.0
	check(old_visual.advance_struck_action(1.0) == new_visual.advance_struck_action(1.0), "one interval crossing multiple hit starts returns identical pause")
	check(_snapshot(old_visual) == _snapshot(new_visual), "batched render reset is identical after multiple hit starts")
	for visual: Object in [old_visual, new_visual]:
		for index in range(16):
			visual._enqueue_presentation(0, 0.125 + float(index) / 1000.0, index)
		visual._enqueue_presentation(0, 0.25, 99)
	check(_snapshot(old_visual) == _snapshot(new_visual), "full ring collapses and appends exactly as original")
	check(old_visual.begin_attack_presentation(0.30, 2, 2000, Vector2.LEFT, clock.now_s) == new_visual.begin_attack_presentation(0.30, 2, 2000, Vector2.LEFT, clock.now_s), "critical supersession has the same admission result")
	check(_snapshot(old_visual) == _snapshot(new_visual), "critical supersession keeps same newest struck")
	check(not old_visual.begin_attack_presentation(0.30, 2) and not new_visual.begin_attack_presentation(0.30, 2), "same action retry is idempotent in original and extracted paths")
	old_visual.mark_attack_motion_overridden(2)
	new_visual.mark_attack_motion_overridden(2)
	check(_snapshot(old_visual) == _snapshot(new_visual), "motion override preserves exact matching action state")
	old_visual.play_death(0.62)
	new_visual.play_death(0.62)
	check(_snapshot(old_visual) == _snapshot(new_visual), "death clears the same queue and clocks")
	old_visual.free()
	new_visual.free()
	old_owner.free()
	new_owner.free()
	check(FileAccess.get_sha256(BASELINE_PATH) == BASELINE_SHA, "baseline oracle bytes remain fixed for the complete comparison")
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_actor_baseline_equivalence_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_ACTOR_BASELINE_EQUIVALENCE_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
