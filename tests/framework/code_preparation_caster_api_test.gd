extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const OverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const Data := preload("res://scripts/features/generated/internal_code_preparation_catalog_data.gd")
const Guard := preload("res://scripts/features/compilation/code_preparation_envelope_guard.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const SCENE_ID := "code_preparation_caster_api_test"
const ENTRY_ID := "framework.code.caster_animation.v1"
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
@export var owner_mode := "normal"
@export var receipt_scene_id := SCENE_ID
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

class Consumer extends Control:
	var generation := 1
	var loading_phase := true
	func is_code_preparation_generation_current(value: int) -> bool:
		return generation == value
	func is_code_preparation_loading_phase_current(value: int) -> bool:
		return loading_phase and generation == value
	func _exit_tree() -> void:
		if ContentLayers.has_method("cancel_internal_code_owner"):
			ContentLayers.cancel_internal_code_owner(self, generation)

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _start_target(prepared: Dictionary, consumer: Node, generation: int, holder: Dictionary) -> void:
	holder.result = await ContentLayers.request_internal_prepared_script(prepared, consumer, generation)
	holder.done = true

func _drain(service: Node) -> bool:
	for _frame in range(600):
		if service.pending_count() == 0:
			return true
		await get_tree().process_frame
	return service.pending_count() == 0

func _run() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "Caster API test retains the non-test runtime setting")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(), "formal wrapper supplies isolated APPDATA and run identity")
	check(not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(), "API evidence binds invocation and tested source bytes")
	check(not ResourceLoader.has_cached(TARGET_SCRIPT), "real target Script is cold; fixture stores only its String path")
	var mode := owner_mode
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--code-owner-mode="):
			mode = argument.trim_prefix("--code-owner-mode=")
	check(mode in ["normal", "before_request", "in_flight", "after_get"], "owner mode is one explicit bounded lifecycle")
	var api_ready := ContentLayers.has_method("prepare_internal_code_entry") and ContentLayers.has_method("request_internal_prepared_script") and ContentLayers.has_method("retire_internal_code_result")
	check(api_ready, "formal ContentLayers owns the registered preparation and Script retrieval APIs")
	if not api_ready:
		_finish()
		return
	var consumer := Consumer.new()
	add_child(consumer)
	var overlay: Control = OverlayScript.new()
	consumer.add_child(overlay)
	var old_stats := PlayerState.computed_stats.duplicate(true)
	var unknown: Dictionary = await ContentLayers.prepare_internal_code_entry("framework.code.unknown", overlay, consumer, consumer.generation)
	check(not unknown.success, "an unregistered internal entry cannot nominate arbitrary resources")
	var uncovered: Dictionary = await ContentLayers.prepare_internal_code_entry(ENTRY_ID, overlay, consumer, consumer.generation)
	check(not uncovered.success and not ResourceLoader.has_cached(TARGET_SCRIPT), "pre-cover preparation refuses before touching the target Script")
	overlay.begin_loading("caster.api." + mode)
	await overlay.transition_covered
	check(not overlay.code_preparation_cover_receipt().is_empty(), "real covered presentation admits the Loading preparation phase")
	var began := Time.get_ticks_usec()
	var prepared: Dictionary = await ContentLayers.prepare_internal_code_entry(ENTRY_ID, overlay, consumer, consumer.generation)
	var preparation_usec := Time.get_ticks_usec() - began
	check(prepared.success, "same production service prepares all actual registered Caster inputs")
	check(Budget.snapshot().open_scopes == 0, "input completion crosses no open Budget scope")
	var service: Node = ContentLayers._feature_resources()
	if not prepared.success:
		consumer.queue_free()
		await get_tree().process_frame
		check(await _drain(service), "failed input preparation retires its held references")
		_finish()
		return
	check(not ResourceLoader.has_cached(TARGET_SCRIPT), "successful input preparation keeps the real target Script cold")
	var bundle := Data.read_bundle()
	var authored_plan: Dictionary = bundle.entries[ENTRY_ID]
	check(authored_plan.nodes.size() == 18 and authored_plan.edges.size() == 57 and authored_plan.prepared_inputs.size() == 2, "real Caster proof includes Script/class/residency edges rather than a two-path whitelist")
	var false_owner: Dictionary = Guard.begin_verification(authored_plan, ENTRY_ID, true, consumer)
	check(not false_owner.success, "a caller boolean cannot grant publication authority")
	var malformed: Dictionary = authored_plan.duplicate(true)
	malformed.nodes[TARGET_SCRIPT] = 7
	var malformed_result: Dictionary = Guard.begin_verification(malformed, ENTRY_ID, ContentLayers, consumer)
	check(not malformed_result.success and malformed_result.errors == ["code_preparation_target_not_supported_script"], "malformed target shape is a business refusal before Dictionary access")
	var lease: RefCounted = prepared.lease
	var shader_identity: Dictionary = {}
	for path: String in authored_plan.prepared_inputs:
		var shader: Shader = lease.resource_at(path) as Shader
		check(shader != null and shader.resource_path == path and shader.code == FileAccess.get_file_as_string(path) and FileAccess.get_sha256(path) == authored_plan.nodes[path].sha256, "prepared Shader has exact source bytes and usable code: " + path)
		shader_identity[path] = shader.get_instance_id() if shader != null else 0
	var before: Dictionary = service.metrics()
	var holder := {"done": false, "result": {}}
	var generation: int = consumer.generation
	if mode == "before_request":
		consumer.loading_phase = false
		consumer.queue_free()
		var refused: Dictionary = await ContentLayers.request_internal_prepared_script(prepared, consumer, generation)
		check(not refused.success, "owner exit before request refuses code admission")
		check(service.metrics().request_calls == before.request_calls and service.metrics().get_calls == before.get_calls, "pre-request refusal owns no native retrieval token")
	else:
		_start_target(prepared, consumer, generation, holder)
		if mode == "in_flight":
			for _frame in range(600):
				if service.metrics().request_calls > before.request_calls or holder.done:
					break
				await get_tree().process_frame
			check(service.metrics().request_calls == before.request_calls + 1 and service.metrics().get_calls == before.get_calls, "in-flight exit occurs after an accepted real request and before its get")
			consumer.loading_phase = false
			consumer.queue_free()
		for _frame in range(600):
			if holder.done:
				break
			await get_tree().process_frame
		check(holder.done, "one physical Script job returns a terminal owner result")
		var result: Dictionary = holder.result
		if mode == "in_flight":
			check(not result.get("success", false), "exited owner cannot receive a successful Script handoff")
		else:
			check(result.get("success", false), "real prepared Caster Script request completes through the original owner")
			var script: Script = result.get("resource") as Script
			check(script != null and script.resource_path == TARGET_SCRIPT and FileAccess.get_sha256(TARGET_SCRIPT) == authored_plan.nodes[TARGET_SCRIPT].sha256, "returned real Script keeps its authoring identity and bytes")
			if script != null:
				var shader_constants: Dictionary = script.get_script_constant_map()
				var found := 0
				for value: Variant in shader_constants.values():
					if value is Shader and shader_identity.has(value.resource_path):
						found += 1
						check(value.get_instance_id() == shader_identity[value.resource_path], "Script preload reuses the original held Shader instance: " + value.resource_path)
				check(found == authored_plan.prepared_inputs.size(), "actual Shader constants cover every source-derived prepared input")
			var sprite: Sprite2D = script.new() as Sprite2D if script != null else null
			check(sprite != null, "actual first-use construction produces a real Sprite2D")
			if sprite != null:
				consumer.add_child(sprite)
				sprite.queue_free()
				await get_tree().process_frame
				sprite = null
			script = null
			if mode == "after_get":
				consumer.loading_phase = false
				consumer.queue_free()
				check(service.metrics().get_calls == before.get_calls + 1, "after-get exit follows the one actual native retrieval")
		ContentLayers.retire_internal_code_result(result)
		holder.result = {}
	lease = null
	ContentLayers.retire_internal_code_result(prepared)
	if is_instance_valid(consumer) and not consumer.is_queued_for_deletion():
		consumer.queue_free()
	await get_tree().process_frame
	check(await _drain(service), "all jobs and original retirement references drain within the bounded owner lifecycle")
	var after: Dictionary = service.metrics()
	check(after.request_calls - before.request_calls == (0 if mode == "before_request" else 1) and after.get_calls - before.get_calls == (0 if mode == "before_request" else 1), "accepted request has exactly one get; no INVALID phantom get")
	check(ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "the native Script retrieval right has retired")
	var reentry_consumer := Consumer.new()
	reentry_consumer.generation = generation + 1
	add_child(reentry_consumer)
	var reentry_overlay: Control = OverlayScript.new()
	reentry_consumer.add_child(reentry_overlay)
	reentry_overlay.begin_loading("caster.api.reentry")
	await reentry_overlay.transition_covered
	var reentry_before: Dictionary = service.metrics()
	var reentry: Dictionary = await ContentLayers.prepare_internal_code_entry(ENTRY_ID, reentry_overlay, reentry_consumer, reentry_consumer.generation)
	check(reentry.success, "a new live covered consumer generation can lawfully prepare the same registered entry")
	var reentry_result: Dictionary = await ContentLayers.request_internal_prepared_script(reentry, reentry_consumer, reentry_consumer.generation)
	check(reentry_result.get("success", false) and reentry_result.get("resource") is Script, "same-owner legal reentry yields the real Script through cache or one fresh physical job")
	ContentLayers.retire_internal_code_result(reentry_result)
	ContentLayers.retire_internal_code_result(reentry)
	reentry_consumer.queue_free()
	await get_tree().process_frame
	check(await _drain(service), "legal reentry also drains through the original retirement queue")
	var reentry_after: Dictionary = service.metrics()
	check(reentry_after.request_calls - reentry_before.request_calls == reentry_after.get_calls - reentry_before.get_calls and reentry_after.request_calls - reentry_before.request_calls in [0, 1], "legal reentry owns zero cache retrieval rights or exactly one new request/get pair")
	check(ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "legal reentry leaves no native retrieval right")
	check(PlayerState.computed_stats == old_stats, "preparation retains the existing gameplay attribute authority")
	check(Budget.snapshot().open_scopes == 0, "owner exit and resource retirement leave no open Budget scope")
	print("CODE_PREPARATION_CASTER_API_OBSERVATION ", JSON.stringify({"mode": mode, "preparation_usec": preparation_usec, "before": before, "after": after, "reentry_before": reentry_before, "reentry_after": reentry_after, "phase_quanta": service.code_phase_metrics(), "headless_gpu_proof": "NOT_RUN", "root_preparation": "NOT_RUN", "android_exported_support": "MISSING"}))
	_finish()

func _finish() -> void:
	print("CODE_PREPARATION_CASTER_API_CHECKS: ", checks, " failures=", failures.size())
	var valid := proof.write_receipt(receipt_scene_id, checks, failures.size())
	print("CODE_PREPARATION_CASTER_API_%s checks=%d failures=%s" % ["PASS" if valid and failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if valid and failures.is_empty() else 1)
