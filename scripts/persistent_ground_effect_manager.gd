class_name PersistentGroundEffectManager
extends RefCounted

## Q2-B / HC-P1-007: unified scheduler for generic persistent ground effects.
## Owned by GameRoot; reuses the shared RuntimeCombatSpatialIndex (no second
## enemy index). It only schedules ticks and candidate processing; it never
## computes damage values, decides skill ranges, creates visuals, rebuilds
## snapshots or changes stacking rules. FireWall's formal path (controller +
## 4 visual cells) stays independent.

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const CONTRACT_ID := "hardcore.combat.persistent_ground_effect_manager.v1"
const EXPANSION_EPSILON_GU := 0.05


var _spatial_index: SpatialIndexScript
var _effects: Dictionary = {}
var _registration_sequence := 0
var _rejection_reason := ""

var tick_dispatch_count := 0
var broadphase_query_count := 0
var total_candidate_count := 0
var max_candidate_count := 0
var exact_intersection_test_count := 0
var group_scan_count := 0
var group_nodes_examined := 0
var snapshot_rebuild_count := 0
var damage_application_count := 0
var claim_rejection_count := 0
var expired_effect_count := 0
var cancelled_effect_count := 0
var cross_map_rejection_count := 0
var spatial_index_unavailable_count := 0


func _init(spatial_index: SpatialIndexScript) -> void:
	_spatial_index = spatial_index


func register(registration: Dictionary) -> bool:
	var effect_id := int(registration.get("effect_runtime_id", 0))
	if effect_id <= 0:
		return false
	var snapshot: Dictionary = registration.get("canonical_snapshot", {})
	if (
		int(snapshot.get("schema_version", 0))
		!= Snapshot.SCHEMA_VERSION
		or str(snapshot.get("coordinate_space", ""))
		!= Snapshot.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	):
		return false
	_registration_sequence += 1
	_effects[effect_id] = {
		"effect_runtime_id": effect_id,
		"registration_sequence": _registration_sequence,
		"skill_id": str(registration.get("skill_id", "")),
		"release_id": str(registration.get("release_id", "")),
		"snapshot_id": str(registration.get("snapshot_id", "")),
		"runtime_map_id": int(registration.get("runtime_map_id", -1)),
		"caster_reference": registration.get("caster_reference"),
		"canonical_snapshot": snapshot,
		"expected_context": (
			registration.get("expected_context", {})
			if registration.get("expected_context", {}) is Dictionary
			else {}
		),
		"tick_interval_s": maxf(
			0.05,
			float(registration.get("tick_interval_s", 0.8))
		),
		"elapsed_s": 0.0,
		"next_tick_s": 0.0,
		"expiration_s": maxf(
			0.1,
			float(registration.get("expiration_s", 4.0))
		),
		"stacking_policy": str(registration.get("stacking_policy", "")),
		"claim_policy": str(registration.get("claim_policy", "")),
		"manager_owned_damage_ticks": bool(
			registration.get("manager_owned_damage_ticks", false)
		),
		"damage_callback": (
			registration.get("damage_callback", Callable())
			if registration.get("damage_callback", Callable()) is Callable
			else Callable()
		),
		"lifecycle_callback": (
			registration.get("lifecycle_callback", Callable())
			if registration.get("lifecycle_callback", Callable()) is Callable
			else Callable()
		),
		"effect": registration.get("effect"),
	}
	return true


func unregister(effect_runtime_id: int, reason := "cancelled") -> void:
	if not _effects.has(effect_runtime_id):
		return
	var entry: Dictionary = _effects[effect_runtime_id]
	_effects.erase(effect_runtime_id)
	if reason == "expired":
		expired_effect_count += 1
	else:
		cancelled_effect_count += 1
	var lifecycle_callback: Callable = entry.get(
		"lifecycle_callback",
		Callable()
	)
	if lifecycle_callback.is_valid():
		lifecycle_callback.call(reason, entry.get("effect"))


func clear_map(runtime_map_id: int) -> void:
	var removed: Array[int] = []
	for raw_id: Variant in _effects.keys():
		var entry: Dictionary = _effects.get(raw_id, {})
		if int(entry.get("runtime_map_id", -1)) == runtime_map_id:
			removed.append(int(raw_id))
	for effect_id: int in removed:
		unregister(effect_id, "map_cleared")


func clear_all() -> void:
	## World-teardown sweep: the caller (GameRoot) frees every zone_content
	## node on map transition; all manager registrations must leave with them.
	var removed: Array[int] = []
	for raw_id: Variant in _effects.keys():
		removed.append(int(raw_id))
	for effect_id: int in removed:
		unregister(effect_id, "map_cleared")


func registered_effect_count() -> int:
	return _effects.size()


func tick_frame(delta: float) -> void:
	if delta <= 0.0 or _effects.is_empty():
		return
	var ordered := _sorted_entries()
	for entry: Dictionary in ordered:
		var effect_id := int(entry.get("effect_runtime_id", 0))
		if not _effects.has(effect_id):
			continue
		var live: Dictionary = _effects[effect_id]
		var effect_node: Variant = live.get("effect")
		if (
			effect_node == null
			or not is_instance_valid(effect_node)
			or (effect_node is Node and (effect_node as Node).is_queued_for_deletion())
		):
			unregister(effect_id, "node_freed")
			continue
		live["elapsed_s"] = float(live.get("elapsed_s", 0.0)) + delta
		var elapsed := float(live.get("elapsed_s", 0.0))
		var expires := elapsed >= float(live.get("expiration_s", 0.0))
		if elapsed >= float(live.get("next_tick_s", 0.0)):
			_dispatch_tick(live)
		if expires:
			unregister(effect_id, "expired")


func persistent_ground_effect_diagnostics() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"registered_effect_count": _effects.size(),
		"active_effect_count": _effects.size(),
		"tick_dispatch_count": tick_dispatch_count,
		"broadphase_query_count": broadphase_query_count,
		"total_candidate_count": total_candidate_count,
		"max_candidate_count": max_candidate_count,
		"exact_intersection_test_count": exact_intersection_test_count,
		"group_scan_count": group_scan_count,
		"group_nodes_examined": group_nodes_examined,
		"snapshot_rebuild_count": snapshot_rebuild_count,
		"damage_application_count": damage_application_count,
		"claim_rejection_count": claim_rejection_count,
		"expired_effect_count": expired_effect_count,
		"cancelled_effect_count": cancelled_effect_count,
		"cross_map_rejection_count": cross_map_rejection_count,
		"spatial_index_unavailable_count": spatial_index_unavailable_count,
		"rejection_reason": _rejection_reason,
	}


func _sorted_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id: Variant in _effects.keys():
		result.append(_effects.get(raw_id, {}))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_seq := int(a.get("registration_sequence", 0))
			var b_seq := int(b.get("registration_sequence", 0))
			if a_seq != b_seq:
				return a_seq < b_seq
			return int(a.get("effect_runtime_id", 0)) < int(
				b.get("effect_runtime_id", 0)
			)
	)
	return result


func _dispatch_tick(entry: Dictionary) -> void:
	tick_dispatch_count += 1
	# Old cadence: after a tick the timer resets to a full interval (max one
	# tick per physics frame, no multi-tick catch-up on long frames).
	var elapsed := float(entry.get("elapsed_s", 0.0))
	entry["next_tick_s"] = (
		elapsed + float(entry.get("tick_interval_s", 0.8))
	)
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	if (
		_spatial_index == null
		or not is_instance_valid(_spatial_index)
	):
		spatial_index_unavailable_count += 1
		_rejection_reason = "spatial_index_unavailable"
		return
	var snapshot: Dictionary = entry.get("canonical_snapshot", {})
	var expected_context: Dictionary = entry.get("expected_context", {})
	if not bool(Snapshot.validate_for_consumer(
		snapshot,
		expected_context,
		Snapshot.VALIDATION_STRICT_V2
	).get("valid", false)):
		_rejection_reason = "invalid_snapshot"
		return
	var effect: Node = entry.get("effect")
	if effect == null or not is_instance_valid(effect):
		return
	if not (effect is GroundSkillEffect):
		return
	var ground_effect := effect as GroundSkillEffect
	if (
		not bool(entry.get("manager_owned_damage_ticks", false))
		or not ground_effect.manager_owned_damage_ticks
	):
		return
	broadphase_query_count += 1
	var candidates: Array[Dictionary] = _spatial_index.query_aabb_candidates(
		runtime_map_id,
		_snapshot_bounds_ground_gu(snapshot),
		EXPANSION_EPSILON_GU
	)
	total_candidate_count += candidates.size()
	max_candidate_count = maxi(max_candidate_count, candidates.size())
	for candidate: Dictionary in candidates:
		var raw_node: Variant = candidate.get("node")
		if not raw_node is EnemyActor:
			continue
		var enemy := raw_node as EnemyActor
		if enemy.is_queued_for_deletion() or not is_instance_valid(enemy):
			continue
		exact_intersection_test_count += 1
		if not ground_effect.runtime_target_is_inside(enemy):
			continue
		if not ground_effect.claim_runtime_tick(enemy):
			claim_rejection_count += 1
			continue
		_apply_damage(ground_effect, entry, enemy)


func _apply_damage(
	ground_effect: GroundSkillEffect,
	entry: Dictionary,
	enemy: EnemyActor
) -> void:
	damage_application_count += 1
	var damage_callback: Callable = entry.get("damage_callback", Callable())
	if damage_callback.is_valid():
		damage_callback.call(enemy, ground_effect.damage)
	elif ground_effect.runtime_tick_adapter.is_valid():
		ground_effect.runtime_tick_adapter.call(enemy, ground_effect.damage)
	elif ground_effect.damage > 0:
		enemy.take_damage(ground_effect.damage, ground_effect.source_actor)


func _snapshot_bounds_ground_gu(snapshot: Dictionary) -> Rect2:
	var min_gu := Vector2.INF
	var max_gu := -Vector2.INF
	var polygons: Variant = snapshot.get("polygons_ground_gu", [])
	if polygons is Array:
		for raw_polygon: Variant in polygons:
			if raw_polygon is PackedVector2Array:
				for point: Vector2 in raw_polygon as PackedVector2Array:
					min_gu.x = minf(min_gu.x, point.x)
					min_gu.y = minf(min_gu.y, point.y)
					max_gu.x = maxf(max_gu.x, point.x)
					max_gu.y = maxf(max_gu.y, point.y)
	if not min_gu.is_finite() or not max_gu.is_finite():
		var origin := snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2
		return Rect2(origin, Vector2.ZERO)
	return Rect2(min_gu, max_gu - min_gu)
