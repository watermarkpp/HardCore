extends RefCounted
var host: Object
var random: Object
var world: Dictionary
var generation := 0
var ticks := 0
var request: Dictionary
var done := false
var valid := true
var submitted_once := false
func _init(source_host: Object, boot: Dictionary) -> void:
	host = source_host
	world = boot.world_identity
	generation = int(host.capabilities().bridge_generation)
	random = ClassDB.instantiate("HardCoreGameplayGlobalRandom")
	valid = random.initialize_handoff(boot.gameplay_random_handoff)
	valid = valid and random.is_initialized() and random.owner_thread_id() == host.owner_thread_id()
func on_inputs(_domain: String, _packets: Array) -> bool:
	return true
func on_phase(phase: String, frame: Dictionary) -> bool:
	if phase == "H_GROUP":
		ticks += 1
		valid = valid and host.current_clock_frame().has("paused")
		valid = valid and host.current_host_time_scale() == 1.0
		var draw: int = random.randi_range(-10, 10)
		valid = valid and draw >= -10 and draw <= 10
		if not submitted_once:
			var site := {"clock_epoch":int(frame.epoch),"domain":&"H","entry_id":"live_resource_actual_S_fixture","entry_ordinal":1,
				"bootstrap":false,"observation_process_epoch":int(frame.source_process_frame),"world_context":world,"deadline_usec":int(frame.next_release_usec)}
			var prefix := {"bridge_generation":generation,"journal_generation":generation,"through_ordinal":1,
				"events":[{"ordinal":1,"operation":&"fixture_label","arguments":["actual prefix before live status"]}]}
			var reservation := {"contract_id":"hardcore.resource.budget_reservation.v1","reservation_id":1,"owner_session_id":1,
				"ledger_epoch":int(frame.epoch),"category":"fixture_status","lane":0,"reserved_usec":0,"issued_usec":Time.get_ticks_usec()}
			var input := {"protocol":"hardcore.streaming.live_primitives.v1","site":site,"op":&"status",
				"args":["res://tests/framework/no_accepted_live_resource_claim.png"],"reservation":reservation,"main_prefix":prefix,
				"submitted_usec":Time.get_ticks_usec(),"deadline_usec":int(site.deadline_usec),"order_key":"fixture:status:path",
				"dependencies":[],"priority":0,"cleanup":false}
			var original_input := input.duplicate(true)
			var admission: Dictionary = host.submit_live_original_resource(input)
			valid = valid and input == original_input and not input.site.has("call_ordinal")
			if admission.get("status", "") == "PENDING":
				request = admission.request
				submitted_once = true
				var repeated: Dictionary = host.submit_live_original_resource(input)
				valid = valid and (repeated.get("status", "") == "BUSY" or repeated.get("request", {}) == request)
			else:
				valid = valid and admission.get("status", "") in ["BUSY", "BACKPRESSURE"]
	if phase == "PUBLISH":
		if not request.is_empty() and not done:
			var completion: Dictionary = host.poll_live_original_resource(request.identity)
			if completion.get("status", "") == "READY":
				var reply: Dictionary = completion.reply
				valid = valid and reply.result == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and reply.native_deadline_status == "FAIL"
				valid = valid and reply.native_main_prefix_receipt == {"bridge_generation":generation,"journal_generation":generation,"through_ordinal":1,"applied":true}
				var charged := int(reply.finished_usec) - int(reply.started_usec)
				var settlement := {"contract_id":"hardcore.resource.budget_settlement.v1","reservation_id":1,"owner_session_id":1,
					"identity":request.identity,"s_commit_epoch":int(frame.epoch),"main_started_usec":int(reply.started_usec),
					"main_finished_usec":int(reply.finished_usec),"charged_usec":charged,"receipt_received_usec":int(reply.native_received_usec),
					"queue_wait_usec":int(reply.started_usec)-int(request.submitted_usec),"overrun_usec":charged}
				if host.settle_live_original_resource(settlement):
					done = host.retire_live_original_resource(request.identity)
		return host.publish_snapshot({"ticks":ticks,"done":done,"valid":valid}, [])
	return valid
func close_session() -> bool:
	if not done:
		return false
	host.completed_original_main_prefix_receipt()
	return valid and done
