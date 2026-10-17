extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const CORE_PATH := "res://scripts/gameplay/actors/monster_action_timeline.gd"
var proof := Proof.new()
var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(FileAccess.file_exists(CORE_PATH), "production Node-free action timeline exists")
	if not FileAccess.file_exists(CORE_PATH):
		_finish()
		return
	var script: Script = load(CORE_PATH)
	var timeline: Object = script.new()
	check(not timeline is Node, "action state can live without a SceneTree object")
	timeline.enqueue(timeline.STRUCK, 0.25, -1)
	check(timeline.try_start_next(true, false, false) == timeline.STRUCK, "idle owner starts first hit immediately")
	check(timeline.pending_struck_count == 0 and timeline.hit_remaining == 0.25, "playing hit leaves the waiting queue")
	var paused: float = timeline.advance_struck(0.10, 1.10, false, -1.0, 0.0, 0.0, false)
	check(is_equal_approx(paused, 0.10) and is_equal_approx(timeline.hit_remaining, 0.15), "physics consumes exact hit slice")
	timeline.enqueue(timeline.STRUCK, 0.125, -1)
	paused = timeline.advance_struck(0.20, 1.30, false, -1.0, 0.0, 0.0, false)
	check(is_equal_approx(paused, 0.20) and is_equal_approx(timeline.hit_remaining, 0.075), "one interval crosses hit boundary without backlog acceleration")
	check(timeline.hit_start_serial == 2 and timeline.pending_struck_count == 0, "each queued hit starts once")

	var overlap: RefCounted = script.new()
	overlap.attack_duration = 0.46
	overlap.attack_action_id = 7
	overlap.enqueue(overlap.STRUCK, 0.25, -1)
	check(overlap.try_start_next(true, true, false) == -1, "logical attack prevents early dequeue even with zero visual cache")
	paused = overlap.advance_struck(0.10, 0.40, true, 0.0, 0.46, 0.40, false)
	check(paused == 0.0 and overlap.pending_struck_count == 1, "active attack spends no struck interval")
	paused = overlap.advance_struck(0.10, 0.50, false, 0.0, 0.46, 0.50, false)
	check(is_equal_approx(paused, 0.04) and is_equal_approx(overlap.hit_remaining, 0.21), "attack ending inside physics step leaves only residual slice")
	var before: float = overlap.hit_remaining
	check(overlap.advance_struck(0.10, 0.60, false, 0.0, 0.46, 0.60, true) == 0.0 and overlap.hit_remaining == before, "death blocks consumption")
	check(overlap.advance_struck(0.0, 0.60, false, 0.0, 0.46, 0.60, false) == 0.0, "zero interval does not advance")
	overlap.motion_overridden_attack_action_id = 7
	overlap.attack_remaining = 0.2
	overlap.advance_struck(0.1, 0.4, true, 0.0, 0.46, 0.4, false)
	check(overlap.attack_remaining == 0.0, "motion override suppresses visual cache while logical attack still owns interval")

	var fifo: RefCounted = script.new()
	fifo.enqueue(fifo.STRUCK, 0.125, 11)
	fifo.enqueue(fifo.ATTACK, 0.5, 12)
	fifo.enqueue(fifo.STRUCK, 0.25, 13)
	check(fifo.merge_pending_struck_feedback() == 3, "attack admission merges all waiting presentations")
	check(fifo.presentation_count == 1 and fifo.pending_struck_count == 1 and fifo.presentation_duration[0] == 0.25 and fifo.presentation_step_barrier[0] == 13, "merge retains newest struck duration and legacy barrier")
	fifo.clear_queue()
	for index in range(fifo.QUEUE_CAPACITY):
		fifo.enqueue(fifo.STRUCK, 0.125, index)
	fifo.enqueue(fifo.STRUCK, 0.25, 99)
	check(fifo.presentation_count == 2 and fifo.pending_struck_count == 2 and fifo.last_backpressure_collapsed == 15, "full struck ring collapses before new append")
	fifo.clear_queue()
	for index in range(fifo.QUEUE_CAPACITY):
		fifo.enqueue(fifo.ATTACK, 0.5, index)
	fifo.enqueue(fifo.STRUCK, 0.25)
	check(fifo.last_enqueue_overflow and fifo.presentation_count == fifo.QUEUE_CAPACITY and fifo.pending_struck_count == 0, "full attack-only ring rejects newest event")
	fifo.clear_queue()
	fifo.enqueue(fifo.ATTACK, 0.5)
	fifo.enqueue(fifo.STRUCK, 0.25)
	check(fifo.advance_struck(1.0, 1.0, false, -1.0, 0.0, 0.0, false) == 0.0 and fifo.presentation_count == 2, "physics struck advance cannot bypass an earlier preview attack")
	check(fifo.try_start_next(false, false, false) == fifo.ATTACK and fifo.dequeued_duration == 0.5, "preview FIFO returns original attack first")
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_actor_timeline_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_ACTOR_TIMELINE_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)

