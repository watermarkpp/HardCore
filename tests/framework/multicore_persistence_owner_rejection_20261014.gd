extends Node
const Prepared := preload("res://scripts/json_prepared_request.gd")
const LegacyBudget := preload("res://scripts/gameplay/profile/legacy_persistence_budget.gd")
const Service := preload("res://scripts/json_persistence_service.gd")
const LegacyContent := preload("res://scripts/gameplay/profile/legacy_profile_content.gd")
const LegacyRules := preload("res://scripts/gameplay/profile/legacy_profile_rules.gd")
const Pricing := preload("res://scripts/pricing_service.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof = Proof.new()
var failures: Array[String] = []
var checks := 0
func _ready() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	PlayerState.test_mode = true
	var service := Service.new()
	# Use the externally scheduled budget on the real creating owner so this
	# illegal-owner probe cannot touch the legacy FrameBudget while RED.
	service.configure_owner("simulation")
	var path := "user://illegal_owner_%d_%d/profile.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var callbacks: Array[int] = []
	var validator := func(_document: Dictionary) -> Dictionary: return {"valid": true}
	var complete := func(_receipt: Dictionary) -> void: callbacks.append(OS.get_thread_caller_id())
	var job: RefCounted = service.submit(path, {"profile_id":"owner", "domain":"owner"}, {"gold":19}, validator,
		Callable(), false, null, complete, true)
	check(job != null and bool(service.finish_preparation(job, true).get("success", false)), "actual owner prepares a real staged JSON request")
	var handle := Prepared.new()
	handle.configure(service, job)
	var worker := Thread.new()
	check(worker.start(_illegal_owner.bind(service, job, path, handle)) == OK, "a different real Godot Thread attempts the prepared request")
	while worker.is_alive(): await get_tree().process_frame
	var raw: Variant = worker.wait_to_finish()
	var result: Dictionary = raw if raw is Dictionary else {}
	check(str(result.get("finish_reason", "")) == "persistence_owner_mismatch", "wrong owner receives an explicit failed finish result")
	check(callbacks.is_empty(), "wrong owner cannot consume the accepted completion callback")
	check(not FileAccess.file_exists(path), "wrong owner cannot promote the actual prepared file")
	check(service.pending_count() == 1 and not bool(job.response.get("finished", false)) and not bool(service._queue[0].allow_promotion) and not job.cancellation_requested(), "rejection leaves the accepted request pending with its original owner")
	check(bool(result.get("other_entries_rejected", false)), "submit cleanup pump drain authorize cancel and read APIs reject the wrong owner")
	check(bool(result.get("handle_rejected", false)) and not handle._cancelled, "prepared handle rejects wrong-owner completion cancellation and binding")
	check(bool(result.get("budget_rejected", false)), "legacy budget rejects Thread access before calling main FrameBudget")
	check(bool(result.get("legacy_fallback_rejected", false)), "missing S content cannot access main autoload rules or pricing cache")
	var receipt: Dictionary = service.finish(job, true)
	check(bool(receipt.get("success", false)) and callbacks == [OS.get_main_thread_id()], "the original owner still completes the same request exactly once")
	check(service.pending_count() == 0 and int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 19, "owner completion durably saves the unchanged approved contents")
	if not proof.write_receipt("multicore_persistence_owner_rejection_20261014", checks, failures.size()): failures.append("receipt")
	print("MULTICORE_PERSISTENCE_OWNER_REJECTION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _illegal_owner(service: RefCounted, job: RefCounted, path: String, handle: RefCounted) -> Dictionary:
	var raw: Variant = service.finish(job, true)
	var receipt: Dictionary = raw if raw is Dictionary else {}
	var result := {"finish_reason":str(receipt.get("reason", "")), "other_entries_rejected":false,
		"legacy_fallback_rejected":false}
	# On old source finish already demonstrates the violation; avoid probing
	# further legacy autoload access after that real RED witness.
	if str(receipt.get("reason", "")) != "persistence_owner_mismatch": return result
	var prepare_result: Dictionary = service.finish_preparation(job, false)
	service.authorize(job)
	service.cancel_uncommitted_domain("owner")
	result.other_entries_rejected = (not service.configure_owner("legacy_main") and not service.configure_process_owner(null)
		and service.submit(path + ".other", {}, {}, Callable()) == null
		and service.submit_cleanup(path.get_base_dir(), {}, 1) == null
		and not service.pump() and not service.drain() and not service.cancel(job)
		and service.owner_context().is_empty() and service.work_snapshot().is_empty()
		and service.pending_count() == -1 and not service.has_pending_domain("owner")
		and str(prepare_result.get("reason", "")) == "persistence_owner_mismatch")
	var illegal_handle := Prepared.new()
	illegal_handle.configure(service, job)
	result.handle_rejected = (not handle.cancel() and str(handle.result(true).get("reason", "")) == "persistence_owner_mismatch"
		and illegal_handle.job == null and illegal_handle._service == null)
	var legacy_budget := LegacyBudget.new()
	legacy_budget.configure(null)
	legacy_budget.mark_pending("illegal-owner", true, true)
	legacy_budget.end(1)
	legacy_budget.release("illegal-owner")
	result.budget_rejected = legacy_budget.begin("illegal-owner", true) == 0
	result.legacy_fallback_rejected = (LegacyContent.resolve() == null and LegacyRules.rules() == null
		and Pricing.policy().is_empty())
	return result
