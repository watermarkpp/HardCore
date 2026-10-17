extends RefCounted

## Physical Main work only. Source supplies its actual slots/Player/map/loot
## values. One accepted coroutine owns the original Main claim dictionary,
## cache pins and real render sequence leases until their actual completion.
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const WarmAnimationPlayer := preload("res://scripts/caster_skill_animation_player.gd")
const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const Contract := preload("res://scripts/gameplay/world/world_source_application_contract.gd")
var _views: WeakRef
var _root: Node
var _job: Dictionary = {}
var _visual: Node2D
var _workset_budget_usec := 0
var _render_budget_usec := 0

func configure_main(views: RefCounted) -> bool:
	var view_source: Script = views.get_script() if views != null else null
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _views != null or view_source == null or view_source.resource_path != "res://scripts/gameplay/world/world_main_views.gd": return false
	var root: Node = views.get("_root")
	var root_source: Script = root.get_script() if is_instance_valid(root) else null
	if root_source == null or root_source.resource_path != "res://scripts/game_root.gd" or not root.is_inside_tree() or not root.has_method("_prewarm_texture_paths_until"): return false
	var constants: Dictionary = root_source.get_script_constant_map()
	if not constants.get("LOADING_PREWARM_BUDGET_USEC") is int or not constants.get("LOADING_RENDER_WARM_BUDGET_USEC") is int or not constants.get("FRAME_TEXTURE_WARM_MAX_IN_FLIGHT") is int: return false
	if constants.LOADING_PREWARM_BUDGET_USEC <= 0 or constants.LOADING_RENDER_WARM_BUDGET_USEC <= 0 or constants.FRAME_TEXTURE_WARM_MAX_IN_FLIGHT != 4: return false
	_workset_budget_usec = constants.LOADING_PREWARM_BUDGET_USEC
	_render_budget_usec = constants.LOADING_RENDER_WARM_BUDGET_USEC
	_views = weakref(views); _root = root
	return true

func _fail(error: String) -> Dictionary: return {"success":false,"status":"INVALID","error":error,"completed":false}
func _main() -> bool: return OS.get_thread_caller_id() == OS.get_main_thread_id() and _views != null and _views.get_ref() != null and is_instance_valid(_root)
func _identity(request: Dictionary) -> bool:
	if not _main() or not Contract.accepts_map_warm_request(request): return false
	var views: RefCounted = _views.get_ref()
	var header: Dictionary = views.get("_header_identity")
	if request.world_context != views.get("_world") or request.source_root_id != header.get("source_root_id") or request.owner_session_id != header.get("owner_session_id"): return false
	var producer: RefCounted = views.get("_map_producer")
	if producer == null: return false
	var scope: Dictionary = producer.get("_scope")
	if scope.get("transition_id") != request.transition_id or scope.get("coordinator_generation") != request.coordinator_generation or scope.get("map_id") != request.map_id: return false
	if request.operation != "loot_icons":
		var arrival: Dictionary = views.get("_last_map_arrival")
		if arrival.get("after_world") != request.world_context or arrival.get("loading_scope") != scope or not views.get("_map_host").verify_committed_original_map_arrival(arrival): return false
	return true

func start_original_map_warm(request: Dictionary) -> Dictionary:
	if not _identity(request): return _fail("actual_Source_map_warm_identity_required")
	if not _job.is_empty() and _job.request == request: return _observe()
	if has_pending_original_map_warm(): return {"success":false,"status":"BUSY","completed":false}
	if request.operation == "workset" and not _root.get("_loading_texture_threaded").is_empty(): return _fail("original_loading_claims_must_be_owned_until_drain")
	var captured: Dictionary = Graph.copy_and_seal(request)
	if not captured.ok: return _fail("map_warm_request_must_be_plain")
	_job = {"request":captured.value,"completed":false,"started_usec":Time.get_ticks_usec(),"result":{}}
	# This is the real Main coroutine, never a coroutine serialized to Source.
	# It waits only for Main process_frame/frame_post_draw, never for Source.
	Callable(self,"_run_original_map_warm").call()
	return _observe()

func poll_original_map_warm(request: Dictionary) -> Dictionary:
	if not _main() or _job.is_empty() or _job.request != request: return _fail("exact_accepted_map_warm_job_required")
	return _observe()

func _observe() -> Dictionary:
	if _job.is_empty(): return _fail("actual_map_warm_job_missing")
	return {"success":true,"status":"READY" if _job.completed else "PENDING","completed":_job.completed,
		"request":_job.request,"result":_job.result.duplicate(true),"actual_Main_capture":true,
		"actual_Main_process_frame":Engine.get_process_frames(),"started_usec":_job.started_usec,
		"completed_usec":_job.get("completed_usec",0)}

func _run_original_map_warm() -> void:
	var request: Dictionary = _job.request
	var result: Dictionary
	match request.operation:
		"loot_icons":
			var names: Array[String] = []; names.assign(request.item_names)
			var submitted: int = LootPickupScript.prewarm_item_names(names)
			# The original loot helper starts the existing UI item cache requests.
			# It never waited for icon residency; distinguish that fact explicitly.
			result = {"success":true,"stage":"ORIGINAL_LOOT_ICON_REQUESTS_SUBMITTED","submitted_count":submitted,"item_names":names,"icon_residency_status":"NOT_RUN"}
		"workset": result = await _prewarm_original_workset(request)
		"render": result = await _warm_original_render(request)
	var captured: Dictionary = Graph.copy_and_seal(result)
	if not captured.ok:
		_job.result = {"success":false,"status":"INVALID","error":"actual_map_warm_result_not_plain"}
	else: _job.result = captured.value
	_job.completed_usec = Time.get_ticks_usec()
	_job.completed = true

func _prewarm_original_workset(request: Dictionary) -> Dictionary:
	Registry.set_loading_window_active(true)
	Registry.unpin_all_frames()
	var workset: Array[String] = []; workset.assign(request.workset)
	if workset.is_empty():
		return {"success":true,"deadline_exceeded":false,"tail_after_deadline_ms":0.0,"loaded":0,"failed":0,"not_admitted":0,"incomplete_skills":[]}
	var started_usec := Time.get_ticks_usec()
	var deadline_usec := started_usec + _workset_budget_usec
	var direction: int = Registry.direction_index(request.facing)
	var paths: Array[String] = []
	for skill: String in workset: paths.append_array(Registry.animation_sequence_paths(skill,direction))
	# Execute the unchanged original request/get/drain loop against the SAME
	# Root dictionary already observed by the actual Main warm IO owner.
	var pumped: Dictionary = await _root.call(&"_prewarm_texture_paths_until",paths,deadline_usec)
	var optional_skipped := false
	if Time.get_ticks_usec() < deadline_usec:
		for audio: String in ["sword","wood","fist"]: PresentationAssets.audio(audio)
		for action: String in ["attack","hit","cast","death"]: PresentationAssets.player_texture(action)
	else: optional_skipped = true
	var incomplete: Array[String] = []
	for skill: String in workset:
		if not Registry.sequence_resident(Registry.animation_sequence_paths(skill,direction)): incomplete.append(skill)
	var pins: Dictionary = Registry.pin_skill_workset(workset,direction)
	var elapsed: int = Time.get_ticks_usec() - started_usec
	print("[LOADING-WORKSET] skills=%d paths=%d loaded=%d failed=%d not_admitted=%d prewarm_ms=%d deadline_exceeded=%s tail_after_deadline_ms=%.1f optional_skipped=%s accepted=%s rejected=%s pinned_paths=%d pinned_bytes=%d incomplete=%s" % [workset.size(),paths.size(),int(pumped.get("loaded",0)),int(pumped.get("failed",0)),int(pumped.get("not_admitted",0)),elapsed/1000,str(pumped.get("deadline_exceeded",false)),float(pumped.get("tail_after_deadline_ms",0.0)),str(optional_skipped),str(pins.get("accepted_skills",[])),str(pins.get("rejected_skills",[])),int(pins.get("pinned_paths",-1)),int(pins.get("pinned_bytes",-1)),str(incomplete)])
	return {"success":true,"deadline_exceeded":bool(pumped.get("deadline_exceeded",false)),"tail_after_deadline_ms":float(pumped.get("tail_after_deadline_ms",0.0)),"loaded":int(pumped.get("loaded",0)),"failed":int(pumped.get("failed",0)),"not_admitted":int(pumped.get("not_admitted",0)),"incomplete_skills":incomplete,"actual_pin_result":pins,"actual_facing_direction_index":direction,"actual_workset":workset,"original_deadline_usec":deadline_usec,"actual_pump_result":pumped}

func _covered() -> bool:
	if not _main(): return false
	var views: RefCounted = _views.get_ref()
	var loading: RefCounted = views.get("_actual_loading")
	var scope: Dictionary = loading.actual_original_loading_scope(views.get("_world"))
	if loading.verify_actual_original_loading_scope(scope).get("success") == true: return true
	var hud: Node = views.get("_views").get("hud")
	return is_instance_valid(hud) and hud.is_inside_tree() and preload("res://scripts/gameplay/source/main_boot_launch_loading.gd").capture_original_presented_cover(hud.get("loading_transition_overlay")).get("success") == true

func _warm_original_render(request: Dictionary) -> Dictionary:
	var result := {"success":true,"skills_considered":0,"skills_warmed":0,"frames_drawn":0,"budget_exhausted":false,"elapsed_ms":0.0,"lease_refcount_before":0,"lease_refcount_after":0,"gpu_status":"NOT_RUN"}
	var before: int = int(Registry.frame_texture_cache_diagnostics().get("leased_sequence_refcount_total",0))
	result.lease_refcount_before = before; result.lease_refcount_after = before
	if DisplayServer.get_name() == "headless": return result
	var started_usec := Time.get_ticks_usec()
	var deadline_usec := started_usec + _render_budget_usec
	var position: Vector2 = request.player_position_px
	var camera: Camera2D = _views.get_ref().get("_views").get("camera")
	if is_instance_valid(camera): position = camera.get_screen_center_position()
	var facing := Vector2.DOWN
	var normalized: Vector2 = request.facing.normalized()
	if normalized.length_squared() > 0.0: facing = normalized
	var direction: int = Registry.direction_index(facing)
	for skill: String in request.workset:
		result.skills_considered += 1
		if not Registry.is_runtime_ready(skill): continue
		if not Registry.sequence_resident(Registry.animation_sequence_paths(skill,direction)): continue
		if not _covered(): result.success = false; result.error = "actual_Loading_cover_lost_during_render_warm"; break
		var visual := WarmAnimationPlayer.new()
		if not visual.configure(skill,facing): visual.free(); continue
		_visual = visual
		result.skills_warmed += 1
		if skill == "wizard.fire_wall": visual.modulate = Color(1.0,1.0,1.0,0.78); visual.scale.y *= 0.6
		visual.global_position = position; visual.visible = true
		_root.add_child(visual)
		for frame_index: int in visual.frame_count():
			visual.set_manual_frame(frame_index)
			await RenderingServer.frame_post_draw
			result.frames_drawn += 1
			if Time.get_ticks_usec() >= deadline_usec: result.budget_exhausted = true; break
			if not _covered(): result.success = false; result.error = "actual_Loading_cover_lost_during_render_warm"; break
		visual.queue_free()
		await RenderingServer.frame_post_draw
		# Keep actual ownership if a platform has not flushed this queue_free
		# at post_draw yet. Only genuine tree exit/free checkpoints discharge it.
		if is_instance_valid(visual) and visual.is_inside_tree(): await visual.tree_exited
		while is_instance_valid(visual): await _root.get_tree().process_frame
		_visual = null
		if not result.success: break
		if Time.get_ticks_usec() >= deadline_usec: result.budget_exhausted = true; break
	var after: int = int(Registry.frame_texture_cache_diagnostics().get("leased_sequence_refcount_total",0))
	result.lease_refcount_after = after
	result.elapsed_ms = float(Time.get_ticks_usec()-started_usec)/1000.0
	result.original_deadline_usec = deadline_usec
	result.gpu_status = ("PASS" if result.frames_drawn > 0 else "NOT_RUN") if result.success else "FAIL"
	if after != before:
		result.success = false; result.gpu_status = "FAIL"; result.error = "actual_render_sequence_lease_mismatch"
		push_error("[RENDER-WARM] sequence lease leak detected: before=%d after=%d" % [before,after])
	print("[FRAME-STALL] baseline: caster=%s presentation=%d monster_overlay=%s" % [Registry.frame_texture_cache_diagnostics(),PresentationAssets.cached_resource_count(),preload("res://scripts/monster_source_frames.gd").diagnostics()])
	return result

func has_pending_original_map_warm() -> bool:
	return not _job.is_empty() and (not _job.completed or is_instance_valid(_visual))
func inspect_actual_original_map_warm() -> Dictionary:
	if not _main(): return {"status":"INVALID"}
	return {"status":"PENDING" if has_pending_original_map_warm() else "READY","actual_Main_capture":true,"actual_Main_process_frame":Engine.get_process_frames(),"request":_job.get("request",{}),"completed":_job.get("completed",false),"loading_texture_threaded":_root.get("_loading_texture_threaded").keys(),"actual_render_visual_id":_visual.get_instance_id() if is_instance_valid(_visual) else 0,"actual_sequence_leases":Registry.frame_texture_cache_diagnostics().get("leased_sequence_refcount_total",0)}
