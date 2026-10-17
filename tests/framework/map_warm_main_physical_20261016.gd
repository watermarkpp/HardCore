extends "res://tests/framework/main_launch_loading_scope_20261015.gd"

## Actual isolated original launch Root/code cover plus the real Main resource
## kernel. This deliberately does not claim Source request capture, Native
## START/POLL admission, first arrival, GPU drawing or whole-world acceptance.
const WarmKernel := preload("res://scripts/gameplay/world/world_original_map_warm_main.gd")
const WarmRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const WarmContract := preload("res://scripts/gameplay/world/world_source_application_contract.gd")
var _warming := false

func _process(delta: float) -> void:
	if not _warming: super._process(delta)

func _inspect_actual_launch(request: Dictionary) -> void:
	super._inspect_actual_launch(request)
	if _failed > 0 or not is_instance_valid(_root): return
	_warming = true
	_exercise_actual_physical_kernel.call_deferred()

func _exercise_actual_physical_kernel() -> void:
	check(DisplayServer.get_name() == "headless","physical resource component explicitly distinguishes headless from actual GPU drawing")
	var identity: Dictionary = Identity.inspect_original_root_identity(_root,_facade)
	check(identity.get("success") == true,"resource kernel retains the actual selected original Root created under the real code cover")
	if identity.get("success") != true: _warming = false; return
	var scope_token := RefCounted.new()
	var input := {"contract_id":"hardcore.source.map_warm_request.v1","world_context":identity.world,
		"source_root_id":scope_token.get_instance_id(),"owner_session_id":1151616,"transition_id":"physical-kernel-component",
		"coordinator_generation":1,"map_id":913203,"operation":"workset","workset":["wizard.fire_wall"],
		"facing":Vector2.UP,"player_position_px":Vector2.ZERO,"item_names":[]}
	check(WarmContract.accepts("map_warm_start",[input]) and WarmContract.accepts("map_warm_state",[input]),"fixed schema accepts only the complete explicit physical-kernel input graph")
	var changed: Dictionary = input.duplicate(true); changed.facing = Vector2(INF,0.0)
	check(not WarmContract.accepts("map_warm_start",[changed]),"nonfinite physical direction cannot enter the fixed warm application contract")
	changed = input.duplicate(true); changed.workset.append("wizard.fire_wall")
	check(not WarmContract.accepts("map_warm_start",[changed]),"duplicate workset identities fail before physical work starts")
	changed = input.duplicate(true); changed["arbitrary_method"] = "load"
	check(not WarmContract.accepts("map_warm_start",[changed]),"extra method capability cannot be smuggled into the fixed warm request")
	var kernel := WarmKernel.new()
	check(kernel.start_original_map_warm(input).get("success") != true and not kernel.has_pending_original_map_warm(),"numeric kernel input cannot manufacture actual Source owner admission or start a formal Main job")
	# Bind only actual physical kernel dependencies for this direct component.
	# The formal public start remains rejected; no Fake Views/Core/Host is used.
	kernel.set("_root",_root)
	var constants: Dictionary = _root.get_script().get_script_constant_map()
	kernel.set("_workset_budget_usec",constants.LOADING_PREWARM_BUDGET_USEC)
	kernel.set("_render_budget_usec",constants.LOADING_RENDER_WARM_BUDGET_USEC)
	var direction: int = WarmRegistry.direction_index(Vector2.UP)
	var paths: Array[String] = WarmRegistry.animation_sequence_paths("wizard.fire_wall",direction)
	check(not paths.is_empty(),"nonempty original fire-wall facing sequence supplies actual texture paths, not an empty warm fixture")
	if not paths.is_empty():
		var actual: Dictionary = await kernel._prewarm_original_workset(input)
		check(actual.get("success") == true and actual.get("actual_workset") == ["wizard.fire_wall"] and actual.get("actual_facing_direction_index") == direction,"actual Main resource kernel consumes exactly the supplied nonempty workset and facing")
		check(actual.get("actual_pump_result") is Dictionary and actual.get("original_deadline_usec",0) > 0,"unchanged original Root request/get/drain loop returns its real absolute deadline diagnostics")
		check(_root.get("_loading_texture_threaded").is_empty(),"the same original accepted-loading dictionary is actually drained before resource completion")
		check(WarmRegistry.sequence_resident(paths) and actual.get("incomplete_skills") == [],"actual original facing textures are resident in the real Registry after the physical warm")
		check(actual.get("actual_pin_result",{}).get("accepted_skills",[]).has("wizard.fire_wall"),"actual workset cache pin accepts the real resident fire-wall sequence")
		if DisplayServer.get_name() == "headless":
			var render: Dictionary = await kernel._warm_original_render(input)
			check(render.get("gpu_status") == "NOT_RUN" and render.get("frames_drawn") == 0,"headless reports GPU NOT_RUN without inventing a rendered frame")
			check(render.get("lease_refcount_before") == render.get("lease_refcount_after"),"headless observation preserves the actual current active-sequence lease count")
	WarmRegistry.unpin_all_frames()
	WarmRegistry.set_loading_window_active(false)
	check(_root.get("_loading_texture_threaded").is_empty(),"physical component leaves no accepted original Root loader claim behind")
	_warming = false
