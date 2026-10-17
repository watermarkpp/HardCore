extends RefCounted
class UiTextureCache extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _core: WeakRef
	func _init(core: RefCounted) -> void: _core = weakref(core)
	func owner_thread_id() -> int: return _owner
	func poll_threaded_paths() -> void:
		assert(OS.get_thread_caller_id() == _owner)
		if not _core.get_ref().emit_original_main_event(&"original_UI_texture_poll",[]): _core.get_ref().fault("actual_original_UI_texture_poll_not_published",{})
## Narrow S services. Dependencies are the actual existing owners, not providers
## that return success on behalf of an absent Main source boundary.
class Home extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _catalog: RefCounted
	var _home: Vector2
	func _init(catalog: RefCounted, home: Vector2) -> void: _catalog = catalog; _home = home
	func owner_thread_id() -> int: return _owner
	func home_screen_position_px() -> Vector2: return _home
	func get_map_profile(id: int) -> Dictionary: return _catalog.get_map_profile(id)
class Pause extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _core: WeakRef
	func _init(core: RefCounted) -> void: _core = weakref(core)
	func owner_thread_id() -> int: return _owner
	func apply_original_pause(paused: bool, frame: Dictionary) -> bool:
		if frame != _core.get_ref().current_clock_frame(): return false
		return _core.get_ref().emit_original_main_event(&"original_tree_pause",[paused])
class Content extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _session: WeakRef
	var _core: WeakRef
	var _feature: RefCounted
	var _consumer: RefCounted
	var _claimed := false
	func configure(core: RefCounted, session: RefCounted, consumer: RefCounted) -> bool:
		if _session != null or core.owner_thread_id() != _owner or session.owner_thread_id() != _owner or consumer == null: return false
		_core = weakref(core); _session = weakref(session); _feature = session.feature_resource_session().coordinator; _consumer = consumer
		return true
	func owner_thread_id() -> int: return _owner
	func prepare_resource_directory(path: String) -> Dictionary:
		# This is ProfileExpansion.reload_feature_catalog_async, which requires
		# no live world readers. The Session owns the original canonical parser.
		return await _session.get_ref().prepare_profile_feature_directory(path)
	func claim_internal_code_world_retention(world: Dictionary) -> Dictionary:
		if _claimed or world != _core.get_ref().current_world_identity(): return {"success":false,"errors":["actual_original_code_claim_identity"]}
		# The Main Root already exists under the original cover. Claim its one
		# actual code-retention edge through the same admitted cold Feature call;
		# do not stage the old scene-change job and instantiate another Root.
		var application: RefCounted = _session.get_ref().original_world_main_dependency(&"WorldUiLoading")
		if application == null or not _session.get_ref().cold_resource_calls_allowed(): return {"success":false,"errors":["actual_epoch0_application_code_claim_required"]}
		var claimed: Dictionary = application._loading_call("claim_initial_code_retention",[world])
		var held: Dictionary = claimed.get("result",{})
		if claimed.get("success") != true: return claimed
		if held.get("success") != true or held.get("lease") == null or held.get("resource") == null: return {"success":false,"errors":["actual_original_code_handoff_not_available"]}
		_claimed = true
		return {"success":true,"actual_original_claim":true,"result":held}
	func retire_internal_code_result(result: Dictionary) -> bool:
		_feature.retire_code_result(result)
		# This proves the original S result clear/lease-release admission only.
		# Whole physical retirement is independently checked by Native/Main close.
		return result.is_empty() and not _session.get_ref().feature_resource_session().primitives.failed()
	func retire_threaded_resource_claims(path: String, count: int) -> bool: return _feature.retire_threaded_resource_claims(path,count)
class BootstrapResources extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _session: WeakRef
	var _primitives: RefCounted
	var _publication: Dictionary
	func _init(session: RefCounted, publication: Dictionary) -> void:
		_session = weakref(session); _primitives = session.feature_resource_session().primitives; _publication = publication
	func owner_thread_id() -> int: return _owner
	func blocking_original_loading_scope_allowed() -> bool:
		return _session.get_ref().cold_resource_calls_allowed() and _session.get_ref().actual_original_loading_scope_is_current(_publication.loading_scope)
	func _allowed() -> bool:
		if blocking_original_loading_scope_allowed(): return true
		_session.get_ref().fault("blocking_world_resource_outside_actual_Loading",{})
		return false
	func display_server_name() -> String: return _publication.display_server_name
	func exists(path: String) -> bool: return _primitives.exists(path,"") if _allowed() else false
	func load_threaded_request(path: String, hint := "", subthreads := false) -> int: return _primitives.load_threaded_request(path,hint,subthreads) if _allowed() else ERR_UNAVAILABLE
	func load_threaded_get_status(path: String, _progress: Array = []) -> int: return _primitives.load_threaded_get_status(path) if _allowed() else -1
	func load_threaded_get(path: String) -> Variant: return _primitives.load_threaded_get(path) if _allowed() else null
	func load(path: String) -> Variant:
		# The original headless serial-prefetch leaf is an actual synchronous
		# ResourceLoader.load in the canonical Main primitive executor.
		return _primitives.load_original_loading_resource(path) if _allowed() else null
	func is_original_resource_reference(value: Variant) -> bool: return _primitives.is_native_type(value,"Resource")
class Lifecycle extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _core: WeakRef
	var _native: Object
	var _proof: Dictionary
	var _frames: RefCounted
	var _publisher: RefCounted
	var _audio: RefCounted
	func _init(core: RefCounted, native: Object, proof: Dictionary, frames: RefCounted, publisher: RefCounted, audio: RefCounted) -> void: _core = weakref(core); _native = native; _proof = proof; _frames=frames; _publisher=publisher; _audio=audio
	func owner_thread_id() -> int: return _owner
	func configure_original_ready_views(world: Dictionary, player_id: int) -> Dictionary:
		# The actual M player shell binding happens after S canonical birth.
		# No queued Node event is a ready receipt.
		return _native.original_world_view_ready_receipt(world,player_id,_proof)
	func publish_original_prefix(prefix: Dictionary) -> Dictionary: return _native.publish_original_world_view_prefix(prefix)
	var _actor_free: Dictionary = {}
	var _renderer_actors: Dictionary = {}
	var _world_exit: Dictionary = {}
	func _retiring_identity(id: int) -> Dictionary:
		var handle: Object = _core.get_ref().actor_handle_for_runtime_id(id)
		if handle == null or handle.kind() not in [&"player",&"enemy"]: return {}
		var model: Object = handle.model()
		if model == null: return {}
		var world: Variant = handle.get("_world")
		var life: Variant = model.current_life()
		if not world is Dictionary or not life is int: return {}
		var actual := {"world":world,"runtime_id":id,"life_generation":life}
		return actual if preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts_retiring_actor(actual) else {}
	func original_renderer_retirement_ids() -> Dictionary:
		if OS.get_thread_caller_id() != _owner or _core.get_ref() == null: return {"success":false,"status":"INVALID"}
		var core: RefCounted = _core.get_ref()
		var ids: Array[int] = []
		for actor_id: int in core.get("_enemy_visual_services"):
			var service_id: int = core.get("_enemy_visual_services")[actor_id]
			var identity: Dictionary = _retiring_identity(actor_id)
			if identity.is_empty(): return {"success":false,"status":"INVALID"}
			_renderer_actors[service_id] = identity.duplicate(true); ids.append(service_id)
		return {"success":true,"status":"READY","ids":ids}
	func request_original_renderer_destruction(service_id: int) -> bool:
		if not _renderer_actors.has(service_id): return false
		return release_presented_actor_at_original_free(int(_renderer_actors[service_id].runtime_id)).get("status") == "READY"
	func original_renderer_destruction_receipt(service_id: int) -> Dictionary:
		if not _renderer_actors.has(service_id): return {"status":"INVALID"}
		var id: int = _renderer_actors[service_id].runtime_id
		if not _actor_free.has(id): return {"status":"PENDING"}
		var receipt: Dictionary = _actor_free[id].receipt
		return {"status":"PENDING"} if receipt.is_empty() else (receipt if receipt.get("service_id") == service_id and receipt.get("actor_identity") == _renderer_actors[service_id] else {"status":"INVALID"})
	func _actual_application_P() -> bool:
		var core: RefCounted = _core.get_ref()
		var frame: Dictionary = core.current_clock_frame()
		var budget: RefCounted = core.original_source_session().original_frame_budget()
		var site: Dictionary = core.current_original_source_site()
		var actual_cold: bool = core.original_source_session().cold_resource_calls_allowed() and site.get("bootstrap") == true and site.get("clock_epoch") == 0 and frame.get("epoch") == 0
		return site.get("domain") == "P" and (frame.get("phase") in ["P_GROUP","P_CLOSE_SERVICE"] or actual_cold) and budget.snapshot().open_scopes == 0 and not budget.resource_external_segment_active()
	func actual_world_view_exit(world: Dictionary) -> Dictionary:
		if not _world_exit.is_empty(): return _world_exit
		if not _actual_application_P(): return {"success":true,"status":"PENDING"}
		if _core.get_ref().original_source_session().get("_phase") == "LIVE" and not _core.get_ref().original_close_renderer_retirement_complete(): return {"success":true,"status":"PENDING","error":"actual_original_renderer_retirement_required"}
		if not _audio.detach_at_original_world_exit(): return {"success":false,"status":"PENDING","error":"actual_audio_reply_pending"}
		var actual: Dictionary = _native.actual_original_world_view_exit_receipt(world)
		if actual.get("success") != true or actual.get("status") != "READY": return actual
		if not _publisher.detach_at_original_world_exit(): return {"success":false,"status":"PENDING","error":"actual_Profile_UI_detach"}
		if not _core.get_ref().original_session_close_resource_owner_held() and not _frames.release_current_world(): return {"success":false,"status":"PENDING","error":"actual_persistent_overlay_claim_drain"}
		_world_exit = actual.duplicate(true)
		return _world_exit
	func remember_presented_actor_at_original_free(id: int) -> bool:
		var identity: Dictionary = _retiring_identity(id)
		if identity.is_empty(): return false
		if _actor_free.has(id): return _actor_free[id].identity == identity
		_actor_free[id] = {"identity":identity,"receipt":{},"failure":{}}
		return true
	func release_presented_actor_at_original_free(id: int) -> Dictionary:
		if not remember_presented_actor_at_original_free(id): return {"status":"INVALID","error":"actual_original_actor_identity"}
		var row: Dictionary = _actor_free[id]
		if not row.failure.is_empty(): return row.failure
		if not row.receipt.is_empty(): return row.receipt
		if not _actual_application_P(): return {"success":true,"status":"PENDING","actor_identity":row.identity}
		var actual: Dictionary = _native.actual_original_actor_view_free_receipt(row.identity)
		if actual.get("status") == "READY": row.receipt = actual.duplicate(true)
		elif actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: row.failure = actual.duplicate(true)
		return actual
	func confirm_presented_actor_at_original_free(id: int) -> bool:
		if not _actor_free.has(id): return false
		var row: Dictionary = _actor_free[id]
		if row.receipt.get("metadata_released") == true: return true
		if not _actual_application_P(): return false
		var actual: Dictionary = _native.actual_original_actor_view_free_receipt(row.identity)
		if actual.get("status") not in ["READY","PENDING","BUSY","BACKPRESSURE"]: row.failure = actual.duplicate(true)
		if actual.get("status") != "READY" or actual.get("metadata_released") != true or actual.get("renderer_registration_retired") != true: return false
		row.receipt = actual.duplicate(true)
		return true
	func consume_presented_actor_at_original_free(id: int) -> bool:
		if not _actor_free.has(id) or _actor_free[id].receipt.get("metadata_released") != true: return false
		var service_id: int = int(_actor_free[id].receipt.get("service_id",0))
		_actor_free.erase(id); _renderer_actors.erase(service_id)
		return true
