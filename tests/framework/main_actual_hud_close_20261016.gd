extends Node
const HUD := preload("res://scripts/hud.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1; proof.record(value,label)
	if not value: failures += 1
func _ready() -> void: start.call_deferred()
func start() -> void:
	var hud: CanvasLayer = HUD.new()
	add_child(hud)
	check(hud.is_inside_tree() and hud.get("_all_panels_prewarmed") == false, "actual original HUD exists without fabricated panel readiness")
	# Start the actual seven-script loader coroutine. These are real engine
	# requests and original callback scopes, never injected pending markers.
	Callable(hud,"_prefetch_panel_scripts").call(true)
	var issued: int = hud.get("_panel_script_pending").size()
	var resident: int = hud.get("_panel_script_warm_refs").size()
	check(issued + resident >= 7, "actual original panel loader accepted or completed all seven real script requests")
	check(hud.begin_actual_original_source_prewarm_close(), "same actual HUD cancels only future optional work")
	var before: int = hud.get("_panel_script_pending").size()
	hud.start_budgeted_panel_prewarm()
	hud._start_catalog_icon_prewarm(false)
	check(hud.get("_panel_script_pending").size() == before and hud.get("_catalog_icon_prewarm_in_progress") == false and hud.get("_background_prewarm_requested") == false, "close prevents new optional requests without deleting accepted panel requests")
	var reply: Dictionary = hud.service_actual_original_source_prewarm_close()
	var deadline: int = Time.get_ticks_usec() + 45000000
	while reply.get("status") == "PENDING" and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		reply = hud.service_actual_original_source_prewarm_close()
	check(reply.get("success") == true and reply.get("status") == "READY", "actual terminal loader states and original suspended callbacks drain without a blocking get")
	check(hud.get("_panel_script_pending").is_empty() and reply.get("callback_depth") == 0 and reply.get("accepted_icon_requests") == 0, "same original accepted-request and callback ledgers are truly empty")
	check(reply.get("prewarm_completed") == false and hud.get("_all_panels_prewarmed") == false, "cancelled prewarming is never relabelled completed")
	hud.free()
	check(not is_instance_valid(hud), "the actual HUD exits only after its accepted loads and callbacks retired")
	var written: bool = proof.write_receipt("main_actual_hud_close_20261016",checks,failures)
	print("MAIN_ACTUAL_HUD_CLOSE_20261016_"+("PASS" if written and failures == 0 else "FAIL")+" checks="+str(checks)+" failures="+str(failures))
	get_tree().quit(0 if written and failures == 0 else 1)
