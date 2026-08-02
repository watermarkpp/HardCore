class_name SkillProjectile
extends Node2D

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
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

const VISUAL_PATHS := {
	"wizard.fireball": "res://assets/art/characters/wizard/effects/fireball.png",
	"wizard.great_fireball": "res://assets/art/characters/wizard/effects/great_fireball.png",
	"taoist.soul_fire_talisman": "res://assets/art/characters/taoist/effects/soul_fire_talisman.png",
}

var direction := Vector2.RIGHT
# Formal gameplay motion. The unsuffixed fields below are compatibility mirrors
# only and are never read by the physics path.
var direction_ground_gu := Vector2(1.0, -1.0).normalized()
var speed_gu_per_sec := CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC
var max_travel_distance_gu := -1.0
var traveled_distance_gu := 0.0
var remaining_travel_distance_gu := -1.0
var projectile_radius_gu := CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU
var visual_muzzle_offset_px := Vector2.ZERO
var speed := 520.0
var remaining_range := 360.0
var maximum_range_tiles := -1.0
var traveled_range_tiles := 0.0
var damage := 1
var effect := "damage"
var effect_strength := 0
var effect_duration := 0.0
var projectile_color := Color(0.35, 0.7, 1.0)
var hit_radius := 24.0
var skill_id := ""
var resolution_skill_id := ""
var source_actor: Node2D
var magic_defense_adapter := Callable()
var anti_magic_roll_override := -1
var anti_poison_roll_override := -1
var last_resolution: Dictionary = {}
var _sprite: Sprite2D
var visual_rejection_reason := ""
var _projectile_role_valid := false


func setup(start: Vector2, cast_direction: Vector2, value: int, travel_range: float, color: Color, status_effect := "damage", status_strength := 0, status_duration := 0.0, source_skill_id := "") -> void:
	global_position = start
	direction = cast_direction.normalized() if cast_direction.length() > 0.0 else Vector2.RIGHT
	direction_ground_gu = GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction
	).normalized()
	damage = maxi(0, value)
	remaining_range = maxf(40.0, travel_range)
	remaining_travel_distance_gu = (
		CombatUnitLegacyAdapterScript.legacy_screen_distance_px_to_gu(
			remaining_range
		)
	)
	projectile_color = color
	effect = status_effect
	effect_strength = status_strength
	effect_duration = status_duration
	resolution_skill_id = ProfessionRules.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	skill_id = resolution_skill_id
	if skill_id.is_empty() and PlayerState != null:
		if PlayerState.profession == "法师":
			skill_id = "wizard.fireball"
		elif PlayerState.profession == "道士":
			skill_id = "taoist.soul_fire_talisman"


func setup_ground_unit_motion(
	start_screen_position_px: Vector2,
	cast_direction_ground_gu: Vector2,
	maximum_distance_gu: float,
	speed_value_gu_per_sec := CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC,
	radius_gu := CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU,
	muzzle_offset_px := Vector2.ZERO
) -> void:
	global_position = start_screen_position_px
	direction_ground_gu = (
		cast_direction_ground_gu.normalized()
		if cast_direction_ground_gu.length_squared() > 0.000001
		else Vector2(1.0, -1.0).normalized()
	)
	direction = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		direction_ground_gu
	).normalized()
	speed_gu_per_sec = maxf(0.0, speed_value_gu_per_sec)
	projectile_radius_gu = maxf(0.0, radius_gu)
	visual_muzzle_offset_px = muzzle_offset_px
	configure_maximum_travel_distance_gu(maximum_distance_gu)


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
	source_skill_id := ""
) -> void:
	## The sole production setup boundary. All gameplay motion arrives in GU;
	## screen PX is retained only for presentation origin and muzzle offset.
	global_position = start_screen_position_px
	direction_ground_gu = (
		cast_direction_ground_gu.normalized()
		if cast_direction_ground_gu.length_squared() > 0.000001
		else Vector2(1.0, -1.0).normalized()
	)
	direction = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
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


func configure_maximum_range_tiles(value: float) -> void:
	# Legacy field is numerically GU under the versioned combat-unit adapter.
	configure_maximum_travel_distance_gu(value)


func configure_maximum_travel_distance_gu(value_gu: float) -> void:
	max_travel_distance_gu = value_gu if value_gu > 0.0 else -1.0
	maximum_range_tiles = max_travel_distance_gu
	traveled_distance_gu = 0.0
	traveled_range_tiles = 0.0
	if max_travel_distance_gu > 0.0:
		remaining_travel_distance_gu = max_travel_distance_gu


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
	var candidate := AnimationPlayerScript.new()
	if not candidate.configure(skill_id, direction, desired_extent):
		visual_rejection_reason = "projectile_animation_failed"
		candidate.queue_free()
		return
	_sprite = candidate
	add_child(_sprite)
	_sprite.position = visual_muzzle_offset_px


func _physics_process(delta: float) -> void:
	if not skill_id.is_empty() and not _projectile_role_valid:
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
	global_position = segment_end_screen_px
	traveled_distance_gu += travel_distance_gu
	traveled_range_tiles = traveled_distance_gu
	if remaining_travel_distance_gu >= 0.0:
		remaining_travel_distance_gu = maxf(
			0.0,
			remaining_travel_distance_gu - travel_distance_gu
		)
		remaining_range = (
			remaining_travel_distance_gu
			* CombatUnitLegacyAdapterScript.CANONICAL_SOUTH_AXIS_PX_PER_GU
		)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		if not _swept_segment_intersects_enemy_footprint(
			segment_start_screen_px,
			segment_end_screen_px,
			node
		):
			continue
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
	var enemy_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			enemy.collision_radius
		)
	)
	var contact_radius_gu := enemy_radius_gu + maxf(0.0, projectile_radius_gu)
	return swept_segment_intersects_footprint_gu(
		segment_start_ground_relative,
		segment_end_ground_relative,
		Vector2.ZERO,
		contact_radius_gu
	)


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
	draw_line(-direction * 30.0, Vector2.ZERO, Color(projectile_color, 0.25), 10.0)
	if _sprite == null:
		draw_circle(Vector2.ZERO, 9.0, projectile_color)
	draw_circle(Vector2.ZERO, 14.0, Color(projectile_color, 0.22), false, 4.0)
