extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const OverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const Scope := preload("res://scripts/features/contracts/loading_preparation_scope.gd")
const SCENE_ID := "code_preparation_cover_surface_test"
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

class Consumer extends Node:
	var generation := 1
	var loading_phase := true
	func is_code_preparation_generation_current(value: int) -> bool:
		return value == generation
	func is_code_preparation_loading_phase_current(value: int) -> bool:
		return value == generation and loading_phase

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _new_cover(overlay: Control, transition: String) -> Dictionary:
	overlay.begin_loading(transition)
	await overlay.transition_covered
	return overlay.code_preparation_cover_receipt()

func _run() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "cover fixture retains non-test runtime setting")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(), "formal runner isolates APPDATA and supplies run identity")
	check(not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(), "cover evidence binds invocation and source bytes")
	check(not ResourceLoader.has_cached(TARGET_SCRIPT), "target Script remains cold before cover checks")
	var stage := Control.new()
	add_child(stage)
	var consumer := Consumer.new()
	stage.add_child(consumer)
	var overlay: Control = OverlayScript.new()
	consumer.add_child(overlay)
	var api_ready := overlay.has_method("code_preparation_cover_receipt") and overlay.has_method("code_preparation_cover_current")
	check(api_ready, "formal overlay exposes a presentation-bound preparation receipt")
	if not api_ready:
		stage.queue_free()
		await get_tree().process_frame
		_finish()
		return
	check(overlay.code_preparation_cover_receipt().is_empty(), "hidden overlay has no preparation witness")
	var receipt: Dictionary = await _new_cover(overlay, "cover.initial")
	check(not receipt.is_empty() and receipt.get("contract_id") == "ui.loading.transition.v1", "existing covered handshake grants a current full viewport surface witness")
	check(receipt.get("shade_instance_id") == overlay.shade.get_instance_id(), "witness binds the actual shade instance")
	check(overlay.code_preparation_cover_current(receipt), "current exact receipt is valid")
	var scope: RefCounted = Scope.issue(overlay, consumer, consumer.generation)
	check(scope != null and scope.valid_for(consumer, consumer.generation), "loading consumer receives one live preparation scope")
	if scope == null:
		stage.queue_free()
		await get_tree().process_frame
		_finish()
		return
	overlay.shade.hide()
	check(overlay.visible and overlay.modulate.a == 1.0, "hidden-shade counterexample retains visible opaque overlay properties")
	check(overlay.code_preparation_cover_receipt().is_empty() and not scope.valid_for(consumer, consumer.generation), "hidden shade retires the current witness and scope")
	overlay.shade.show()
	check(overlay.code_preparation_cover_receipt().is_empty(), "reshowing shade cannot restore a retired receipt without a new presentation")
	receipt = await _new_cover(overlay, "cover.after_hide")
	check(not receipt.is_empty(), "new covered handshake permits legal reentry after hide")
	var original_shade: ColorRect = overlay.shade
	overlay.remove_child(original_shade)
	check(overlay.code_preparation_cover_receipt().is_empty(), "shade outside the SceneTree is rejected")
	stage.add_child(original_shade)
	check(original_shade.is_inside_tree() and overlay.code_preparation_cover_receipt().is_empty(), "in-tree shade with a different parent is rejected")
	stage.remove_child(original_shade)
	overlay.add_child(original_shade)
	check(overlay.code_preparation_cover_receipt().is_empty(), "reattaching shade cannot revive the previous presentation")
	receipt = await _new_cover(overlay, "cover.after_parent")
	check(not receipt.is_empty(), "new handshake permits legal reentry after restoring shade ownership")
	var original_size: Vector2 = original_shade.size
	original_shade.size = original_size * 0.5
	check(overlay.code_preparation_cover_receipt().is_empty(), "a smaller shade cannot certify full viewport coverage")
	original_shade.size = original_size
	check(overlay.code_preparation_cover_receipt().is_empty(), "restored dimensions still require a new presentation")
	receipt = await _new_cover(overlay, "cover.after_size")
	check(not receipt.is_empty(), "new handshake permits legal reentry after restoring coverage")
	consumer.loading_phase = false
	check(Scope.issue(overlay, consumer, consumer.generation) == null, "covered surface alone cannot authorize work outside the Loading phase")
	consumer.loading_phase = true
	scope = Scope.issue(overlay, consumer, consumer.generation)
	consumer.generation += 1
	check(not scope.valid_for(consumer, consumer.generation), "consumer generation change retires the old scope")
	original_shade.queue_free()
	check(overlay.code_preparation_cover_receipt().is_empty(), "queued shade deletion is rejected before physical deletion")
	scope = null
	stage.queue_free()
	await get_tree().process_frame
	check(not ResourceLoader.has_cached(TARGET_SCRIPT), "cover tests never preload, request, retrieve or construct the target Script")
	_finish()

func _finish() -> void:
	print("CODE_PREPARATION_COVER_SURFACE_CHECKS: ", checks, " failures=", failures.size())
	var valid := proof.write_receipt(SCENE_ID, checks, failures.size())
	if valid and failures.is_empty():
		print("CODE_PREPARATION_COVER_SURFACE_PASS: ", checks, " checks; complete receipt valid")
	get_tree().quit(0 if valid and failures.is_empty() else 1)
