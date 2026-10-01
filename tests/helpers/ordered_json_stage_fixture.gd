extends RefCounted

## Observe the real coordinator phase. An optional poll can legally yield
## under the shared frame budget; a previous successful stage is not proof
## that this request has reached its durable promotion stage.
static func await_durable_promotion(service: RefCounted, job: RefCounted, drive: Callable, tree: SceneTree) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while true:
		assert(Time.get_ticks_msec() < deadline, "real promotion stage did not become runnable")
		assert(not service._queue.is_empty() and service._queue[0].job == job,
			"fixture observes the exact ordered request head")
		if str(service._queue[0].phase) == "PROMOTING":
			break
		drive.call()
		assert(not bool(job.response.get("finished", false)), "main has not consumed the promotion receipt")
		if str(service._queue[0].phase) != "PROMOTING":
			await tree.process_frame
	var promoted: Dictionary = job.stage_result(true)
	assert(bool(promoted.finished) and bool(promoted.result.get("success", false)),
		"actual worker promotion completed durably before the foreign-state boundary")
	assert(not bool(job.response.get("finished", false)), "worker completion still awaits its main-thread consumer")
