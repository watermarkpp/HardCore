extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REGISTRY := "res://assets/data/features/validation/resource_ready_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _capture(box: Dictionary) -> void:
	box.success = await ContentLayers.reload_feature_catalog_async(REGISTRY)
	box.resume_scopes = Budget.snapshot().open_scopes
	box.finished = true

func _capture_other(box: Dictionary) -> void:
	box.result = await ContentLayers._feature_resource_service.prepare(ContentLayers.feature_configuration().catalog,["hc.resource_ready_probe"])
	box.resume_scopes = Budget.snapshot().open_scopes
	if box.get("cancel_again", "") == "formal_again": ContentLayers.cancel_feature_resource_preparation()
	elif box.get("cancel_again", "") == "service_again": ContentLayers._feature_resource_service.cancel_all()
	box.finished = true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	for mode: String in ["formal", "service", "formal_again", "service_again"]:
		var accuracy: int = PlayerState.computed_stats.accuracy
		var other := {"finished":false,"result":{},"resume_scopes":-1,"cancel_deferred":false,"cancel_again":mode}
		var observation := {"calls":0,"scope":0,"promoted":false,"nested":true,"locked":false}
		var observe := func() -> void:
			observation.calls += 1
			if observation.calls > 1: return
			observation.scope = Budget.snapshot().open_scopes
			observation.promoted = int(PlayerState.computed_stats.accuracy) == accuracy + 1
			if mode == "formal": ContentLayers.cancel_feature_resource_preparation()
			else:
				_capture_other(other)
				ContentLayers._feature_resource_service.cancel_all()
				other.cancel_deferred = not other.finished
			observation.locked = ContentLayers._feature_publication_in_progress
			observation.nested = ContentLayers.set_feature_module_enabled("hc.resource_ready_probe", false)
		ContentLayers.feature_catalog_changed.connect(observe)
		var box := {"finished":false,"success":false,"resume_scopes":-1}
		_capture(box)
		for index in range(180):
			if box.finished: break
			await get_tree().process_frame
		ContentLayers.feature_catalog_changed.disconnect(observe)
		check(observation.promoted and int(observation.scope) > 0, mode + " cancellation observes actual committed publication within its accounted notification")
		check(box.finished and box.success, mode + " cancellation cannot relabel an already committed application as a failed preparation")
		check(int(box.resume_scopes) == 0, mode + " application waiter resumes only after the shared scope closes")
		check(observation.locked and not observation.nested and observation.calls == 1, mode + " cancellation retains the outer publication lock and rejects notification reentry")
		check(int(PlayerState.computed_stats.accuracy) == accuracy + 1 and ContentLayers.feature_configuration().enabled_modules == ["hc.resource_ready_probe"], mode + " committed actor result and enabled source match successful completion")
		check(not ContentLayers._feature_publication_in_progress and Budget.snapshot().open_scopes == 0, mode + " application ownership finishes normally after notification")
		if mode != "formal":
			check(other.cancel_deferred, "reentrant cancellation of another pending caller does not resume it inside the application scope")
			check(other.finished and not bool(other.result.get("success",true)) and int(other.resume_scopes) == 0,
				"other cancelled caller receives exactly the rejected result after scope closure")
		check(ContentLayers.reload_feature_catalog(), mode + " fixture restores through the original synchronous empty path")
	if not proof.write_receipt("feature_resource_promotion_cancel_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_PROMOTION_CANCEL_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
