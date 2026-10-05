extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Coordinator := preload("res://scripts/world_bootstrap_coordinator.gd")
var proof := Proof.new()
var failures: Array[String] = []
var coordinator := Coordinator.new()
var old_generation := -1
var old_finished := false
var old_calls: Array[String] = []
var new_calls: Array[String] = []
var takeover_scheduled := false
var takeover_done := false
var quantum := 0
var budget_ms := 0.0
var synchronous_calls: Array[String] = []
var shared_queue: Array

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	quantum = int(ProjectSettings.get_setting("world/loading/max_items_per_frame", Coordinator.DEFAULT_MAX_ITEMS_PER_FRAME))
	budget_ms = float(ProjectSettings.get_setting("world/loading/slice_budget_ms", Coordinator.DEFAULT_SLICE_BUDGET_MS))
	check(quantum > 0 and budget_ms > 0.0, "original configured frame quantum and budget are valid")
	if quantum <= 0 or budget_ms <= 0.0:
		_finish(); return
	coordinator.begin_map_transition(101)
	coordinator.advance(Coordinator.Stage.BUILD_MAP)
	old_generation = coordinator.generation
	shared_queue = coordinator._map_build_queue
	var descriptors: Array = []
	for index in range(quantum + 1):
		descriptors.append({"owner": "A", "index": index})
	coordinator.submit_map_descriptors(descriptors)
	check(coordinator.defer_between_slices, "real production queue uses SceneTree frame waits")
	_consume_old_queue()
	check(not old_finished and not coordinator._map_build_queue.is_empty(), "A suspended at its real frame boundary with original work pending")
	var deadline := Time.get_ticks_msec() + 2000
	while not old_finished and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(takeover_done and old_finished, "deferred B takeover and A continuation actually execute within two seconds")
	check(coordinator.generation == old_generation + 1, "original begin_map_transition creates exactly one new coordinator generation")
	check(is_same(shared_queue, coordinator._map_build_queue), "B reused the actual coordinator-owned Array rather than a queue copy")
	check(not "B" in old_calls, "retired A callback never consumes B's newly submitted map descriptor")
	check(coordinator.built_map_item_count == 0 and coordinator._map_build_queue.size() == 1,
		"A continuation leaves B's original queue and build counters untouched")
	await coordinator.process_map_queue(Callable(self, "_new_handler"), quantum, budget_ms)
	check(new_calls == ["B"] and coordinator.built_map_item_count == 1 and coordinator._map_build_queue.is_empty(),
		"B's sole current-generation consumer builds its own exact descriptor once")
	await _synchronous_takeover_probe()
	_finish()

func _synchronous_takeover_probe() -> void:
	coordinator.begin_map_transition(103)
	coordinator.advance(Coordinator.Stage.BUILD_MAP)
	coordinator.submit_map_descriptors([{"owner": "C"}, {"owner": "C"}])
	await coordinator.process_map_queue(Callable(self, "_synchronous_handler"), quantum, budget_ms)
	check(synchronous_calls == ["C"], "synchronous owner replacement stops the old slice before consuming new work")
	check(coordinator.built_map_item_count == 0 and coordinator._map_build_queue.size() == 1
		and coordinator.map_slice_count == 0, "returned old callback cannot write any new owner item or slice counter")
	await coordinator.process_map_queue(Callable(self, "_new_handler"), quantum, budget_ms)
	check(coordinator.built_map_item_count == 1 and coordinator._map_build_queue.is_empty(),
		"new owner still consumes its original descriptor after synchronous takeover")

func _synchronous_handler(item: Dictionary) -> bool:
	synchronous_calls.append(str(item.owner))
	if item.owner == "C":
		coordinator.begin_map_transition(104)
		coordinator.advance(Coordinator.Stage.BUILD_MAP)
		coordinator.submit_map_descriptors([{"owner": "D"}])
	return true

func _consume_old_queue() -> void:
	await coordinator.process_map_queue(Callable(self, "_old_handler"), quantum, budget_ms)
	old_finished = true

func _old_handler(item: Dictionary) -> bool:
	old_calls.append(str(item.owner))
	if not takeover_scheduled:
		takeover_scheduled = true
		_take_over.call_deferred()
	return true

func _take_over() -> void:
	check(not old_finished and coordinator.generation == old_generation and not coordinator._map_build_queue.is_empty(),
		"B takes over after A yielded, before A finished its original queue")
	coordinator.begin_map_transition(102)
	coordinator.advance(Coordinator.Stage.BUILD_MAP)
	coordinator.submit_map_descriptors([{"owner": "B", "index": 0}])
	takeover_done = true

func _new_handler(item: Dictionary) -> bool:
	new_calls.append(str(item.owner))
	return true

func _finish() -> void:
	print("QUEUE_TAKEOVER_OBSERVATION ", JSON.stringify({"old_generation": old_generation,
		"current_generation": coordinator.generation, "quantum": quantum, "budget_ms": budget_ms,
		"old_calls": old_calls, "new_calls": new_calls, "old_finished": old_finished,
		"takeover_done": takeover_done, "built_map_items": coordinator.built_map_item_count}))
	var ok := proof.write_receipt("published_queue_generation_takeover_test", proof.records.size(), failures.size())
	print("PUBLISHED_QUEUE_GENERATION_TAKEOVER_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
