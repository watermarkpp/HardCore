extends RefCounted

const EnvironmentPublication := preload("res://scripts/gameplay/world/world_environment_publication.gd")
const Codec := preload("res://scripts/gameplay/world/world_environment_transport_codec.gd")
const BodyPolicy := preload("res://scripts/actor_body_policy.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
const Art := preload("res://scripts/art_spec.gd")
const WorldClock := preload("res://scripts/world_monster_clock_ledger.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const RuntimeMap := preload("res://scripts/map_editor/map_editor_runtime_map_service.gd")
const CONTRACT_ID := "world.environment.formal_boot.v1"

## MAIN ONLY. Queue capacities are explicit approved host policy inputs; this
## publisher supplies no capacity, physics setting, radius or readiness default.
static func capture(background: Node, requested_map_ids: Array[int], world_identity: Dictionary, world_clock_generation: String, host_policy: Dictionary) -> Dictionary:
	return _capture(background, requested_map_ids, world_identity, world_clock_generation, host_policy, {}, null)

## Original first entry has a real Root with map=-1, while the detached original
## Background still contains its constructor's reference-map defaults. Prepare
## positive formal content without claiming the destination has become active.
## This is called on Main before Host's external physics ownership handoff.
static func capture_before_first_map(root: Node2D, background: Node, tree: SceneTree, requested_map_ids: Array[int], world_identity: Dictionary, world_clock_generation: String, host_policy: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or tree == null or tree != Engine.get_main_loop():
		return {"ok":false,"errors":["actual_Main_pre_map_capture_required"]}
	if not is_instance_valid(root) or root.get_script() != preload("res://scripts/game_root.gd") or root.is_inside_tree() or root.is_queued_for_deletion() or root.get("current_map_id") != -1 or root.get("_zone_generation") != 0:
		return {"ok":false,"errors":["original_detached_pre_map_Root_required"]}
	if not is_instance_valid(background) or background.get_script() != preload("res://scripts/world_background.gd") or background.is_inside_tree() or background.is_queued_for_deletion() or background.get_child_count() != 0:
		return {"ok":false,"errors":["original_detached_Background_required"]}
	if background.get("_skip_initial_legacy_build_once") != true or not background.get("zone_data").is_empty() or background.get("_source_collision_shape_count") != 0 or background.get("_editor_runtime_size") != Vector2i.ZERO or background.get("_source_mask_image") != null:
		return {"ok":false,"errors":["original_unbuilt_Background_required"]}
	if world_identity.get("world_runtime_id") != root.get_instance_id() or world_identity.get("runtime_map_id") != -1 or world_identity.get("world_epoch") != 0 or requested_map_ids.is_empty():
		return {"ok":false,"errors":["actual_initial_Root_context_required"]}
	var source: Script = background.get_script()
	var context: Dictionary = {"contract_id":"world.environment.pre_map_context.v1", "world_identity":world_identity,
		"background_reference_map_id":background._active_map_id(), "source_path":source.resource_path,
		"source_sha256":source.get_source_code().sha256_text()}
	return _capture(background, requested_map_ids, world_identity, world_clock_generation, host_policy, context, tree)

static func _capture(background: Node, requested_map_ids: Array[int], world_identity: Dictionary, world_clock_generation: String, host_policy: Dictionary, pre_map_context: Dictionary, actual_tree: SceneTree) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not ClassDB.class_exists("HardCoreContentValueGraph"):
		return {"ok": false, "errors": ["main_native_boot_boundary_required"]}
	if world_identity.size() != 5 or world_identity.get("contract_id") != "hardcore.execution.world_context.v1" or not world_identity.get("world_runtime_id") is int or world_identity.world_runtime_id <= 0 or not world_identity.get("world_epoch") is int or world_identity.world_epoch < 0 or not world_identity.get("runtime_map_id") is int or (world_identity.runtime_map_id < 0 and (pre_map_context.is_empty() or world_identity.runtime_map_id != -1 or world_identity.world_epoch != 0)) or not world_identity.get("profile_id") is String or world_identity.profile_id.is_empty() or not WorldClock.valid_generation(world_clock_generation):
		return {"ok": false, "errors": ["accepted_world_identity_required"]}
	var config: Dictionary = {}
	for field: String in ["max_epochs_per_turn", "timer_capacity", "input_capacity", "event_capacity"]:
		if not host_policy.get(field) is int or host_policy[field] <= 0:
			return {"ok": false, "errors": ["explicit_host_policy_required:" + field]}
		config[field] = host_policy[field]
	config["physics_hz"] = Engine.physics_ticks_per_second
	var environment: Dictionary = EnvironmentPublication.capture(background, requested_map_ids)
	if not environment.ok:
		return environment
	if pre_map_context.is_empty() and background._active_map_id() != world_identity.runtime_map_id:
		return {"ok": false, "errors": ["background_world_map_mismatch"]}
	var publication: Dictionary = environment.publication
	var content_reference_map: int = background._active_map_id() if not pre_map_context.is_empty() else world_identity.runtime_map_id
	var active: Dictionary = publication.runtime_maps[content_reference_map]
	if not active.formal_playable or active.runtime.is_empty():
		return {"ok": false, "errors": ["formal_runtime_boot_required"]}
	var documents: Dictionary = {}
	for id: int in publication.map_load_order:
		var entry: Dictionary = publication.runtime_maps[id]
		if not entry.has_runtime_map:
			continue
		var path: String = entry.runtime_path
		if path.is_empty() or not FileAccess.file_exists(path):
			return {"ok": false, "errors": ["runtime_source_document_missing:" + str(id)]}
		var bytes := FileAccess.get_file_as_bytes(path)
		var raw := bytes.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(raw)
		if not parsed is Dictionary or bytes.is_empty() or not Bridge.has_runtime_map(id):
			return {"ok": false, "errors": ["runtime_source_document_invalid:" + str(id)]}
		# Check the cached Bridge value against the same original formal loader and
		# its single legacy-unit import boundary; never reset a stale cache here.
		var checked: Dictionary = RuntimeMap.load_runtime(path)
		if not checked.get("ok", false) or not checked.get("runtime") is Dictionary:
			return {"ok": false, "errors": checked.get("errors", ["runtime_source_revalidation_failed"])}
		checked.runtime["runtime_map_id"] = id
		if checked.runtime != entry.runtime:
			return {"ok": false, "errors": ["Bridge_runtime_source_snapshot_mismatch:" + str(id)]}
		documents[id] = {"path": path, "raw_utf8": bytes, "raw_json": raw, "raw_file_sha256": FileAccess.get_sha256(path),
			"build_sha256": str(entry.runtime.get("build_sha256", "")), "original_json": parsed}
	var encoded: Dictionary = Codec.encode(publication)
	if not encoded.ok:
		return encoded
	var templates: Dictionary = _capture_body_templates()
	if not templates.ok:
		return templates
	var default_area := {
		"gravity": ProjectSettings.get_setting("physics/2d/default_gravity"),
		"gravity_vector": ProjectSettings.get_setting("physics/2d/default_gravity_vector"),
		"linear_damp": ProjectSettings.get_setting("physics/2d/default_linear_damp"),
		"angular_damp": ProjectSettings.get_setting("physics/2d/default_angular_damp")}
	var settings := {
		"physics/2d/default_gravity": default_area.gravity,
		"physics/2d/default_gravity_vector": default_area.gravity_vector,
		"physics/2d/default_linear_damp": default_area.linear_damp,
		"physics/2d/default_angular_damp": default_area.angular_damp,
		"physics/common/physics_ticks_per_second": ProjectSettings.get_setting("physics/common/physics_ticks_per_second"),
		"physics/common/max_physics_steps_per_frame": ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame")}
	var tree: SceneTree = actual_tree if not pre_map_context.is_empty() else background.get_tree()
	if tree == null:
		return {"ok": false, "errors": ["live_Main_scene_clock_required"]}
	var boot := {"contract_id": CONTRACT_ID, "world_identity": world_identity,
		"world_clock_generation": world_clock_generation, "runtime_map_id": world_identity.runtime_map_id,
		"environment_wire": encoded.wire, "runtime_source_documents": documents,
		"default_area": default_area, "project_settings": settings, "body_templates": templates.value,
		"engine_clock": {"physics_ticks_per_second": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale,
			"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame, "physics_jitter_fix": Engine.physics_jitter_fix,
			"process_frames": Engine.get_process_frames(), "physics_frames": Engine.get_physics_frames(),
			"wall_msec": Time.get_ticks_msec(), "wall_usec": Time.get_ticks_usec(), "paused": tree.paused},
		"background_clock_eligibility": {"can_process": background.can_process(), "process_processing": background.is_processing(),
			"physics_processing": background.is_physics_processing(), "inside_world": background.is_inside_tree(),
			"queued_for_retirement": background.is_queued_for_deletion(), "process_mode": background.process_mode},
		"host_config": config}
	if not pre_map_context.is_empty():
		var initial: Dictionary = pre_map_context.duplicate(true)
		initial["prepared_map_ids"] = publication.map_load_order
		boot["pre_map_context"] = initial
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph") as RefCounted
	var captured: Dictionary = native.call("capture", boot, true, false)
	return {"ok": bool(captured.get("success", false)), "errors": captured.get("errors", []),
		"boot": captured.get("value") if captured.get("success", false) else {}}

static func _capture_body_templates() -> Dictionary:
	# These three assignments are the exact _ready contract in player.gd,
	# enemy.gd and summon_actor.gd; remaining settings are actual engine values.
	var prototype := CharacterBody2D.new()
	prototype.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	prototype.safe_margin = 0.35
	prototype.max_slides = 6
	var motion := {"motion_mode": prototype.motion_mode, "safe_margin": prototype.safe_margin,
		"max_slides": prototype.max_slides, "wall_min_slide_angle": prototype.wall_min_slide_angle,
		"collision_priority": prototype.collision_priority}
	prototype.free()
	var policy_path: String = BodyPolicy.BODY_POLICY_PATH
	var policy := BodyPolicy._load_policy()
	if policy.is_empty() or not FileAccess.file_exists(policy_path) or BodyPolicy.player_screen_radius_px() != Art.PLAYER_COLLISION_RADIUS_PX:
		return {"ok": false, "errors": ["source_body_policy_not_resolved"]}
	var points: Dictionary = {}
	for tier: StringName in [BodyPolicy.TIER_SMALL, BodyPolicy.TIER_LARGE]:
		var radius := BodyPolicy.tier_screen_radius_px(tier)
		if not is_finite(radius) or radius <= 0.0:
			return {"ok": false, "errors": ["source_body_tier_invalid:" + String(tier)]}
		points[String(tier)] = {"screen_radius_px": radius, "footprint_points": Spatial.actor_footprint_polygon_px(radius)}
	points["player"] = {"screen_radius_px": Art.PLAYER_COLLISION_RADIUS_PX,
		"footprint_points": Spatial.actor_footprint_polygon_px(Art.PLAYER_COLLISION_RADIUS_PX)}
	var bytes := FileAccess.get_file_as_bytes(policy_path)
	return {"ok": true, "value": {"motion": motion, "footprints": points,
		"filters": {"player": {"collision_layer": Spatial.PLAYER_LAYER, "collision_mask": Spatial.PLAYER_MASK},
			"enemy_ground": {"collision_layer": Spatial.ENEMY_LAYER, "collision_mask": Spatial.ENEMY_MASK},
			"enemy_flying": {"collision_layer": 0, "collision_mask": Spatial.WORLD_MASK},
			"summon": {"collision_layer": Spatial.PLAYER_LAYER, "collision_mask": Spatial.WORLD_LAYER | Spatial.ENEMY_LAYER}},
		"policy": policy, "policy_path": policy_path, "policy_raw_utf8": bytes,
		"policy_raw_file_sha256": FileAccess.get_sha256(policy_path), "policy_normalized_sha256": BodyPolicy._policy_sha256_lower()}}
