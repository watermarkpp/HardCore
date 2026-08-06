class_name GroundSkillEffect
extends Node2D

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const FIRE_WALL_SKILL_ID := "wizard.fire_wall"
const GROUND_UNIT_SETUP_CONTRACT_ID := (
	"skills.ground_effect.setup_ground_unit_effect.v1"
)
const RELEASE_FOOTPRINT_CONTRACT_ID := (
	"skills.ground_effect.ground_exact.shared_release_snapshot.v1"
)
const RUNTIME_TICK_CLAIM_RETENTION_MSEC := 60000
const FIRE_WALL_RENDER_Z_INDEX := -1
const FIRE_WALL_RENDER_ALPHA := 0.78

const VISUAL_PATHS := {
	"wizard.fire_wall": "res://assets/art/characters/wizard/effects/fire_wall.png",
}

var damage := 1
var radius_gu := 0.5
var visual_radius_px := 72.0
var duration := 4.0
var tick_interval := 0.8
var effect_color := Color(1.0, 0.25, 0.05)
var skill_id := ""
var release_id := ""
var skill_footprint_snapshot: Dictionary = {}
var source_actor: Node2D
var runtime_tick_adapter := Callable()
var runtime_target_filter := Callable()
var runtime_damage_enabled := true
var runtime_screen_to_ground_position_px := Callable()
var visual_rejection_reason := ""
var _snapshot_validation_context: Dictionary = {}
var _tick_timer := 0.0
var _sprite: Sprite2D

static var _runtime_tick_claims: Dictionary = {}


func setup_ground_unit_effect(
	position_screen_px: Vector2,
	damage_value: int,
	radius_value_gu: float,
	duration_value: float,
	color: Color,
	source_skill_id := "",
	tick_interval_value := 0.8,
	visual_radius_value_px := 72.0,
	source_release_id := "",
	release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {}
) -> void:
	## Sole production setup boundary: gameplay radius arrives in GU while the
	## screen-space origin and optional visual radius remain explicitly PX.
	global_position = position_screen_px
	damage = maxi(0, damage_value)
	radius_gu = maxf(0.0, radius_value_gu)
	visual_radius_px = maxf(1.0, visual_radius_value_px)
	duration = maxf(0.1, duration_value)
	tick_interval = maxf(0.05, tick_interval_value)
	effect_color = color
	skill_id = ProfessionRules.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	if skill_id.is_empty() and PlayerState != null:
		skill_id = "wizard.fire_wall" if PlayerState.profession == "法师" else ""
	release_id = (
		source_release_id
		if not source_release_id.is_empty()
		else "%s:ground:%d" % [
			skill_id if not skill_id.is_empty() else "unbound.ground_effect",
			get_instance_id(),
		]
	)
	_snapshot_validation_context = (
		snapshot_validation_context
		if snapshot_validation_context is Dictionary
		else {}
	)
	if _snapshot_strict_ok(release_snapshot):
		skill_footprint_snapshot = release_snapshot


func _ready() -> void:
	add_to_group("zone_content")
	if skill_id == FIRE_WALL_SKILL_ID:
		z_index = FIRE_WALL_RENDER_Z_INDEX
		z_as_relative = true
	else:
		z_as_relative = true
	_install_visual()
	queue_redraw()


func configure_runtime_resolution(
	caster: Node2D,
	tick_adapter: Callable,
	applies_damage := true,
	target_filter := Callable(),
	screen_to_ground_position_px := Callable()
) -> void:
	source_actor = caster
	runtime_tick_adapter = tick_adapter
	runtime_damage_enabled = applies_damage
	runtime_target_filter = target_filter
	runtime_screen_to_ground_position_px = screen_to_ground_position_px


func configure_runtime_source(caster: Node2D) -> void:
	source_actor = caster


func runtime_target_is_inside(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	if runtime_target_filter.is_valid():
		return bool(runtime_target_filter.call(target))
	var effect_ground_gu := _runtime_screen_to_ground_position(global_position)
	var target_ground_gu := _runtime_screen_to_ground_position(target.global_position)
	if _snapshot_strict_ok(skill_footprint_snapshot):
		return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_footprint_snapshot,
			target_ground_gu,
			_target_combat_radius_gu(target)
		)
	if SkillFootprintSnapshotScript.has_legacy_base_contract(
		skill_footprint_snapshot
	):
		# Q1-B: a present snapshot that fails STRICT_V2 (for example a runtime
		# map mismatch) must reject the tick instead of silently falling back
		# to a screen-range guess.
		return false
	return GroundUnitSpaceScript.is_within_range_gu(
		effect_ground_gu,
		target_ground_gu,
		radius_gu
	)


func _runtime_screen_to_ground_position(screen_position_px: Vector2) -> Vector2:
	if runtime_screen_to_ground_position_px.is_valid():
		var ground_position_gu: Variant = (
			runtime_screen_to_ground_position_px.call(screen_position_px)
		)
		if ground_position_gu is Vector2:
			return ground_position_gu
	# Without a valid map projection, screen positions cannot be converted to
	# ground coordinates. Treating absolute screen pixels as relative deltas
	# produces silently wrong results. If a SkillFootprintSnapshot is present,
	# the caller must inject a proper runtime_target_filter instead.
	if SkillFootprintSnapshotScript.has_legacy_base_contract(
		skill_footprint_snapshot
	):
		push_error(
			"GroundSkillEffect %s: snapshot present but no valid "
			+ "screen-to-ground projection — cannot resolve target intersection."
			% [skill_id if not skill_id.is_empty() else str(get_instance_id())]
		)
		return Vector2.INF
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_position_px
	)


func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_snapshot_validation_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


static func _target_combat_radius_gu(target: Node2D) -> float:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == "combat_radius_gu":
			return maxf(0.0, float(target.get("combat_radius_gu")))
	return 0.0


func claim_runtime_tick(target: Node) -> bool:
	if skill_id != FIRE_WALL_SKILL_ID or not is_instance_valid(source_actor):
		return true
	if not is_instance_valid(target):
		return false
	var now_msec := Time.get_ticks_msec()
	var claim_key := "%d:%s:%d" % [
		source_actor.get_instance_id(),
		skill_id,
		target.get_instance_id(),
	]
	var current_claim: Dictionary = _runtime_tick_claims.get(claim_key, {})
	var owner_effect_id := int(current_claim.get("owner_effect_id", 0))
	var next_allowed_msec := int(current_claim.get("next_allowed_msec", -1))
	if owner_effect_id != get_instance_id() and now_msec < next_allowed_msec:
		return false
	_runtime_tick_claims[claim_key] = {
		"owner_effect_id": get_instance_id(),
		"next_allowed_msec": now_msec + roundi(tick_interval * 1000.0),
	}
	_cleanup_runtime_tick_claims(now_msec)
	return true


static func reset_runtime_tick_claims_for_tests() -> void:
	_runtime_tick_claims.clear()


static func _cleanup_runtime_tick_claims(now_msec: int) -> void:
	if _runtime_tick_claims.size() < 256:
		return
	for raw_key: Variant in _runtime_tick_claims.keys():
		var claim: Dictionary = _runtime_tick_claims.get(raw_key, {})
		if (
			int(claim.get("next_allowed_msec", 0))
			+ RUNTIME_TICK_CLAIM_RETENTION_MSEC
			< now_msec
		):
			_runtime_tick_claims.erase(raw_key)


func _install_visual() -> void:
	if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
		visual_rejection_reason = CasterSkillVisualRegistry.runtime_readiness_reason(skill_id)
		return
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	if str(profile.get("role", "")) != CasterSkillVisualRegistry.ROLE_GROUND_EFFECT:
		visual_rejection_reason = "non_ground_visual:%s" % str(
			profile.get("role", "missing")
		)
		return
	var candidate := AnimationPlayerScript.new()
	if not candidate.configure(skill_id, Vector2.DOWN, 0.0):
		visual_rejection_reason = "ground_animation_failed"
		candidate.queue_free()
		return
	if skill_id == FIRE_WALL_SKILL_ID:
		candidate.modulate = Color(1.0, 1.0, 1.0, FIRE_WALL_RENDER_ALPHA)
	_sprite = candidate
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if (
				not node is EnemyActor
				or node.is_queued_for_deletion()
				or not runtime_target_is_inside(node)
			):
				continue
			if runtime_damage_enabled and not claim_runtime_tick(node):
				continue
			if runtime_tick_adapter.is_valid():
				runtime_tick_adapter.call(node, damage)
			else:
				node.take_damage(damage, source_actor)
	if duration <= 0.0:
		queue_free()
	if _sprite == null:
		queue_redraw()


func _draw() -> void:
	if _sprite != null or not skill_id.is_empty():
		return
	var pulse := 0.78 + sin(Time.get_ticks_msec() * 0.01) * 0.12
	draw_circle(Vector2.ZERO, visual_radius_px * pulse, Color(effect_color, 0.16))
	draw_circle(Vector2.ZERO, visual_radius_px * pulse, Color(effect_color, 0.70), false, 4.0)
