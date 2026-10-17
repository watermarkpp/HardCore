extends "res://scripts/gameplay/world/world_skill_effect_model.gd"

const GroundUnitSpaceScript = preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript = preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const FIRE_WALL_SKILL_ID = "wizard.fire_wall"
const GROUND_UNIT_SETUP_CONTRACT_ID = (
	"skills.ground_effect.setup_ground_unit_effect.v1"
)
const RELEASE_FOOTPRINT_CONTRACT_ID = (
	"skills.ground_effect.ground_exact.shared_release_snapshot.v1"
)
const RUNTIME_TICK_CLAIM_RETENTION_MSEC = 60000
const FIRE_WALL_RENDER_Z_INDEX = 0
const FIRE_WALL_RENDER_ALPHA = 0.78
const FIRE_WALL_HEIGHT_SCALE = 0.6

const VISUAL_PATHS = {
	"wizard.fire_wall": "res://assets/art/characters/wizard/effects/fire_wall.png",
}

var damage = 1
var radius_gu = 0.5
var visual_radius_px = 72.0
var duration = 4.0
var tick_interval = 0.8
var effect_color = Color(1.0, 0.25, 0.05)
var skill_id = ""
var release_id = ""
var skill_footprint_snapshot: Dictionary = {}

var runtime_tick_adapter = Callable()
var runtime_target_filter = Callable()
var runtime_damage_enabled = true
## Q2-B: when true, PersistentGroundEffectManager owns the damage tick path.
## The node keeps its visual lifecycle only; its own enemy-group scan stays
## closed so damage is never applied twice. FireWall formal cells never set
## this flag and keep their historical visual-only scan contract.
var manager_owned_damage_ticks = false
var runtime_screen_to_ground_position_px = Callable()
var visual_rejection_reason = ""
var _snapshot_validation_context: Dictionary = {}
var _tick_timer = 0.0
## R1-B (GPT audit 2026-09-15): production candidate authority is the shared
## Object. The historical enemy-group scan is closed:
## without an injected spatial context the self-managed tick fails closed
## (no delivery, no group scan, no direct take_damage fallback).
var _combat_spatial_index: Object = null
var _combat_map_id = -1
var legacy_tick_delivery_skip_count = 0



const TargetQueryCore := preload("res://scripts/gameplay/world/world_skill_target_query.gd")


func setup_ground_unit_effect(
	position_screen_px: Vector2,
	damage_value: int,
	radius_value_gu: float,
	duration_value: float,
	color: Color,
	source_skill_id = "",
	tick_interval_value = 0.8,
	visual_radius_value_px = 72.0,
	source_release_id = "",
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
	skill_id = _rules.profession.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	if skill_id.is_empty() and PlayerState != null:
		skill_id = "wizard.fire_wall" if _profile.profession_id == "hc.profession.wizard" else ""
	release_id = (
		source_release_id
		if not source_release_id.is_empty()
		else "%s:ground:%d" % [
			skill_id if not skill_id.is_empty() else "unbound.ground_effect",
			runtime_actor_id(),
		]
	)
	_snapshot_validation_context = (
		snapshot_validation_context
		if snapshot_validation_context is Dictionary
		else {}
	)
	if _snapshot_strict_ok(release_snapshot):
		skill_footprint_snapshot = release_snapshot


func configure_runtime_resolution(
	caster: Object,
	tick_adapter: Callable,
	applies_damage = true,
	target_filter = Callable(),
	screen_to_ground_position_px = Callable()
) -> void:
	source_actor = caster
	runtime_tick_adapter = tick_adapter
	runtime_damage_enabled = applies_damage
	runtime_target_filter = target_filter
	runtime_screen_to_ground_position_px = screen_to_ground_position_px


func configure_runtime_source(caster: Object) -> void:
	source_actor = caster


func set_combat_spatial_context(
	spatial_index: Object,
	runtime_map_id: int
) -> void:
	_combat_spatial_index = spatial_index
	_combat_map_id = runtime_map_id


func runtime_target_is_inside(target: Object) -> bool:
	if not _actors.is_runtime_present(target):
		return false
	if runtime_target_filter.is_valid():
		return bool(runtime_target_filter.call(target))
	var effect_ground_gu = _runtime_screen_to_ground_position(global_position)
	var target_ground_gu = _runtime_screen_to_ground_position(_actors.position_screen_px(target))
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
			"Object %s: snapshot present but no valid "
			+ "screen-to-ground projection — cannot resolve target intersection."
			% [skill_id if not skill_id.is_empty() else str(runtime_actor_id())]
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


func _target_combat_radius_gu(target: Object) -> float:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == "combat_radius_gu":
			return maxf(0.0, float(target.get("combat_radius_gu")))
	return 0.0


func _physics_process(delta: float) -> void:
	duration -= delta
	if not manager_owned_damage_ticks:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = tick_interval
			_run_legacy_damage_tick()
	if duration <= 0.0:
		_world.queue_cast_retirement(self)
	_presentation.redraw_ground_if_without_sprite(self)


func _run_legacy_damage_tick() -> void:
	## R1-B: the self-managed tick keeps its exact historical target-set
	## semantics (runtime_target_is_inside gate, runtime claim gate, adapter
	## delivery) but the candidate universe now comes from the shared
	## Object instead of a full enemy-group scan. Without
	## an injected spatial context the tick fails closed: nothing is
	## delivered and the skip counter advances. The historical direct
	## take_damage fallback is removed (GPT audit R1-P0 item 5).
	var projection_valid = runtime_screen_to_ground_position_px.is_valid()
	if (
		_combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
		or _combat_map_id < 0
		or (
			_snapshot_strict_ok(skill_footprint_snapshot)
			and not projection_valid
		)
	):
		legacy_tick_delivery_skip_count += 1
		return
	var bounds = _runtime_effect_bounds_ground_gu()
	if bounds.size.x < 0.0:
		legacy_tick_delivery_skip_count += 1
		return
	var candidates: Array[Dictionary] = (
		_combat_spatial_index.query_aabb_candidates(
			_combat_map_id, bounds, 0.05
		)
	)
	for candidate: Dictionary in candidates:
		var node: Variant = candidate.get("node")
		if (
			not _actors.is_kind(node, &"enemy")
			or _actors.is_queued_for_retirement(node)
			or not runtime_target_is_inside(node)
		):
			continue
		if runtime_damage_enabled and not claim_runtime_tick(node):
			continue
		if runtime_tick_adapter.is_valid():
			runtime_tick_adapter.call(node, damage)
		else:
			legacy_tick_delivery_skip_count += 1


func _runtime_effect_bounds_ground_gu() -> Rect2:
	var effect_ground_gu = _runtime_screen_to_ground_position(global_position)
	if not effect_ground_gu.is_finite():
		return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
	var radius = maxf(0.0, radius_gu)
	var bounds = Rect2(effect_ground_gu - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	if _snapshot_strict_ok(skill_footprint_snapshot):
		var result = SkillFootprintSnapshotScript.ground_aabb(skill_footprint_snapshot)
		if not bool(result.get("valid", false)):
			return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
		var canonical_bounds: Rect2 = result.bounds_ground_gu
		bounds = bounds.merge(canonical_bounds)
	return bounds

func claim_runtime_tick(target: Object) -> bool:
	return _claims.claim_fire_wall_controller_tick(self, source_actor, skill_id, tick_interval, target)

func _ready() -> void:
	_world.enter_cast_group(self, &"zone_content")
	_presentation.prepare_ground_visual(self)
