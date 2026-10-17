extends RefCounted

## Borrow the actual S models and immutable navigation release. Output is
## numeric preparation data; no gameplay authority or Object enters W.
const WorkingGraph := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _geometry: RefCounted
var _native: RefCounted
var _static_publication: Dictionary = {}
var _configured := false
var _pipeline: WeakRef

func owner_thread_id() -> int: return _owner

func configure_owner(world: RefCounted, actual_static_geometry: RefCounted, native: RefCounted) -> bool:
	if _configured or _owner == OS.get_main_thread_id() or world.owner_thread_id() != _owner or actual_static_geometry.owner_thread_id() != _owner or native.owner_thread_id() != _owner: return false
	# Root provides this from the same actual native/static world publication.
	# It must include every original WORLD/safe-zone/terrain blocker, not a
	# synthetic open map or guessed scalar return.
	for method: String in ["freeze_original_world_predicates", "current_original_static_revision", "validate_actual_loading_navigation_admission", "report_original_planning_receipt"]:
		if not actual_static_geometry.has_method(method): return false
	_world = weakref(world)
	_geometry = actual_static_geometry
	_native = native
	if not _native.has_method("publish_static_navigation"): return false
	_configured = true
	return true

func publish_actual_loading_navigation(contexts_by_radius: Dictionary, actual_loading_admission: Dictionary) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner or not _static_publication.is_empty(): return false
	var world: RefCounted = _world.get_ref()
	var map_id: int = int(world.current_world_identity().runtime_map_id)
	var values: Dictionary = {}
	for radius: float in contexts_by_radius:
		var value: Dictionary = _native_values(contexts_by_radius[radius], radius)
		if value.get("ok") != true: return false
		values[Graph.key_for_radius(radius)] = value.values
	var predicates: Dictionary = _geometry.freeze_original_world_predicates(map_id)
	if predicates.get("ok") != true: return false
	if not _geometry.validate_actual_loading_navigation_admission(actual_loading_admission, predicates, world.current_world_identity()): return false
	# The Native admission validates the real Loading source barrier before
	# copying the original release once. LIVE never falls back to full packing.
	var published: Dictionary = _native.publish_static_navigation(values, predicates, world.current_world_identity(), _geometry.current_original_static_revision(map_id), actual_loading_admission)
	if published.get("ok") != true or not published.get("descriptor") is Dictionary: return false
	_static_publication = published.descriptor
	return true

func _native_values(context: Dictionary, radius: float) -> Dictionary:
	if not context.get("valid") is bool or not context.valid: return {"ok": false, "reason": "actual_navigation_context_invalid"}
	var result := {"valid": true, "runtime_map_id": context.runtime_map_id, "design_size": context.design_size,
		"contract_id": context.contract_id, "build_sha256": context.build_sha256,
		"coordinate_contract_id": context.coordinate_contract_id}
	if context.has("poly_index"):
		var index: RefCounted = context.poly_index
		if index == null or not index.ready: return {"ok": false, "reason": "actual_polygon_index_unready"}
		var key: String = Graph.key_for_radius(radius)
		var graph: RefCounted = context.get("poly_graphs", {}).get(key)
		if graph == null or not graph.ready or graph.radius_gu != radius: return {"ok": false, "reason": "actual_exact_radius_navigation_missing"}
		result.kind = &"polygon"
		result.index = {"design_size": index.design_size, "parts": index.parts, "boxes": index.boxes,
			"padded_boxes": index._padded_boxes, "first_buckets": index._first_buckets, "buckets": index.buckets}
		result.graph = {"radius_key": graph.radius_key, "radius_gu": graph.radius_gu, "vertices": graph.vertices,
			"faces": graph.faces, "centers": graph.centers, "links": graph.links, "buckets": graph.buckets}
	else:
		for field: String in ["blocked_cells"]:
			if not context.get(field) is Dictionary: return {"ok": false, "reason": "actual_legacy_navigation_field_missing", "field": field}
		result.kind = &"legacy_grid"
		result.blocked_cells = context.blocked_cells
		# Original _cell_blocks_los reads the same blocked_cells, no second mask.
	var restored: Dictionary = WorkingGraph.restore_runtime_roots(result)
	return {"ok": restored.ok, "values": restored.value, "errors": restored.errors}

func capture_original_planning_batch(sequence: int, released_usec: int, period_usec: int) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner: return {"ok": false, "reason": "wrong_source_owner"}
	var world: RefCounted = _world.get_ref()
	var actors: Array[Dictionary] = []
	var map_id: int = int(world.current_world_identity().runtime_map_id)
	var frozen: Dictionary = world.freeze_crowd_geometry(map_id)
	if not frozen.get("peers") is Array: return {"ok": false, "reason": "actual_peer_geometry_missing"}
	var static_revision: int = _geometry.current_original_static_revision(map_id)
	if _static_publication.is_empty() or _static_publication.get("static_revision") != static_revision:
		return {"ok": false, "reason": "actual_loading_static_navigation_publication_missing"}
	var peers: Array[Dictionary] = []
	for peer: Dictionary in frozen.peers:
		var handle: Object = world.registry.resolve_runtime_actor(peer.runtime_id)
		if handle == null: return {"ok": false, "reason": "actual_frozen_peer_identity_missing"}
		var model: Object = handle.model()
		var fact: Dictionary = peer.duplicate(false)
		fact.enemy = handle.kind() == &"enemy"
		fact.damage_eligible = model.can_receive_damage() if model.has_method("can_receive_damage") else false
		fact.world_collision = bool(model.behavior_profile.get("worldCollision", true)) if fact.enemy else false
		fact.stable_combat_order = int(model.spatial_actor_runtime_id) if fact.enemy else handle.stable_combat_order()
		peers.append(fact)
	var source_ticks_ms: int = world.owner_services.Time.get_ticks_msec()
	for handle: Object in world.actors_in_group(&"enemies"):
		if not handle.is_registered() or not handle.is_inside_world() or handle.is_queued_for_retirement(): continue
		var model: RefCounted = handle.model()
		# Same original eligibility gate; this does not advance clocks/cadence,
		# perform retarget, draw RNG, or accept an attack/movement permission.
		if not model._source176_ordinary_melee() or not model._hc_owner_optional_budget_runnable(): continue
		var target: Object = model.target
		var target_handle: Object = world.actor_access.canonical(target)
		if target_handle == null or not target_handle.runtime_object_is_present() or target_handle.is_queued_for_retirement(): continue
		var context: Dictionary = model._terrain_navigation_context
		var radius: float = model.combat_radius_gu
		var key: String = Graph.key_for_radius(radius)
		if not _static_publication.get("radius_keys") is Array or key not in _static_publication.radius_keys or context.build_sha256 != _static_publication.get("build_sha256"):
			return {"ok": false, "reason": "actual_exact_radius_navigation_publication_missing"}
		var position: Vector2 = model.spatial_index_position()
		# Last-known source observation is the soft target input. A new player
		# pose never invalidates the complete batch or forces every-H replanning.
		var anchor: Vector2 = model._hc_known_ground
		if not position.is_finite() or not anchor.is_finite(): continue
		var identity: Dictionary = handle.identity()
		var target_identity: Dictionary = target_handle.identity()
		var stamp: Dictionary = world.read_crowd_geometry_stamp(world.actor_access.view(handle))
		var target_stamp: Dictionary = world.read_crowd_geometry_stamp(world.actor_access.view(target_handle))
		var retain_same_source_goal: bool = model._hc_path_anchor == anchor or model._hc_surround_goal.is_finite()
		var active_failed_edges: Array = []
		for edge: String in model._hc_failed_edges:
			if int(model._hc_failed_edges[edge]) <= source_ticks_ms: continue
			var sides := edge.split(">")
			if sides.size() != 2: return {"ok": false, "reason": "original_failed_edge_key_invalid"}
			var from := sides[0].split(",")
			var to := sides[1].split(",")
			if from.size() != 2 or to.size() != 2: return {"ok": false, "reason": "original_failed_edge_key_invalid"}
			for component: String in from + to:
				if not component.is_valid_int(): return {"ok": false, "reason": "original_failed_edge_key_invalid"}
			active_failed_edges.append([Vector2i(int(from[0]), int(from[1])), Vector2i(int(to[0]), int(to[1]))])
		actors.append({"runtime_id": handle.get_instance_id(), "life": int(identity.life_generation),
			"target_runtime_id": target_handle.get_instance_id(), "target_life": int(target_identity.life_generation),
			"radius_revision": int(stamp.radius_revision), "radius": radius, "margin": float(stamp.margin),
			"position": position, "historical_target": anchor, "target_radius": model._target_combat_radius_gu(target),
			"target_margin": float(target_stamp.margin), "target_radius_revision": int(target_stamp.radius_revision),
			"source_ticks_ms": source_ticks_ms, "side_retry_due": source_ticks_ms >= model._hc_next_side_retry_ms,
			"active_failed_edges": active_failed_edges, "actor_key": current_original_actor_key(handle.get_instance_id()),
			"stable_combat_order": int(model.spatial_actor_runtime_id), "navigation_key": key,
			"source_surround_goal": model._hc_surround_goal if model._hc_surround_goal.is_finite() else null, "source_surround_slot": model._hc_surround_slot,
			"source_flank_waypoint": model._hc_flank_waypoint if model._hc_flank_waypoint.is_finite() and retain_same_source_goal else null,
			"source_flank_anchor": model._hc_flank_anchor if model._hc_flank_anchor.is_finite() else null,
			"source_route": model._hc_route if retain_same_source_goal else PackedVector2Array(), "source_route_index": model._hc_route_index if retain_same_source_goal else 0,
			"source_failed_edges": model._hc_failed_edges, "source_observed": model._hc_observed})
	var batch := {"ok": true, "contract_id": "hardcore.pursuit.planning.snapshot.v1", "sequence": sequence,
		"released_usec": released_usec, "period_usec": period_usec, "world_context": world.current_world_identity(),
		"static_revision": static_revision, "static_navigation": _static_publication,
		"actors": actors, "peers": peers}
	var restored: Dictionary = WorkingGraph.restore_runtime_roots(batch)
	return restored.value if restored.ok else {"ok": false, "reason": "actual_planning_snapshot_nonplain", "errors": restored.errors}

func bind_actual_pipeline(pipeline: RefCounted) -> bool:
	if not _configured or _pipeline != null or pipeline.owner_thread_id() != _owner: return false
	_pipeline = weakref(pipeline)
	return true

func current_original_actor_key(runtime_id: int) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner: return {}
	var world: RefCounted = _world.get_ref()
	var handle: Object = world.registry.resolve_runtime_actor(runtime_id)
	if handle == null or not handle.is_registered() or not handle.is_inside_world() or handle.is_queued_for_retirement(): return {}
	var model: Object = handle.model()
	if not model._source176_ordinary_melee() or not model._hc_owner_optional_budget_runnable(): return {}
	var target: Object = world.actor_access.canonical(model.target)
	if target == null or not target.is_inside_world() or target.is_queued_for_retirement(): return {}
	var own_stamp: Dictionary = world.read_crowd_geometry_stamp(world.actor_access.view(handle))
	var target_stamp: Dictionary = world.read_crowd_geometry_stamp(world.actor_access.view(target))
	# Poses, moving-player observation and whole crowd geometry generation are
	# soft inputs. Hard life/world/shape/target/control qualification stays fresh.
	return {"world_context": world.current_world_identity(), "static_revision": _geometry.current_original_static_revision(model.runtime_map_id),
		"runtime_id": runtime_id, "life": handle.identity().life_generation,
		"target_runtime_id": target.get_instance_id(), "target_life": target.identity().life_generation,
		"radius_revision": own_stamp.radius_revision, "target_radius_revision": target_stamp.radius_revision,
		"zone_generation": int(model.read_meta("zone_generation", -1)),
		"navigation_build_sha256": model._terrain_navigation_context.get("build_sha256"),
		"movement_authority_failed_closed": model._movement_authority_failed_closed,
		"controlled": model.control_time > 0.0 or model.charm_time > 0.0}

func validate_original_planning_adoption(batch: Dictionary, actor: Dictionary, row: Dictionary) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner: return {"ok": false, "reason": "wrong_source_owner"}
	if row.get("runtime_id") != actor.runtime_id or row.get("life") != actor.life: return {"ok": false, "reason": "native_output_identity_mismatch"}
	var current: Dictionary = current_original_actor_key(actor.runtime_id)
	return {"ok": true, "hard_valid": not current.is_empty() and current == actor.actor_key and batch.world_context == current.world_context,
		"actor_key": current}

func install_original_planning_row(actor: Dictionary, row: Dictionary) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner: return {"ok": false, "reason": "wrong_source_owner"}
	var world: RefCounted = _world.get_ref()
	var handle: Object = world.registry.resolve_runtime_actor(actor.runtime_id)
	if handle == null or not row.get("route") is PackedVector2Array: return {"ok": false, "reason": "actual_source_model_or_route_missing"}
	var model: Object = handle.model()
	if not model.has_method("install_original_prepared_pursuit"): return {"ok": false, "reason": "actual_enemy_prepared_install_overlay_missing"}
	return model.install_original_prepared_pursuit(actor, row)

func report_original_planning_receipt(receipt: Dictionary) -> void:
	_geometry.report_original_planning_receipt(receipt)

func original_prepared_neighbor(model: Object, current: Vector2, hit_target: Object) -> Dictionary:
	if _pipeline == null or _pipeline.get_ref() == null: return {"ok": false, "reason": "actual_pipeline_missing"}
	var pipeline: RefCounted = _pipeline.get_ref()
	if not pipeline.has_actual_installed_intent(model.runtime_actor_id()): return {"ok": true, "neighbor": Vector2i.ZERO, "status": "PREPARATION_PENDING"}
	return model.consume_original_prepared_pursuit(current, hit_target, pipeline.actual_installed_row(model.runtime_actor_id()))
