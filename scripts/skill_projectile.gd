class_name SkillProjectile
extends Node2D

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const FOOTPRINT_HIT_CONTRACT_ID := (
	"skills.projectile.ground_gu_swept_footprint_contact.v2"
)
const GROUND_UNIT_SETUP_CONTRACT_ID := (
	"skills.projectile.setup_ground_unit_projectile.v1"
)
const RELEASE_FOOTPRINT_CONTRACT_ID := (
	"skills.projectile.release_swept_path.shared_snapshot.v1"
)

const VISUAL_PATHS := {
	"wizard.fireball": "res://assets/art/characters/wizard/effects/fireball.png",
	"wizard.great_fireball": "res://assets/art/characters/wizard/effects/great_fireball.png",
	"taoist.soul_fire_talisman": "res://assets/art/characters/taoist/effects/soul_fire_talisman.png",
}

var direction_screen_px := Vector2.RIGHT
# Formal gameplay motion. Screen PX is presentation-only; all range, speed and
# collision state is expressed in ground units.
var direction_ground_gu := Vector2(1.0, -1.0).normalized()
var speed_gu_per_sec := CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC
var max_travel_distance_gu := -1.0
var traveled_distance_gu := 0.0
var remaining_travel_distance_gu := -1.0
var projectile_radius_gu := CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU
var visual_muzzle_offset_px := Vector2.ZERO
var damage := 1
var effect := "damage"
var effect_strength := 0
var effect_duration := 0.0
var projectile_color := Color(0.35, 0.7, 1.0)
var skill_id := ""
var release_id := ""
var skill_footprint_snapshot: Dictionary = {}
var last_segment_footprint_snapshot: Dictionary = {}
var runtime_map_id: int = -1
var runtime_ground_gu_to_screen_position_px := Callable()
var runtime_screen_to_ground_position_px := Callable()
## FREEZE-P0.1: fail-closed projection diagnostics.
var missing_projection_rejection_count := 0
var projection_rejection_reason := &""
var _combat_spatial_index: RuntimeCombatSpatialIndexScript
var resolution_skill_id := ""
var source_actor: Node2D
var magic_defense_adapter := Callable()
var anti_magic_roll_override := -1
var anti_poison_roll_override := -1
var last_resolution: Dictionary = {}
var _sprite: Sprite2D
var visual_rejection_reason := ""
var _projectile_role_valid := false
var _physics_segment_index := 0
var _canonical_release_snapshot_bound := false
var _release_snapshot_build_count := 0

var _broadphase_physics_step_count := 0
var _broadphase_snapshot_build_count := 0
var _broadphase_query_count := 0
var _broadphase_total_candidate_count := 0
var _broadphase_max_candidate_count := 0
var _broadphase_exact_test_count := 0
var _broadphase_group_scan_count := 0
var _broadphase_group_nodes_examined := 0
var _broadphase_hit_count := 0
var _broadphase_cross_map_rejection_count := 0
var _broadphase_stale_candidate_count := 0
var _broadphase_unavailable_count := 0


func setup_ground_unit_projectile(
	start_screen_position_px: Vector2,
	cast_direction_ground_gu: Vector2,
	maximum_distance_gu: float,
	value: int,
	speed_value_gu_per_sec := CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC,
	radius_gu := CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU,
	muzzle_offset_px := Vector2.ZERO,
	color := Color.WHITE,
	status_effect := "damage",
	status_strength := 0,
	status_duration := 0.0,
	source_skill_id := "",
	source_release_id := "",
	canonical_release_snapshot: Dictionary = {}
) -> void:
	## The sole production setup boundary. All gameplay motion arrives in GU;
	## screen PX is retained only for presentation origin and muzzle offset.
	global_position = start_screen_position_px
	direction_ground_gu = (
		cast_direction_ground_gu.normalized()
		if cast_direction_ground_gu.length_squared() > 0.000001
		else Vector2(1.0, -1.0).normalized()
	)
	direction_screen_px = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		direction_ground_gu
	).normalized()
	speed_gu_per_sec = maxf(0.0, float(speed_value_gu_per_sec))
	projectile_radius_gu = maxf(0.0, float(radius_gu))
	visual_muzzle_offset_px = muzzle_offset_px
	damage = maxi(0, value)
	projectile_color = color
	effect = status_effect
	effect_strength = status_strength
	effect_duration = status_duration
	resolution_skill_id = (
		ProfessionRules.skill_id(source_skill_id)
		if not source_skill_id.is_empty()
		else ""
	)
	skill_id = resolution_skill_id
	if skill_id.is_empty() and PlayerState != null:
		if PlayerState.profession == "法师":
			skill_id = "wizard.fireball"
		elif PlayerState.profession == "道士":
			skill_id = "taoist.soul_fire_talisman"
	configure_maximum_travel_distance_gu(maximum_distance_gu)
	release_id = (
		source_release_id
		if not source_release_id.is_empty()
		else "%s:projectile:%d" % [
			skill_id if not skill_id.is_empty() else "unbound.projectile",
			get_instance_id(),
		]
	)
	if canonical_release_snapshot.is_empty():
		_build_release_footprint_snapshot()
	else:
		# The canonical planner owns the only release-level snapshot.  Keep the
		# exact frozen object; only physical segment snapshots are derived later.
		_canonical_release_snapshot_bound = true
		skill_footprint_snapshot = canonical_release_snapshot


func configure_runtime_map_projection(
	map_id: int,
	ground_gu_to_screen_position_px: Callable,
	screen_position_px_to_ground_gu: Callable = Callable()
) -> void:
	runtime_map_id = int(map_id)
	runtime_ground_gu_to_screen_position_px = (
		ground_gu_to_screen_position_px
		if ground_gu_to_screen_position_px is Callable
		else Callable()
	)
	runtime_screen_to_ground_position_px = (
		screen_position_px_to_ground_gu
		if screen_position_px_to_ground_gu is Callable
		else Callable()
	)
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		skill_footprint_snapshot = {}
		return
	if _canonical_release_snapshot_bound:
		if not _canonical_release_snapshot_valid():
			projection_rejection_reason = &"invalid_canonical_release_snapshot"
			skill_footprint_snapshot = {}
		return
	_build_release_footprint_snapshot()


func projection_ready() -> bool:
	if runtime_map_id < 0:
		return true
	return runtime_screen_to_ground_position_px.is_valid()


func configure_spatial_index(index: RuntimeCombatSpatialIndexScript) -> void:
	_combat_spatial_index = index


func _snapshot_coordinate_context(origin_ground_gu: Vector2) -> Dictionary:
	return SkillFootprintSnapshotScript.make_absolute_runtime_context(
		runtime_map_id,
		origin_ground_gu,
		origin_ground_gu,
		runtime_ground_gu_to_screen_position_px
	)


func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	var expected_context := _snapshot_coordinate_context(
		_runtime_screen_to_ground_position(global_position)
	)
	if runtime_map_id >= 0:
		expected_context["expected_runtime_map_id"] = runtime_map_id
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		expected_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


func _canonical_release_snapshot_valid() -> bool:
	return (
		not skill_footprint_snapshot.is_empty()
		and str(skill_footprint_snapshot.get("skill_id", "")) == skill_id
		and str(skill_footprint_snapshot.get("release_id", "")) == release_id
		and _snapshot_strict_ok(skill_footprint_snapshot)
	)


func configure_runtime_resolution(
	caster: Node2D = null,
	defense_adapter := Callable(),
	anti_magic_roll := -1,
	anti_poison_roll := -1
) -> void:
	source_actor = caster
	magic_defense_adapter = defense_adapter if defense_adapter is Callable else Callable()
	anti_magic_roll_override = anti_magic_roll
	anti_poison_roll_override = anti_poison_roll


func configure_maximum_travel_distance_gu(value_gu: float) -> void:
	max_travel_distance_gu = value_gu if value_gu > 0.0 else -1.0
	traveled_distance_gu = 0.0
	if max_travel_distance_gu > 0.0:
		remaining_travel_distance_gu = max_travel_distance_gu


func _build_release_footprint_snapshot() -> void:
	_release_snapshot_build_count += 1
	if max_travel_distance_gu <= 0.0:
		skill_footprint_snapshot = {}
		return
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		skill_footprint_snapshot = {}
		return
	var origin_ground_gu := _runtime_screen_to_ground_position(global_position)
	skill_footprint_snapshot = (
		SkillFootprintSnapshotScript.create_swept_capsule_path(
			skill_id if not skill_id.is_empty() else "unbound.projectile",
			release_id,
			origin_ground_gu,
			origin_ground_gu
			+ direction_ground_gu * max_travel_distance_gu,
			projectile_radius_gu,
			SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS / 2,
			"",
			-1,
			_snapshot_coordinate_context(origin_ground_gu)
		)
	)


func _ready() -> void:
	add_to_group("zone_content")
	_install_visual()
	queue_redraw()


func _install_visual() -> void:
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	if str(profile.get("role", "")) != CasterSkillVisualRegistry.ROLE_PROJECTILE:
		visual_rejection_reason = "non_projectile_visual:%s" % str(
			profile.get("role", "missing")
		)
		set_physics_process(false)
		return
	_projectile_role_valid = true
	if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
		visual_rejection_reason = CasterSkillVisualRegistry.runtime_readiness_reason(skill_id)
		return
	var render := CasterSkillVisualRegistry.render_policy(skill_id)
	var desired_extent := maxf(1.0, float(render.get("fit_extent", 34.0)))
	var presentation_overrides := {}
	if skill_id == "taoist.soul_fire_talisman":
		## The talisman source frames carry a hand-relative draw offset
		## (source_draw_offset) rather than a top-left world anchor. Anchoring
		## at the actor foot/hand and dropping the 24px direction muzzle lets
		## the paper fly from the character's body along the target direction
		## while gameplay release origin stays canonical.
		presentation_overrides["anchor_policy"] = (
			"source_draw_offset_from_actor_foot"
		)
	var candidate := AnimationPlayerScript.new()
	if not candidate.configure(
		skill_id,
		direction_screen_px,
		desired_extent,
		null,
		"",
		Vector2.ZERO,
		0.0,
		Vector2.ZERO,
		0.0,
		presentation_overrides
	):
		visual_rejection_reason = "projectile_animation_failed"
		candidate.queue_free()
		return
	_sprite = candidate
	add_child(_sprite)
	_sprite.position = (
		Vector2.ZERO
		if skill_id == "taoist.soul_fire_talisman"
		else visual_muzzle_offset_px
	)


func _physics_process(delta: float) -> void:
	if not skill_id.is_empty() and not _projectile_role_valid:
		return
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		# FREEZE-P0.1: mapped projectile without a projection must stop
		# immediately; no segment snapshot, no broadphase query, no damage.
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		queue_free()
		return
	var available_distance_gu := (
		remaining_travel_distance_gu
		if remaining_travel_distance_gu >= 0.0
		else INF
	)
	var travel_distance_gu := minf(
		maxf(0.0, speed_gu_per_sec) * maxf(0.0, delta),
		available_distance_gu
	)
	var motion_ground_gu := direction_ground_gu * travel_distance_gu
	var motion_screen_px := (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(motion_ground_gu)
	)
	var segment_start_screen_px := global_position
	var segment_end_screen_px := global_position + motion_screen_px
	var segment_start_ground_gu := _runtime_screen_to_ground_position(
		segment_start_screen_px
	)
	var segment_end_ground_gu := _runtime_screen_to_ground_position(
		segment_end_screen_px
	)
	last_segment_footprint_snapshot = (
		SkillFootprintSnapshotScript.create_swept_capsule_path(
			skill_id if not skill_id.is_empty() else "unbound.projectile",
			"%s:segment:%d" % [release_id, _physics_segment_index],
			segment_start_ground_gu,
			segment_end_ground_gu,
			projectile_radius_gu,
			SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS / 2,
			str(skill_footprint_snapshot.get("snapshot_id", "")),
			_physics_segment_index,
			_snapshot_coordinate_context(segment_start_ground_gu)
		)
	)
	_broadphase_snapshot_build_count += 1
	_physics_segment_index += 1
	global_position = segment_end_screen_px
	traveled_distance_gu += travel_distance_gu
	# Q1-B: a segment that no longer validates against the frozen runtime map
	# (e.g. projection became invalid) stops the projectile immediately. The
	# snapshot map id never follows the current player map.
	if not _snapshot_strict_ok(last_segment_footprint_snapshot):
		remaining_travel_distance_gu = 0.0
		queue_free()
		return
	if remaining_travel_distance_gu >= 0.0:
		remaining_travel_distance_gu = maxf(
			0.0,
			remaining_travel_distance_gu - travel_distance_gu
		)
	_broadphase_physics_step_count += 1
	if (
		_combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
	):
		# Q2-A: no fallback to a full enemy-group scan. Reject this frame's
		# hits and record the failure; production always injects the index.
		_broadphase_unavailable_count += 1
	elif runtime_map_id < 0:
		_broadphase_cross_map_rejection_count += 1
	else:
		_broadphase_query_count += 1
		var candidates: Array[Dictionary] = (
			_combat_spatial_index.query_segment_candidates(
				runtime_map_id,
				segment_start_ground_gu,
				segment_end_ground_gu,
				projectile_radius_gu + 0.05
			)
		)
		_broadphase_total_candidate_count += candidates.size()
		_broadphase_max_candidate_count = maxi(
			_broadphase_max_candidate_count,
			candidates.size()
		)
		for candidate: Dictionary in candidates:
			var candidate_node: Variant = candidate.get("node")
			if not candidate_node is EnemyActor:
				continue
			var node := candidate_node as EnemyActor
			if node.is_queued_for_deletion() or not is_instance_valid(node):
				_broadphase_stale_candidate_count += 1
				continue
			_broadphase_exact_test_count += 1
			if not _swept_segment_intersects_enemy_footprint(
				segment_start_screen_px,
				segment_end_screen_px,
				node
			):
				continue
			_broadphase_hit_count += 1
			_apply_hit(node)
			queue_free()
			return
	if (
		remaining_travel_distance_gu >= 0.0
		and remaining_travel_distance_gu <= GroundUnitSpaceScript.EPSILON_GU
	):
		queue_free()


func _intersects_enemy_footprint(enemy: EnemyActor) -> bool:
	return _swept_segment_intersects_enemy_footprint(
		global_position,
		global_position,
		enemy
	)


func _swept_segment_intersects_enemy_footprint(
	segment_start_screen_px: Vector2,
	segment_end_screen_px: Vector2,
	enemy: EnemyActor
) -> bool:
	var enemy_center_ground_gu := (
		_runtime_screen_to_ground_position(enemy.global_position)
	)
	if (
		_snapshot_strict_ok(skill_footprint_snapshot)
		and not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_footprint_snapshot,
			enemy_center_ground_gu,
			enemy.combat_radius_gu
		)
	):
		return false
	if _snapshot_strict_ok(last_segment_footprint_snapshot):
		return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			last_segment_footprint_snapshot,
			enemy_center_ground_gu,
			enemy.combat_radius_gu
		)
	var segment_start_ground_relative := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			segment_start_screen_px - enemy.global_position
		)
	)
	var segment_end_ground_relative := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			segment_end_screen_px - enemy.global_position
		)
	)
	var enemy_radius_gu := enemy.combat_radius_gu
	var contact_radius_gu := enemy_radius_gu + maxf(0.0, projectile_radius_gu)
	return swept_segment_intersects_footprint_gu(
		segment_start_ground_relative,
		segment_end_ground_relative,
		Vector2.ZERO,
		contact_radius_gu
	)


func _runtime_screen_to_ground_position(screen_position_px: Vector2) -> Vector2:
	if runtime_screen_to_ground_position_px.is_valid():
		var ground_position_gu: Variant = (
			runtime_screen_to_ground_position_px.call(screen_position_px)
		)
		if ground_position_gu is Vector2:
			return ground_position_gu
	if runtime_map_id < 0:
		return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			screen_position_px
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = (
		GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
	)
	return Vector2.INF


func release_snapshot_intersects_target_footprint_ground_gu(
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float
) -> bool:
	return (
		_snapshot_strict_ok(skill_footprint_snapshot)
		and SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_footprint_snapshot,
			target_center_ground_gu,
			target_combat_radius_gu
		)
	)


func projectile_broadphase_diagnostics() -> Dictionary:
	var index_diagnostics: Dictionary = (
		_combat_spatial_index.diagnostics()
		if _combat_spatial_index != null
		and is_instance_valid(_combat_spatial_index)
		else {}
	)
	var index_available := (
		_combat_spatial_index != null
		and is_instance_valid(_combat_spatial_index)
	)
	return {
		"runtime_map_id": runtime_map_id,
		"canonical_release_snapshot_bound": _canonical_release_snapshot_bound,
		"release_snapshot_build_count": _release_snapshot_build_count,
		"spatial_index_available": index_available,
		"spatial_index_rejection_reason": (
			"" if index_available else "broadphase_unavailable"
		),
		"physics_step_count": _broadphase_physics_step_count,
		"snapshot_build_count": _broadphase_snapshot_build_count,
		"broadphase_query_count": _broadphase_query_count,
		"total_candidate_count": _broadphase_total_candidate_count,
		"max_candidate_count": _broadphase_max_candidate_count,
		"exact_test_count": _broadphase_exact_test_count,
		"group_scan_count": _broadphase_group_scan_count,
		"group_nodes_examined": _broadphase_group_nodes_examined,
		"hit_count": _broadphase_hit_count,
		"cross_map_candidate_rejection_count": (
			_broadphase_cross_map_rejection_count
		),
		"stale_candidate_count": _broadphase_stale_candidate_count,
		"broadphase_unavailable_count": _broadphase_unavailable_count,
		"index_bucket_change_count": int(
			index_diagnostics.get("index_bucket_change_count", 0)
		),
	}


static func swept_segment_intersects_footprint_gu(
	segment_start_ground_gu: Vector2,
	segment_end_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	combined_contact_radius_gu: float
) -> bool:
	## Pure deterministic helper used by the runtime every physics frame and by
	## contract tests. This prevents a fast projectile from tunnelling between
	## its previous and current GU positions.
	var start_relative_gu := segment_start_ground_gu - target_center_ground_gu
	var segment_ground_gu := segment_end_ground_gu - segment_start_ground_gu
	var closest_relative_gu := start_relative_gu
	if segment_ground_gu.length_squared() > 0.0000001:
		var weight := clampf(
			-start_relative_gu.dot(segment_ground_gu)
			/ segment_ground_gu.length_squared(),
			0.0,
			1.0
		)
		closest_relative_gu += segment_ground_gu * weight
	var inclusive_radius_gu := (
		maxf(0.0, combined_contact_radius_gu)
		+ GroundUnitSpaceScript.EPSILON_GU
	)
	return (
		closest_relative_gu.length_squared()
		<= inclusive_radius_gu * inclusive_radius_gu
	)


func _apply_hit(enemy: EnemyActor) -> void:
	if effect == "poison":
		var poison_bound := TaoistCombatMath.anti_poison_random_bound(enemy.anti_poison)
		var poison_roll := anti_poison_roll_override if anti_poison_roll_override >= 0 else randi_range(0, poison_bound - 1)
		var poison_applies := TaoistCombatMath.poison_succeeds(enemy.anti_poison, poison_roll)
		last_resolution = {
			"evasion_channel": "anti_poison",
			"anti_poison_checked": true,
			"anti_poison_random_bound": poison_bound,
			"anti_poison_roll": poison_roll,
			"poison_applies": poison_applies,
		}
		if not poison_applies:
			return
	elif effect == "damage" and CombatResolutionRules.anti_magic_eligible(resolution_skill_id):
		var anti_magic_roll := anti_magic_roll_override if anti_magic_roll_override >= 0 else randi_range(0, CombatResolutionRules.ANTI_MAGIC_ROLL_SIDES - 1)
		last_resolution = CombatResolutionRules.resolve_direct_spell_damage(
			resolution_skill_id,
			damage,
			enemy.monster_data,
			anti_magic_roll,
			magic_defense_adapter
		)
		var resolved_damage := int(last_resolution.final_damage)
		if resolved_damage <= 0:
			return
		enemy.take_damage(resolved_damage, source_actor)
	elif damage > 0:
		enemy.take_damage(damage, source_actor)
	if not is_instance_valid(enemy):
		return
	match effect:
		"poison": enemy.apply_poison(maxi(1, effect_strength), maxf(1.0, effect_duration))
		"control": enemy.apply_control(maxf(0.5, effect_duration))
		"charm": enemy.apply_charm(maxf(1.0, effect_duration))


func _draw() -> void:
	if not skill_id.is_empty() and not _projectile_role_valid:
		return
	if _sprite != null:
		return
	draw_line(-direction_screen_px * 30.0, Vector2.ZERO, Color(projectile_color, 0.25), 10.0)
	if _sprite == null:
		draw_circle(Vector2.ZERO, 9.0, projectile_color)
	draw_circle(Vector2.ZERO, 14.0, Color(projectile_color, 0.22), false, 4.0)
