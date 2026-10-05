extends Node

## Exercise the performance observer in real engine catch-up frames. The
## deliberate idle stall belongs only to this test, never to gameplay.
class Sampler extends "res://tests/hc_monster_combat_r4/t6_real_load_probe.gd":
	func _ready() -> void:
		process_physics_priority = OBSERVER_PRIORITY
		process_priority = OBSERVER_PRIORITY
		set_physics_process(true)

class NativeActor extends Node:
	var last_tick := -1
	var calls := 0
	func _physics_process(_delta: float) -> void:
		last_tick = Engine.get_physics_frames()
		calls += 1

class IdleStall extends Node:
	var enabled := false
	func _process(_delta: float) -> void:
		if enabled:
			OS.delay_msec(50)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var actor := NativeActor.new()
	var stall := IdleStall.new()
	var sampler := Sampler.new()
	add_child(actor)
	add_child(stall)
	add_child(sampler)
	assert(actor.process_physics_priority < sampler.process_physics_priority)
	sampler.measuring_callbacks = true
	var actual_sets := []
	for stalled: bool in [false, true]:
		stall.enabled = stalled
		var ticks: Array[int] = []
		var start_tick := Engine.get_physics_frames()
		var start_calls := actor.calls
		for i in range(48):
			await sampler.native_physics_boundary
			var tick := Engine.get_physics_frames()
			assert(actor.last_tick == tick, "sampler ran before the native actor")
			assert(tick == start_tick + i + 1, "sampler skipped a native catch-up tick")
			ticks.append(tick)
		assert(actor.calls - start_calls == 48, "sample count does not match real actor callbacks")
		actual_sets.append({"stalled": stalled, "first_tick": ticks.front(), "last_tick": ticks.back(), "calls": actor.calls - start_calls})
	sampler.measuring_callbacks = false
	assert(not sampler.process_sample_overflow and sampler.process_callbacks.size() >= 3, "native process samples missing")
	assert(sampler.process_callbacks[0].process_callback_interval_ms == null, "first process callback includes a partial interval")
	for i in range(1, sampler.process_callbacks.size()):
		assert(sampler.process_callbacks[i].frame == sampler.process_callbacks[i - 1].frame + 1, "native process callback skipped")
		assert(sampler.process_callbacks[i].process_callback_interval_ms != null, "native process interval absent")
	# Show the old signal-then-idle await really skips native physics under the
	# same fault. This is a negative control, not a filter of observed records.
	var old_ticks: Array[int] = []
	for _i in range(12):
		await get_tree().physics_frame
		await get_tree().process_frame
		old_ticks.append(Engine.get_physics_frames())
	var skipped: int = old_ticks.back() - old_ticks.front() + 1 - old_ticks.size()
	assert(skipped > 0, "idle fault did not exercise old sampling alias")
	stall.enabled = false
	sampler.set_physics_process(false)
	print("R4_NATIVE_PHYSICS_SAMPLING_PASS ", JSON.stringify({"native": actual_sets, "old_skipped": skipped}))
	get_tree().quit(0)
