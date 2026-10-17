extends RefCounted
## Main leaves for the Source application attachment. No second Profile, catalog,
## resource service, journal, map scheduler, or gameplay state is created here.
const Publication := preload("res://scripts/gameplay/profile/profile_publication.gd")
const MAIN_VIEWS_PATH := "res://scripts/gameplay/world/world_main_views.gd"
var _views: WeakRef
var _explicit_panel_call := false # CPS lifetime only; HUD owns all warm progress.
var _map_warm: RefCounted

func configure_main(views: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _views != null or views == null or views.get_script().resource_path != MAIN_VIEWS_PATH: return false
	_views = weakref(views)
	return true

func _fail(error: String, status := "MISSING") -> Dictionary:
	return {"success":false,"status":status,"error":error,"errors":[error]}

func execute_loading(operation: String, arguments: Array) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _views == null or _views.get_ref() == null: return _fail("actual_Main_application_owner_required","INVALID")
	var views: RefCounted = _views.get_ref()
	if not preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts(operation,arguments): return _fail("fixed_application_suboperation_schema","INVALID")
	var feature: RefCounted = views.get("_feature")
	var request: Dictionary = feature.get("_source_request")
	# Only the real admitted Main primitive can invoke this entry. Direct calls
	# from a Node or an arbitrary test do not obtain Loading permission.
	if not feature.is_executing_original_primitive() or request.get("operation") != "feature.object_call" or not request.get("arguments") is Array or request.arguments.size() != 3 or request.arguments[1] != "source_application_call" or request.arguments[2] != [operation,arguments]: return _fail("actual_original_Main_application_call_required","INVALID")
	var site: Dictionary = request.get("site",{})
	if site.get("world_context") != views.get("_world") or str(site.get("domain","")) != "P": return _fail("actual_same_World_Source_P_application_required","INVALID")
	var cold: bool = site.get("bootstrap") == true and site.get("clock_epoch") == 0
	var live: bool = site.get("bootstrap") == false and site.get("clock_epoch") is int and site.clock_epoch > 0
	if not cold and not live: return _fail("actual_admitted_cold_or_positive_application_site_required","INVALID")
	var needs_cover: bool = (cold and operation not in ["map_warm_state","release_map_scope","world_view_exit_state","actor_view_free_state"]) or operation in ["prepare_directory","prewarm_panels","map_scope","map_warm_start"] or (operation == "catalog_icons" and arguments[1] == false)
	if needs_cover:
		var loading: RefCounted = views.get("_actual_loading")
		var scope: Dictionary = loading.actual_original_loading_scope(views.get("_world"))
		var covered: bool = loading.verify_actual_original_loading_scope(scope).get("success") == true
		if not covered:
			# The first actual arrival can still be epoch zero. Its current HUD
			# cover is witnessed separately; the immutable launch proof stays old.
			covered = loading.capture_actual_original_map_cover(views.get("_world")).get("success") == true
		if not covered and live:
			var hud: Node = views.get("_views").get("hud")
			if is_instance_valid(hud) and hud.is_inside_tree():
				var actual: Dictionary = preload("res://scripts/gameplay/source/main_boot_launch_loading.gd").capture_original_presented_cover(hud.get("loading_transition_overlay"))
				covered = actual.get("success") == true
		if not covered: return _fail("actual_Main_Loading_coverage_required","INVALID")
	match operation:
		"world_view_exit_state":
			return views.capture_actual_original_world_view_exit(arguments[0])
		"actor_view_free_state":
			return views.capture_actual_original_actor_view_free(arguments[0])
		"claim_initial_code_retention":
			if not cold or arguments[0] != views.get("_world"): return _fail("actual_initial_code_epoch0_World_required","INVALID")
			return views.get("_actual_loading").claim_actual_original_code_for_prepared_root(views.get("_root"),feature)
		"map_warm_start", "map_warm_state":
			if _map_warm == null:
				if operation == "map_warm_state": return _fail("actual_accepted_map_warm_job_required","INVALID")
				var warm := preload("res://scripts/gameplay/world/world_original_map_warm_main.gd").new()
				if not warm.configure_main(views): return _fail("actual_original_Main_map_warm_owner_required","INVALID")
				_map_warm = warm
			return _map_warm.start_original_map_warm(arguments[0]) if operation == "map_warm_start" else _map_warm.poll_original_map_warm(arguments[0])
		"prepare_directory":
			if arguments.size() != 1 or not arguments[0] is String: return _fail("original_directory_arity","INVALID")
			# This static entry checks the canonical catalog write barrier and
			# calls ContentLayers._read_feature_candidate. It reads the actual
			# registry/module files and preserves original compiler diagnostics.
			return prepare_original_directory(arguments[0])
		"view_ready":
			if arguments.size() != 2 or arguments[0] != views.get("_world") or not arguments[1] is int: return _fail("actual_view_ready_identity","INVALID")
			var registry: RefCounted = views.get("_renderer_registry")
			var player: Node2D = registry.actual_original_player_view(arguments[0])
			if player == null or player != views.get("_player_view") or registry.get("_player_id") != arguments[1] or not player.is_inside_tree() or player.is_queued_for_deletion(): return _fail("actual_original_player_shell_not_bound","PENDING")
			var row: Dictionary = registry.get("_actors").get(arguments[1],{})
			if row.get("assets") == null or not row.assets.is_actual_loading_bound() or not row.assets.bind_actual_original_instance(player): return _fail("actual_original_Player_instance_pins_required","INVALID")
			return {"success":true,"status":"READY","stage":"PREMAP_PLAYER_UI_BOUND","actual_source_ready":true,"world":arguments[0],"runtime_id":arguments[1],"actual_player_view_id":player.get_instance_id(),"actual_Main_capture":true,"actual_Main_process_frame":Engine.get_process_frames()}
		"panel_state":
			if arguments.size() != 1: return _fail("original_panel_state_arity","INVALID")
			return _panel_state(views,arguments[0])
		"prewarm_panels", "budgeted_panels":
			if arguments.size() != 2: return _fail("original_panel_prewarm_arity","INVALID")
			var nodes: Dictionary = _ui_nodes(views,arguments[0],arguments[1])
			if nodes.is_empty(): return _fail("actual_original_HUD_Menu_identity","INVALID")
			if operation == "budgeted_panels":
				nodes.hud.start_budgeted_panel_prewarm(nodes.menu)
			elif not _explicit_panel_call:
				_explicit_panel_call = true
				# Start the original Main coroutine at this callsite; return only
				# scalar progress. A suspended GDScript state never crosses to S.
				Callable(self,"_run_explicit_panels").call(nodes.hud,nodes.menu)
			return _panel_state(views,arguments[0])
		"catalog_icons":
			if arguments.size() != 2 or not arguments[1] is bool: return _fail("original_catalog_prewarm_arity","INVALID")
			var nodes: Dictionary = _ui_nodes(views,arguments[0])
			if nodes.is_empty(): return _fail("actual_original_HUD_identity","INVALID")
			# Existing argument means background_mode, not all_icons. Preserve it.
			# The original method owns one batch/frame, pending claims and deadlines.
			nodes.hud._start_catalog_icon_prewarm(arguments[1])
			return _panel_state(views,arguments[0])
		"map_scope":
			if arguments.size() != 4 or not arguments[0] is Dictionary or not arguments[1] is String or not arguments[2] is int or not arguments[3] is int: return _fail("original_map_scope_arity","INVALID")
			var producer: RefCounted = views.get("_map_producer")
			var executor: RefCounted = views.get("_map_executor")
			if producer == null or executor == null or executor.actual_owner_descriptor() != arguments[0]: return _fail("actual_original_Map_owner_descriptor","INVALID")
			# Producer captures Root's actual ten-field scope, validates provenance
			# and publishes through Native. No local scope/sequence generation.
			return producer.publish_actual_loading_scope(arguments[1],arguments[2],arguments[3])
		"release_map_scope":
			if arguments.size() != 1 or not arguments[0] is Dictionary: return _fail("original_map_release_arity","INVALID")
			var producer: RefCounted = views.get("_map_producer")
			if producer == null: return _fail("actual_original_Map_scope_required","INVALID")
			# Exact old input also resumes a retained partial commit. Native CAS,
			# actual IO and every route must complete before this returns READY.
			return producer.release_actual_loading_scope(arguments[0])
	return _fail("unregistered_original_application_operation","INVALID")

func has_pending_original_map_warm() -> bool:
	return _map_warm != null and _map_warm.has_pending_original_map_warm()
func inspect_actual_original_map_warm() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID"}
	return _map_warm.inspect_actual_original_map_warm() if _map_warm != null else {"status":"READY","completed":true,"accepted_jobs":0,"actual_render_visual_id":0,"loading_texture_threaded":[],"actual_Main_capture":true}

static func prepare_original_directory(path: String) -> Dictionary:
	# Also usable by Root's real post-reader Main compiler barrier. The existing
	# static operation performs I/O; no published boot snapshot is substituted.
	return Publication.prepare_feature_directory(path)

func _ui_nodes(views: RefCounted, hud_id: Variant, menu_id: Variant = null) -> Dictionary:
	if not hud_id is int or menu_id != null and not menu_id is int: return {}
	var nodes: Dictionary = views.get("_views")
	var hud: Node = nodes.get("hud")
	var menu: Node = nodes.get("system_menu")
	if not is_instance_valid(hud) or hud.get_instance_id() != hud_id or not hud.is_inside_tree() or hud.is_queued_for_deletion(): return {}
	if menu_id != null and (not is_instance_valid(menu) or menu.get_instance_id() != menu_id or not menu.is_inside_tree() or menu.is_queued_for_deletion()): return {}
	return {"hud":hud,"menu":menu}

func _run_explicit_panels(hud: Node, menu: Node) -> void:
	await hud.prewarm_all_panels(menu)
	_explicit_panel_call = false

func _panel_state(views: RefCounted, hud_id: Variant) -> Dictionary:
	var nodes: Dictionary = _ui_nodes(views,hud_id)
	if nodes.is_empty(): return _fail("actual_original_HUD_identity","INVALID")
	var hud: Node = nodes.hud
	var completed: bool = hud.all_panels_are_prewarmed()
	return {"success":true,"status":"READY" if completed else "PENDING","completed":completed,"hud_id":hud_id,"catalog_icon_prewarm_complete":hud.get("_catalog_icon_prewarm_complete"),"diagnostic":hud.panel_prewarm_diagnostic(),"actual_Main_capture":true,"actual_Main_process_frame":Engine.get_process_frames()}

static func capture_original_audio_canvas(registry: RefCounted, identity: Dictionary) -> Dictionary:
	# Original enemy._audio_is_listenable reads the actual CanvasItem/Viewport.
	# The existing registry resolves the full world/runtime/life identity first.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or registry == null or not registry.has_method("resolve_original_actor_attachment"): return {}
	var view: Node2D = registry.resolve_original_actor_attachment(identity)
	if view == null: return {}
	var viewport: Viewport = view.get_viewport()
	var result := {"actor_identity":identity.duplicate(true),"world_context":identity.world.duplicate(true),"runtime_id":identity.runtime_id,"actual_Main_capture":true,"actual_Main_process_frame":Engine.get_process_frames(),"visible":view.visible,"visible_in_tree":view.is_visible_in_tree(),"viewport_available":viewport != null}
	if viewport != null:
		result.visible_rect = viewport.get_visible_rect()
		result.global_transform_with_canvas = view.get_global_transform_with_canvas()
	return result
