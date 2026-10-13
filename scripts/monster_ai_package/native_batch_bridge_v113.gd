extends RefCounted

## Research-only synchronous numeric advice. Default is the original GD path.
## The caller still owns every WORLD/body check, state change and real move.
const Reference := preload("res://scripts/monster_crowd_attack_position_policy.gd")
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const EXTENSION := "res://research/native/crowd_batch_v113/crowd_batch_v113.gdextension"
static var _mode := "disabled"
static var _kernel: Variant = null
static var _directions := PackedVector2Array()
static var _metrics: Dictionary = {}

static func initialize(mode: String) -> bool:
	_mode = mode
	reset_metrics()
	if mode not in ["B1", "N1"]: return true
	var status := GDExtensionManager.load_extension(ProjectSettings.globalize_path(EXTENSION))
	if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]: return false
	if not ClassDB.class_exists("HardCoreV113CrowdBatchKernel"): return false
	_kernel = ClassDB.instantiate("HardCoreV113CrowdBatchKernel")
	if int(_kernel.get_abi_version()) != 11301: return false
	_directions.clear()
	for delta: Vector2i in Neighbor.NEIGHBOR_DELTAS: _directions.append(Vector2(delta))
	return true

static func reset_metrics() -> void:
	_metrics = {"pack_usec": 0, "native_call_usec": 0, "writeback_usec": 0,
		"bridge_total_usec": 0, "input_bytes": 0, "batches": 0, "fallback_count": 0,
		"fallback_reasons": {}}
	if _kernel != null: _kernel.reset_statistics()

static func contact_rays(actor: CharacterBody2D, hit_target: Node2D, origin: Vector2, snapshot: Array) -> PackedVector2Array:
	if _mode != "N1": return PackedVector2Array()
	var started := Time.get_ticks_usec()
	if _kernel == null or not origin.is_finite() or snapshot.size() > 1024:
		return _fallback("invalid_owner_or_size", started)
	var scope := _scope(actor, hit_target)
	var own_radius := float(actor.get("combat_radius_gu"))
	var map_id := int(actor.get("runtime_map_id"))
	var own_margin := Reference.margin_gu(actor)
	var centers := PackedVector2Array()
	var radii := PackedFloat64Array()
	for record: Dictionary in snapshot:
		var other: Variant = record.get("node")
		if not is_instance_valid(other): return _fallback("retired_peer", started)
		if other == hit_target: continue
		# Known formal actors have pure qualification getters. Unknown script
		# callbacks use the original per-direction path before any result commit.
		if other.get_script() != actor.get_script(): return _fallback("unknown_peer_script", started)
		var center: Vector2 = record.get("position", Vector2.INF)
		var radius := own_radius + float(record.get("radius", 0.0)) + own_margin + Reference.margin_gu(other)
		if not center.is_finite() or maxf(absf(center.x - origin.x), absf(center.y - origin.y)) > 1.0 + radius:
			continue
		if other.runtime_map_id != map_id or not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)):
			continue
		centers.append(center)
		radii.append(radius)
	var has_target := hit_target is CharacterBody2D
	var target_center := Vector2.ZERO
	var target_radius := 0.0
	if has_target:
		target_center = actor.call("_screen_position_px_to_ground_position_gu", hit_target.global_position)
		target_radius = own_radius + float(actor.call("_target_combat_radius_gu", hit_target)) + own_margin + Reference.margin_gu(hit_target)
	if _scope(actor, hit_target) != scope: return _fallback("changed_during_pack", started)
	var packed := Time.get_ticks_usec()
	_metrics["pack_usec"] += packed - started
	_metrics["input_bytes"] += centers.size() * 16 + _directions.size() * 8 + 33
	var points: PackedVector2Array = _kernel.contact_rays(origin, _directions, centers, radii, has_target, target_center, target_radius, GU.EPSILON_GU)
	var returned := Time.get_ticks_usec()
	_metrics["native_call_usec"] += returned - packed
	if points.size() != _directions.size() or _scope(actor, hit_target) != scope:
		return _fallback("invalid_result_or_scope", started)
	for point: Vector2 in points:
		if not point.is_finite() and point != Vector2.INF:
			return _fallback("nonfinite_result", started)
	var finished := Time.get_ticks_usec()
	_metrics["writeback_usec"] += finished - returned
	_metrics["bridge_total_usec"] += finished - started
	_metrics["batches"] += 1
	return points

static func _scope(actor: CharacterBody2D, hit_target: Node2D) -> Array:
	var index: Variant = actor.get("combat_spatial_index")
	return [actor.get_instance_id(), actor.get("runtime_map_id"), actor.get_meta("zone_generation", -1),
		actor.call("_hc_life", actor), actor.global_position,
		hit_target.get_instance_id() if is_instance_valid(hit_target) else 0,
		actor.call("_hc_life", hit_target), hit_target.global_position if is_instance_valid(hit_target) else Vector2.INF,
		index.bucket_membership_revision if index != null else -1]

static func _fallback(reason: String, started: int) -> PackedVector2Array:
	_metrics["fallback_count"] += 1
	var reasons: Dictionary = _metrics["fallback_reasons"]
	reasons[reason] = int(reasons.get(reason, 0)) + 1
	_metrics["bridge_total_usec"] += Time.get_ticks_usec() - started
	return PackedVector2Array()

static func statistics() -> Dictionary:
	var result := _metrics.duplicate(true)
	result["mode"] = _mode
	result["native"] = _kernel.get_statistics() if _kernel != null else {"calls": 0, "kernel_usec": 0}
	result["kernel_clock_scope"] = "C++ synchronous entry, arithmetic and output construction"
	result["bridge_overhead_usec"] = maxi(0, int(result["native_call_usec"]) - int(result["native"].get("kernel_usec", 0)))
	return result

static func close() -> void:
	_kernel = null
	_mode = "disabled"
