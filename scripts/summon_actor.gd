class_name SummonActor
extends CharacterBody2D

signal summon_state_changed(previous_state: int, current_state: int)
signal passive_wakeup_changed()

const SummonDomainStateScript := preload("res://scripts/gameplay/actors/summon_domain_state.gd")
const SummonActorModelScript := preload("res://scripts/gameplay/actors/summon_actor_model.gd")
const SummonLegacyPortsScript := preload("res://scripts/gameplay/actors/summon_legacy_actor_ports.gd")
var _legacy_ports: RefCounted

const DamageLedgerObserverScript := preload("res://scripts/damage_ledger_observer.gd")

const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")
const WarriorCombatMathScript := preload("res://scripts/warrior_combat_math.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const MonsterSourcePoisonStateScript := preload("res://scripts/monster_source_poison_state.gd")

const SPATIAL_CONTRACT_ID := "skills.summon_actor.spatial_ground_gu.v1"
const SPAWN_FOOTPRINT_CONTRACT_ID := (
	"skills.summon.spawn_destination_footprint_snapshot.v1"
)
const ATTACK_FOOTPRINT_CONTRACT_ID := (
	"skills.summon.attack_release_directed_gu.v2"
)
const PERSISTENCE_CONTRACT_ID := "skills.summon.persistence.runtime_state.v1"
const DIRECT_SPELL_DAMAGE_RUNTIME_ID := (
	"summon.direct_spell_damage.openmir2.v1"
)
const STEALTH_STATE_CONTRACT_ID := SummonDomainStateScript.STEALTH_STATE_CONTRACT_ID
const BUFF_STATE_CONTRACT_ID := SummonDomainStateScript.BUFF_STATE_CONTRACT_ID
const SUSTAINED_FRAME_COST_CONTRACT_ID := (
	"skills.summon.sustained_frame_cost.bounded.v1"
)
const VISUAL_FOOT_ANCHOR_CONTRACT_ID := (
	"skills.summon.visual_authored_ground_point_at_actor_origin.v2"
)
const LEVEL_LABEL_CONTRACT_ID := "skills.summon.level_label.current_pet_level.v1"
const TARGET_ACQUISITION_CONTRACT_ID := (
	"skills.summon.target_acquisition.shared_spatial_index.v1"
)
const GROUND_SHADOW_CONTRACT_ID := (
	"skills.summon.ground_shadow.authored_body_frames.v2"
)
const REST_FORMATION_CONTRACT_ID := (
	"skills.summon.owner_formation_slots.v1"
)
const OWNER_TELEPORT_RELOCATION_CONTRACT_ID := (
	"skills.summon.owner_teleport_relocation.v1"
)
const AUDIO_MONSTER_HOOK_CONTRACT_ID := (
	"skills.summon.audio_monster_identity.v1"
)
## These are the exact monster templates from taoist_summon_baseline.  The
## audio service owns the event mapping; SummonActor only supplies the stable
## integer identity and the already-accepted lifecycle phase.
const AUDIO_MONSTER_ID_BY_SUMMON_ID := {
	"skeleton": 145,
	"divine_beast": 146,
}
const COLLISION_INTERACTION_CONTRACT_ID := (
	"skills.summon.collision.player_pet_passthrough.v1"
)
const TARGET_ACQUIRE_INTERVAL_SECONDS := 0.25
const FORMATION_WAKE_DISTANCE_GU := 0.35
const FORMATION_SETTLE_DISTANCE_GU := 0.15
const GROUND_SHADOW_CENTER_LOCAL_PX := Vector2.ZERO
const GROUND_SHADOW_VERTICAL_SCALE := 0.36
const RECALL_OFFSET_GU := (
	42.0 / CombatUnitLegacyAdapterScript.ISO_AREA_EQUIVALENT_PX_PER_GU
)
const STEALTH_BODY_MODULATE_ALPHA := 0.60
const BUFF_HINT_FONT_SIZE := 10
const BUFF_HINT_LINE_SPACING := 12.0
const BUFF_HINT_OFFSET_Y := 6.0
const LEVEL_LABEL_FONT_SIZE := 10
const LEVEL_LABEL_GAP_PX := 2.0
const SKELETON_ATTACK_LENGTH_GU := 1.5
const DIVINE_BEAST_ATTACK_LENGTH_GU := 3.0
const SUMMON_ATTACK_WIDTH_GU := 1.0
const _VISUAL_REQUEST_MAX_ATTEMPTS := 8

enum SummonState {
	FOLLOW_OWNER,
	ACQUIRE_TARGET,
	CHASE_TARGET,
	ATTACK_TARGET,
	RETURN_TO_OWNER,
	EXPIRED,
	DEAD,
}

const VISUAL_PATHS := {
	"taoist.summon_skeleton": "res://assets/art/characters/taoist/effects/summon_skeleton.png",
	"taoist.summon_divine_beast": "res://assets/art/characters/taoist/effects/summon_divine_beast.png",
}

# One numeric owner shared by the legacy adapter and the future S actor.
# Rules are explicit ports; the legacy path supplies the original scripts.
var domain_state := SummonActorModelScript.new(
	TaoistCombatMath, SkillRankResolver,
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(135.0)
)

var owner_player: PlayerCharacter:
	get: return _legacy_ports.resolve_actor(domain_state.owner_link) as PlayerCharacter if _legacy_ports != null else null
	set(value): domain_state.owner_link = _legacy_ports.capture_actor(value)
var _monster_source_poison: RefCounted:
	get: return domain_state._monster_source_poison
	set(value): domain_state._monster_source_poison = value
var _monster_control_remaining: float:
	get: return domain_state._monster_control_remaining
	set(value): domain_state._monster_control_remaining = value
## Owner character level frozen at summon creation. Fully independent of the
## pet's own growth level (summon_exp_level).
var owner_level: int:
	get: return domain_state.owner_level
	set(value): domain_state.owner_level = value
var runtime_map_id: int:
	get: return domain_state.runtime_map_id
	set(value): domain_state.runtime_map_id = value
var runtime_ground_gu_to_screen_position_px: Callable:
	get: return domain_state.runtime_ground_gu_to_screen_position_px
	set(value): domain_state.runtime_ground_gu_to_screen_position_px = value
var runtime_screen_to_ground_position_px: Callable:
	get: return domain_state.runtime_screen_to_ground_position_px
	set(value): domain_state.runtime_screen_to_ground_position_px = value
var _combat_spatial_index: RuntimeCombatSpatialIndexScript
var _outgoing_magic_stats: Dictionary:
	get: return domain_state._outgoing_magic_stats
	set(value): domain_state._outgoing_magic_stats = value
var _rest_formation_moving: bool:
	get: return domain_state._rest_formation_moving
	set(value): domain_state._rest_formation_moving = value
## FREEZE-P0.1: fail-closed projection diagnostics.
var missing_projection_rejection_count: int:
	get: return domain_state.missing_projection_rejection_count
	set(value): domain_state.missing_projection_rejection_count = value
var projection_rejection_reason: StringName:
	get: return domain_state.projection_rejection_reason
	set(value): domain_state.projection_rejection_reason = value
var summon_name: String:
	get: return domain_state.summon_name
	set(value): domain_state.summon_name = value
var summon_id: String:
	get: return domain_state.summon_id
	set(value): domain_state.summon_id = value
var skill_id: String:
	get: return domain_state.skill_id
	set(value): domain_state.skill_id = value
var skill_level: int:
	get: return domain_state.skill_level
	set(value): domain_state.skill_level = value
var effective_skill_rank: int:
	get: return domain_state.effective_skill_rank
	set(value): domain_state.effective_skill_rank = value
var pet_slot_index: int:
	get: return domain_state.pet_slot_index
	set(value): domain_state.pet_slot_index = value
var _divine_damage_more: float:
	get: return domain_state.divine_damage_more
	set(value): domain_state.divine_damage_more = value
var summon_level: int:
	get: return domain_state.summon_level
	set(value): domain_state.summon_level = value
var summon_exp_level: int:
	get: return domain_state.summon_exp_level
	set(value): domain_state.summon_exp_level = value
var maximum_pet_level: int:
	get: return domain_state.maximum_pet_level
	set(value): domain_state.maximum_pet_level = value
var pet_growth_exp: int:
	get: return domain_state.pet_growth_exp
	set(value): domain_state.pet_growth_exp = value
var summon_count: int:
	get: return domain_state.summon_count
	set(value): domain_state.summon_count = value
var attack_type: String:
	get: return domain_state.attack_type
	set(value): domain_state.attack_type = value
var monster_level: int:
	get: return domain_state.monster_level
	set(value): domain_state.monster_level = value
var max_hp: int:
	get: return domain_state.max_hp
	set(value): domain_state.max_hp = value
var current_hp: int:
	get: return domain_state.current_hp
	set(value): domain_state.current_hp = value
var attack_min: int:
	get: return domain_state.attack_min
	set(value): domain_state.attack_min = value
var attack_max: int:
	get: return domain_state.attack_max
	set(value): domain_state.attack_max = value
var ac_min: int:
	get: return domain_state.ac_min
	set(value): domain_state.ac_min = value
var ac_max: int:
	get: return domain_state.ac_max
	set(value): domain_state.ac_max = value
var mac_min: int:
	get: return domain_state.mac_min
	set(value): domain_state.mac_min = value
var mac_max: int:
	get: return domain_state.mac_max
	set(value): domain_state.mac_max = value
var accuracy: int:
	get: return domain_state.accuracy
	set(value): domain_state.accuracy = value
var agility: int:
	get: return domain_state.agility
	set(value): domain_state.agility = value
var name_color_index: int:
	get: return domain_state.name_color_index
	set(value): domain_state.name_color_index = value
var attack_interval: float:
	get: return domain_state.attack_interval
	set(value): domain_state.attack_interval = value
var lifetime_seconds: float:
	get: return domain_state.lifetime_seconds
	set(value): domain_state.lifetime_seconds = value
var remaining_lifetime: float:
	get: return domain_state.remaining_lifetime
	set(value): domain_state.remaining_lifetime = value
var move_speed_gu_per_sec: float:
	get: return domain_state.move_speed_gu_per_sec
	set(value): domain_state.move_speed_gu_per_sec = value
var attack_range_gu: float:
	get: return domain_state.attack_range_gu
	set(value): domain_state.attack_range_gu = value
var aggro_radius_gu: float:
	get: return domain_state.aggro_radius_gu
	set(value): domain_state.aggro_radius_gu = value
var combat_radius_gu: float:
	get: return domain_state.combat_radius_gu
	set(value): domain_state.combat_radius_gu = value
var collision_radius_px: float:
	get: return domain_state.collision_radius_px
	set(value): domain_state.collision_radius_px = value
var leash_range_gu: float:
	get: return domain_state.leash_range_gu
	set(value): domain_state.leash_range_gu = value
var teleport_range_gu: float:
	get: return domain_state.teleport_range_gu
	set(value): domain_state.teleport_range_gu = value
var follow_distance_gu: float:
	get: return domain_state.follow_distance_gu
	set(value): domain_state.follow_distance_gu = value
var actual_ground_motion_gu: Vector2:
	get: return domain_state.actual_ground_motion_gu
	set(value): domain_state.actual_ground_motion_gu = value
var owner_death_rule: String:
	get: return domain_state.owner_death_rule
	set(value): domain_state.owner_death_rule = value
var reject_when_owner_has_slave: bool:
	get: return domain_state.reject_when_owner_has_slave
	set(value): domain_state.reject_when_owner_has_slave = value
var recall_existing_on_create_failure: bool:
	get: return domain_state.recall_existing_on_create_failure
	set(value): domain_state.recall_existing_on_create_failure = value
var state: int:
	get: return domain_state.state
	set(value): domain_state.state = value
var owner_teleport_pending: bool:
	get: return domain_state.owner_teleport_pending
	set(value): domain_state.owner_teleport_pending = value
var _owner_teleport_saved_collision_layer: int:
	get: return domain_state._owner_teleport_saved_collision_layer
	set(value): domain_state._owner_teleport_saved_collision_layer = value
var _owner_teleport_saved_collision_mask: int:
	get: return domain_state._owner_teleport_saved_collision_mask
	set(value): domain_state._owner_teleport_saved_collision_mask = value
var last_attack_type: String:
	get: return domain_state.last_attack_type
	set(value): domain_state.last_attack_type = value
var summon_release_id: String:
	get: return domain_state.summon_release_id
	set(value): domain_state.summon_release_id = value
var summon_spawn_footprint_snapshot: Dictionary:
	get: return domain_state.summon_spawn_footprint_snapshot
	set(value): domain_state.summon_spawn_footprint_snapshot = value
var last_attack_footprint_snapshot: Dictionary:
	get: return domain_state.last_attack_footprint_snapshot
	set(value): domain_state.last_attack_footprint_snapshot = value
var last_attack_relation: String:
	get: return domain_state.last_attack_relation
	set(value): domain_state.last_attack_relation = value
var _attack_timer: float:
	get: return domain_state._attack_timer
	set(value): domain_state._attack_timer = value
var _attack_release_sequence: int:
	get: return domain_state._attack_release_sequence
	set(value): domain_state._attack_release_sequence = value
var _rng: RandomNumberGenerator:
	get: return domain_state._rng
	set(value): domain_state._rng = value
var _sprite: Sprite2D
var _fire_sprite: Sprite2D
var _current_target: EnemyActor:
	get: return _legacy_ports.resolve_actor(domain_state.current_target_link) as EnemyActor if _legacy_ports != null else null
	set(value): domain_state.current_target_link = _legacy_ports.capture_actor(value)
var _animation_resources: Dictionary = {}
var _visual_profile_complete: bool:
	get: return domain_state._visual_profile_complete
	set(value): domain_state._visual_profile_complete = value
var _visual_preview_active: bool:
	get: return domain_state._visual_preview_active
	set(value): domain_state._visual_preview_active = value
var _visual_state: String:
	get: return domain_state._visual_state
	set(value): domain_state._visual_state = value
var _visual_direction: int:
	get: return domain_state._visual_direction
	set(value): domain_state._visual_direction = value
var _visual_frame: int:
	get: return domain_state._visual_frame
	set(value): domain_state._visual_frame = value
var _visual_elapsed: float:
	get: return domain_state._visual_elapsed
	set(value): domain_state._visual_elapsed = value
var _visual_facing: Vector2:
	get: return domain_state._visual_facing
	set(value): domain_state._visual_facing = value
var _attack_visual_remaining: float:
	get: return domain_state._attack_visual_remaining
	set(value): domain_state._attack_visual_remaining = value
var _hit_visual_remaining: float:
	get: return domain_state._hit_visual_remaining
	set(value): domain_state._hit_visual_remaining = value
var _death_visual_remaining: float:
	get: return domain_state._death_visual_remaining
	set(value): domain_state._death_visual_remaining = value
var _pending_attack_target: EnemyActor:
	get: return _legacy_ports.resolve_actor(domain_state.pending_attack_target_link) as EnemyActor if _legacy_ports != null else null
	set(value): domain_state.pending_attack_target_link = _legacy_ports.capture_actor(value)
var _pending_attack_snapshot: Dictionary:
	get: return domain_state._pending_attack_snapshot
	set(value): domain_state._pending_attack_snapshot = value
var _pending_attack_release_remaining: float:
	get: return domain_state._pending_attack_release_remaining
	set(value): domain_state._pending_attack_release_remaining = value
var _pending_attack_direction: Vector2:
	get: return domain_state._pending_attack_direction
	set(value): domain_state._pending_attack_direction = value
var _fire_visual_elapsed := 0.0
var _fire_visual_remaining := 0.0
var _health_bar_y := -35.0
var _visual_request_id := SummonVisualRegistryScript.REQUEST_UNKNOWN
var _visual_request_attempts := 0
var _target_acquire_remaining: float:
	get: return domain_state._target_acquire_remaining
	set(value): domain_state._target_acquire_remaining = value
var _target_scan_count: int:
	get: return domain_state._target_scan_count
	set(value): domain_state._target_scan_count = value
var _target_candidate_count: int:
	get: return domain_state._target_candidate_count
	set(value): domain_state._target_candidate_count = value
var _target_acquire_fail_closed_count: int:
	get: return domain_state._target_acquire_fail_closed_count
	set(value): domain_state._target_acquire_fail_closed_count = value
var _target_acquire_last_rejection_reason: String:
	get: return domain_state._target_acquire_last_rejection_reason
	set(value): domain_state._target_acquire_last_rejection_reason = value
var _custom_draw_request_count := 0
var _sprite_frame_apply_count := 0
var _last_buff_draw_signature := Vector2i(-1, -1)

## Presentation-only monster SFX observer. Lookup is lifecycle-aware and
## shared across actors so the hot physics path never scans the group per actor.
static var _audio_runtime_service: Node
const AUDIO_SERVICE_NEGATIVE_CACHE_MSEC := 1000
static var _audio_service_retry_after_msec := 0
static var _audio_service_lookup_count := 0
static var _audio_service_now_override_msec := -1
var _audio_appear_emitted := false
var _audio_death_emitted := false
var _audio_attack_sequence := 0
var _audio_attack_frame_sequence := -1

## Independent support-buff state: stealth, physical defence (AC) and magic
## defence (MAC) each keep their own timer and refresh independently.
var stealth_remaining_seconds: float:
	get: return domain_state.stealth_remaining_seconds
	set(value): domain_state.stealth_remaining_seconds = value
var stealth_buff_id: String:
	get: return domain_state.stealth_buff_id
	set(value): domain_state.stealth_buff_id = value
var ac_buff_bonus: int:
	get: return domain_state.ac_buff_bonus
	set(value): domain_state.ac_buff_bonus = value
var ac_buff_remaining_seconds: float:
	get: return domain_state.ac_buff_remaining_seconds
	set(value): domain_state.ac_buff_remaining_seconds = value
var ac_buff_id: String:
	get: return domain_state.ac_buff_id
	set(value): domain_state.ac_buff_id = value
var mac_buff_bonus: int:
	get: return domain_state.mac_buff_bonus
	set(value): domain_state.mac_buff_bonus = value
var mac_buff_remaining_seconds: float:
	get: return domain_state.mac_buff_remaining_seconds
	set(value): domain_state.mac_buff_remaining_seconds = value
var mac_buff_id: String:
	get: return domain_state.mac_buff_id
	set(value): domain_state.mac_buff_id = value


func _init() -> void:
	_legacy_ports = SummonLegacyPortsScript.new(self)
	domain_state.configure_ports({
		"profile": PlayerState, "profession_rules": ProfessionRules,
		"warrior_rules": WarriorCombatMathScript, "combat_rules": CombatResolutionRules,
		"art_rules": preload("res://scripts/art_spec.gd"), "actor_links": _legacy_ports,
		"motion": _legacy_ports, "lifetime": _legacy_ports, "presentation": _legacy_ports,
		"damage_observer": _legacy_ports, "landing": _legacy_ports, "spatial": _legacy_ports,
	})
	assert(domain_state.bind_runtime_actor_id(get_instance_id()))
	domain_state.summon_state_changed.connect(summon_state_changed.emit)
	domain_state.passive_wakeup_changed.connect(_on_domain_passive_wakeup_changed)


func _on_domain_passive_wakeup_changed() -> void:
	# Preserve synchronous listener reentry inside the domain timer sweep.
	passive_wakeup_changed.emit()


func setup(
	player: PlayerCharacter,
	display_name: String,
	power: int,
	learned_level := -1,
	source_skill_id := "",
	owner_level_value := -1,
	maximum_pet_level_value := -1
) -> void:
	domain_state.setup(_legacy_ports.capture_actor(player), display_name, power, learned_level, source_skill_id, owner_level_value, maximum_pet_level_value)


func configure_spawn_release_footprint(source_release_id: String) -> void:
	domain_state.configure_spawn_release_footprint(source_release_id)


func configure_runtime_map_projection(
	map_id: int,
	ground_gu_to_screen_position_px: Callable,
	screen_position_px_to_ground_gu: Callable = Callable()
) -> void:
	domain_state.configure_runtime_map_projection(map_id, ground_gu_to_screen_position_px, screen_position_px_to_ground_gu)


func configure_spatial_index(index: RuntimeCombatSpatialIndexScript) -> void:
	_combat_spatial_index = index
	_legacy_ports.configure_spatial_index(index)


func _audio_monster_id() -> int:
	return int(AUDIO_MONSTER_ID_BY_SUMMON_ID.get(summon_id, -1))


func _audio_service() -> Node:
	if not is_inside_tree():
		return null
	if (
		is_instance_valid(_audio_runtime_service)
		and _audio_runtime_service.is_inside_tree()
		and _audio_runtime_service.get_tree() == get_tree()
	):
		return _audio_runtime_service
	_audio_runtime_service = null
	var now_msec := _audio_service_cache_now_msec()
	if now_msec < _audio_service_retry_after_msec:
		return null
	_audio_service_retry_after_msec = now_msec + AUDIO_SERVICE_NEGATIVE_CACHE_MSEC
	_audio_service_lookup_count += 1
	for candidate: Node in get_tree().get_nodes_in_group(&"audio_runtime_service"):
		if (
			is_instance_valid(candidate)
			and candidate.is_inside_tree()
			and candidate.has_method("play_monster_event")
		):
			_audio_runtime_service = candidate
			_audio_service_retry_after_msec = 0
			return candidate
	return null


static func _audio_service_cache_now_msec() -> int:
	return (
		_audio_service_now_override_msec
		if _audio_service_now_override_msec >= 0
		else Time.get_ticks_msec()
	)


static func set_audio_service_cache_clock_for_test(now_msec: int) -> void:
	_audio_service_now_override_msec = now_msec


static func audio_service_lookup_count_for_test() -> int:
	return _audio_service_lookup_count


func _audio_is_listenable(allow_death := false) -> bool:
	if not is_inside_tree() or process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	if not allow_death and not is_physics_processing():
		return false
	if not allow_death and state in [SummonState.EXPIRED, SummonState.DEAD]:
		return false
	var viewport := get_viewport()
	if viewport == null or not visible or not is_visible_in_tree():
		return false
	# Reuse the existing client viewport as the audibility boundary.  Do not
	# wake off-screen pets or invent a second gameplay-distance rule for SFX.
	return viewport.get_visible_rect().has_point(
		get_global_transform_with_canvas().origin
	)


func _audio_context(semantic_event: String) -> Dictionary:
	return {
		"source": "summon_actor",
		"contract_id": AUDIO_MONSTER_HOOK_CONTRACT_ID,
		"monster_id": _audio_monster_id(),
		"summon_id": summon_id,
		"skill_id": skill_id,
		"runtime_map_id": runtime_map_id,
		"semantic_event": semantic_event,
	}


func _emit_summon_audio(semantic_event: String, allow_death := false) -> bool:
	var monster_id := _audio_monster_id()
	if monster_id <= 0 or not _audio_is_listenable(allow_death):
		return false
	var service := _audio_service()
	if service == null:
		return false
	# The service performs exact-ID event resolution and fail-closed mapping;
	# this actor never derives an event from display names or appearance data.
	service.call(
		"play_monster_event",
		monster_id,
		semantic_event,
		_audio_context(semantic_event),
	)
	return true


func _audio_try_emit_appear() -> void:
	# The existing production whitelist disables appear. Seal the old hook
	# without retries while off-screen or while no audio service exists.
	_audio_appear_emitted = true


func _audio_attack_started() -> void:
	_audio_attack_sequence += 1
	_audio_attack_frame_sequence = -1
	# This is called only after _begin_attack has accepted a target and frozen
	# its release snapshot; target acquisition alone never emits attack_start.
	_emit_summon_audio("attack_start")


func _audio_attack_frame() -> void:
	if (
		_audio_attack_sequence <= 0
		or _audio_attack_frame_sequence == _audio_attack_sequence
	):
		return
	# The attack-frame cue is an action-frame observation, not a hit result. Set
	# the guard before dispatch so a service rejection cannot replay the cue.
	_audio_attack_frame_sequence = _audio_attack_sequence
	_emit_summon_audio("attack_frame")


func _audio_hurt() -> void:
	_emit_summon_audio("hurt")


func _audio_death_once() -> void:
	if _audio_death_emitted:
		return
	_audio_death_emitted = true
	_emit_summon_audio("death", true)


func relocate_after_owner_teleport(final_position_px: Vector2) -> Dictionary:
	return domain_state.relocate_after_owner_teleport(final_position_px)


func defer_owner_teleport_relocation() -> void:
	domain_state.defer_owner_teleport_relocation()


func _reset_combat_after_owner_teleport() -> void:
	domain_state._reset_combat_after_owner_teleport()


func projection_ready() -> bool:
	return domain_state.projection_ready()


func _snapshot_coordinate_context(origin_ground_gu: Vector2) -> Dictionary:
	return domain_state._snapshot_coordinate_context(origin_ground_gu)


func _ready() -> void:
	add_to_group("summons")
	add_to_group("combat_targets")
	add_to_group("zone_content")
	collision_layer = WorldSpatialRulesScript.PLAYER_LAYER
	collision_mask = (
		WorldSpatialRulesScript.WORLD_LAYER
		| WorldSpatialRulesScript.ENEMY_LAYER
	)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	domain_state.initialize_gameplay()
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	# HC-BODY-2TIER-1P5-V1: summons resolve their body from the same two-tier
	# policy as monsters. The skeleton joins the small tier (dropping the old
	# 15 px round shape), the divine beast joins the large tier (dropping the
	# old 21 px round shape and its screen-circle vs isometric-convention
	# mismatch). One shared 16-point isometric footsole shape, local transform
	# identity, resolved once before any spawn footprint or index use.
	collision_radius_px = ActorBodyPolicyScript.tier_screen_radius_px(
		StringName(ActorBodyPolicyScript.summon_tier(summon_id))
	)
	if collision_radius_px <= 0.0:
		# Unknown summon id: fail closed to the small tier with a diagnostic.
		collision_radius_px = ActorBodyPolicyScript.tier_screen_radius_px(
			ActorBodyPolicyScript.TIER_SMALL
		)
		set_meta("body_policy_fallback", "unknown_summon_id")
	combat_radius_gu = (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			collision_radius_px
		)
	)
	collision.shape = ActorBodyPolicyScript.footsole_shape_px(collision_radius_px)
	add_child(collision)
	_install_visual()
	_last_buff_draw_signature = _buff_draw_signature()
	_request_visual_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		## Advance one ready ResourceLoader result so an actor teardown can still
		## contribute to the shared warm cache; ResourceLoader owns worker life.
		SummonVisualRegistryScript.reap_completed_requests()


func _process(delta: float) -> void:
	domain_state.step_process(delta)


func _physics_process(delta: float) -> void:
	domain_state.step_physics(delta)


func _owner_follow_landing_authority() -> Node:
	var owner_node: Node = get_parent()
	while owner_node != null:
		if (
			owner_node.has_method("_canonical_summon_follow_landing_plan")
			and owner_node.has_method("_register_pending_main_pet_arrival")
		):
			return owner_node
		owner_node = owner_node.get_parent()
	return null


func _canonical_owner_teleport_landing_plan() -> Dictionary:
	return domain_state._canonical_owner_teleport_landing_plan()


func _defer_owner_follow_landing() -> void:
	domain_state._defer_owner_follow_landing()


func _begin_attack(enemy: EnemyActor) -> void:
	domain_state._begin_attack(_legacy_ports.capture_actor(enemy))


func _update_pending_attack(delta: float) -> void:
	domain_state._update_pending_attack(delta)


func _release_pending_attack() -> void:
	domain_state._release_pending_attack()


func _outgoing_damage_after_defense(target: EnemyActor) -> int:
	return domain_state._outgoing_damage_after_defense(target)


func _attack_hit_succeeds(target: EnemyActor) -> bool:
	return domain_state._attack_hit_succeeds(_legacy_ports.capture_actor(target))


func _attack_release_delay_seconds() -> float:
	return domain_state._attack_release_delay_seconds()


func _clear_pending_attack() -> void:
	domain_state._clear_pending_attack()


func retire_for_rank_cap() -> void:
	domain_state.retire_for_rank_cap()


func _expire() -> void:
	domain_state._expire()


func _set_state(next_state: int) -> void:
	domain_state._set_state(next_state)


func _nearest_enemy() -> EnemyActor:
	return _legacy_ports.resolve_actor(domain_state._nearest_enemy()) as EnemyActor


func _enemy_accepts_external_attack(enemy: EnemyActor) -> bool:
	return domain_state._enemy_accepts_external_attack(_legacy_ports.capture_actor(enemy))


func _reject_target_acquisition(reason: String) -> void:
	domain_state._reject_target_acquisition(reason)


func _owner_formation_anchor_screen_px() -> Vector2:
	return domain_state._owner_formation_anchor_screen_px()


func rest_formation_contract_snapshot() -> Dictionary:
	return domain_state.rest_formation_contract_snapshot()


func spatial_contract_snapshot() -> Dictionary:
	return domain_state.spatial_contract_snapshot()


func synchronize_skill_rank(rank: int) -> bool:
	return domain_state.synchronize_skill_rank(rank)


func gain_growth_from_kill(killed_monster_level: int) -> bool:
	return domain_state.gain_growth_from_kill(killed_monster_level)


func growth_contract_snapshot() -> Dictionary:
	return domain_state.growth_contract_snapshot()


func _apply_growth_stats_preserving_current_hp() -> void:
	domain_state.apply_growth_stats_preserving_current_hp()


func create_attack_release_footprint_snapshot(target: Node2D) -> Dictionary:
	return domain_state.create_attack_release_footprint_snapshot(_legacy_ports.capture_actor(target))


func _attack_effect_length_gu() -> float:
	return domain_state._attack_effect_length_gu()


func _target_within_attack_geometry(target: Node2D) -> bool:
	return domain_state._target_within_attack_geometry(_legacy_ports.capture_actor(target))


func _attack_world_path_clear(target: Node2D) -> bool:
	return domain_state._attack_world_path_clear(_legacy_ports.capture_actor(target))


func attack_release_snapshot_intersects_target(
	attack_snapshot: Dictionary,
	target: Node2D
) -> bool:
	return domain_state.attack_release_snapshot_intersects_target(attack_snapshot, _legacy_ports.capture_actor(target))


func _runtime_screen_to_ground_position(screen_position_px: Vector2) -> Vector2:
	return domain_state._runtime_screen_to_ground_position(screen_position_px)


func distance_gu_to_screen_position_px(target_screen_position_px: Vector2) -> float:
	return domain_state.distance_gu_to_screen_position_px(target_screen_position_px)


func target_footprint_surface_distance_gu(
	target_screen_position_px: Vector2,
	target_combat_radius_gu: float
) -> float:
	return domain_state.target_footprint_surface_distance_gu(target_screen_position_px, target_combat_radius_gu)


static func _target_combat_radius_gu(target: Node) -> float:
	return SummonLegacyPortsScript.target_combat_radius_gu_for_actor(target)


func _screen_velocity_toward_delta_px(delta_screen_px: Vector2) -> Vector2:
	return domain_state._screen_velocity_toward_delta_px(delta_screen_px)


static func _distance_gu_between_screen_positions_px(
	first_screen_position_px: Vector2,
	second_screen_position_px: Vector2
) -> float:
	return SummonActorModelScript._distance_gu_between_screen_positions_px(first_screen_position_px, second_screen_position_px)


func apply_control(seconds: float) -> void:
	domain_state.apply_control(seconds)


func apply_monster_poison(tick_damage: int, seconds: float, interval_seconds: float) -> bool:
	return domain_state.apply_monster_poison(tick_damage, seconds, interval_seconds)


func _update_monster_source_poison(delta: float) -> void:
	domain_state._update_monster_source_poison(delta)


func take_damage(
	amount: int,
	source_or_defense_roll: Variant = null,
	defense_roll := -1,
	delivery_identity: Variant = null,
) -> void:
	domain_state.take_damage(amount, source_or_defense_roll, defense_roll, delivery_identity)


func take_monster_mixed_damage(
	physical_raw: int,
	magic_raw: int,
	context: Dictionary,
	delivery_identity: Variant = null,
) -> Dictionary:
	return domain_state.take_monster_mixed_damage(physical_raw, magic_raw, context, delivery_identity)


func take_magic_damage(amount: int, magic_defense_roll := -1) -> void:
	domain_state.take_magic_damage(amount, magic_defense_roll)


func take_direct_spell_damage(
	skill_id_value: String,
	raw_damage: int,
	anti_magic_roll := -1,
	magic_defense_roll := -1,
	causes_struck := true,
	delivery_identity: Variant = null,
) -> Dictionary:
	return domain_state.take_direct_spell_damage(skill_id_value, raw_damage, anti_magic_roll, magic_defense_roll, causes_struck, delivery_identity)


func _resolve_direct_spell_magic_defense(
	_skill_id_value: String,
	incoming_damage: int,
	target_stats: Dictionary,
	roll_override: int,
	resolution_state: Dictionary,
) -> int:
	return domain_state._resolve_direct_spell_magic_defense(_skill_id_value, incoming_damage, target_stats, roll_override, resolution_state)


func _roll_defense(
	base_minimum: int,
	base_maximum: int,
	active_bonus: int,
	roll_override: int,
) -> int:
	return domain_state._roll_defense(base_minimum, base_maximum, active_bonus, roll_override)


func restore_health(amount: int) -> int:
	return domain_state.restore_health(amount)


func _apply_resolved_damage(amount: int, causes_struck := true, delivery_identity: Variant = null) -> void:
	domain_state._apply_resolved_damage(amount, causes_struck, delivery_identity)


func apply_stealth(seconds: float, buff_id := "buff.taoist.mass_invisibility") -> void:
	domain_state.apply_stealth(seconds, buff_id)


func is_stealthed() -> bool:
	return domain_state.is_stealthed()


func stealth_remaining() -> float:
	return domain_state.stealth_remaining()


func apply_ac_buff(bonus: int, seconds: float, buff_id := "") -> void:
	domain_state.apply_ac_buff(bonus, seconds, buff_id)


func apply_mac_buff(bonus: int, seconds: float, buff_id := "") -> void:
	domain_state.apply_mac_buff(bonus, seconds, buff_id)


func physical_defence_bonus() -> int:
	return domain_state.physical_defence_bonus()


func magic_defence_bonus() -> int:
	return domain_state.magic_defence_bonus()


func clear_ac_buff() -> void:
	domain_state.clear_ac_buff()


func clear_mac_buff() -> void:
	domain_state.clear_mac_buff()


func buff_state_snapshot() -> Dictionary:
	return domain_state.buff_state_snapshot()


func _update_support_buff_timers(delta: float) -> void:
	domain_state.update_support_buff_timers(delta)


func _buff_draw_signature() -> Vector2i:
	return Vector2i(
		ceili(ac_buff_remaining_seconds)
			if ac_buff_bonus > 0 and ac_buff_remaining_seconds > 0.0
			else 0,
		ceili(mac_buff_remaining_seconds)
			if mac_buff_bonus > 0 and mac_buff_remaining_seconds > 0.0
			else 0
	)


func _screen_velocity_toward_arrival_delta_px(
	delta_screen_px: Vector2,
	delta: float
) -> Vector2:
	return domain_state._screen_velocity_toward_arrival_delta_px(delta_screen_px, delta)


func _refresh_buff_redraw_if_needed() -> void:
	var signature := _buff_draw_signature()
	if signature == _last_buff_draw_signature:
		return
	_last_buff_draw_signature = signature
	_request_visual_redraw()


func _request_visual_redraw() -> void:
	_custom_draw_request_count += 1
	queue_redraw()


func _update_stealth_visual() -> void:
	## Only the summoned body/fire layers fade. The health bar and buff hints
	## are drawn separately in _draw() and must stay readable.
	var body_modulate := Color(
		1.0,
		1.0,
		1.0,
		STEALTH_BODY_MODULATE_ALPHA if is_stealthed() else 1.0
	)
	if _sprite != null and _sprite.self_modulate != body_modulate:
		_sprite.self_modulate = body_modulate
	if _fire_sprite != null and _fire_sprite.self_modulate != body_modulate:
		_fire_sprite.self_modulate = body_modulate


func _buff_hint_lines() -> Array[String]:
	## Directly consumes buff_state_snapshot() so hints always agree with the
	## canonical AC/MAC boost and expiry state.
	var snapshot := buff_state_snapshot()
	var lines: Array[String] = []
	var physical: Dictionary = snapshot.get("physical_defence", {})
	var ac_bonus := int(physical.get("bonus", 0))
	var ac_remaining := float(physical.get("remaining_seconds", 0.0))
	if ac_bonus > 0 and ac_remaining > 0.0:
		lines.append("AC+%d %ds" % [ac_bonus, ceili(ac_remaining)])
	var magic: Dictionary = snapshot.get("magic_defence", {})
	var mac_bonus := int(magic.get("bonus", 0))
	var mac_remaining := float(magic.get("remaining_seconds", 0.0))
	if mac_bonus > 0 and mac_remaining > 0.0:
		lines.append("MAC+%d %ds" % [mac_bonus, ceili(mac_remaining)])
	return lines


func state_name() -> String:
	return domain_state.state_name()


func _install_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = (
		"DivineBeastAnimatedBody"
		if summon_id == "divine_beast"
		else "MutantSkeletonAnimatedBody"
	)
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	request_visual_resources()


func request_visual_resources() -> void:
	if _visual_profile_complete:
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_FAILED:
		return
	_visual_request_id = SummonVisualRegistryScript.request_profile(summon_id)
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_READY:
		_visual_request_attempts = 0
		activate_visual_resources()
	elif _visual_request_id > SummonVisualRegistryScript.REQUEST_UNKNOWN:
		_visual_request_attempts = 0


func _poll_visual_activation() -> void:
	if _visual_profile_complete:
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_READY:
		activate_visual_resources()
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_FAILED:
		return
	if _visual_request_id == SummonVisualRegistryScript.REQUEST_UNKNOWN:
		_visual_request_attempts += 1
		if _visual_request_attempts >= _VISUAL_REQUEST_MAX_ATTEMPTS:
			_visual_request_id = SummonVisualRegistryScript.REQUEST_FAILED
			return
		request_visual_resources()
		return
	var profile := SummonVisualRegistryScript.poll_profile(_visual_request_id)
	if profile.is_empty():
		var preview := SummonVisualRegistryScript.preview_profile(
			_visual_request_id
		)
		if not preview.is_empty() and not _visual_preview_active:
			_activate_profile(preview, true)
		if not SummonVisualRegistryScript.request_active(_visual_request_id):
			## The request finished without a profile for this poller: it may
			## have been completed by another actor (cache now ready) or it
			## failed. Ask the registry once so a cache hit activates and a
			## terminal failure is adopted instead of re-requesting forever.
			_visual_request_id = SummonVisualRegistryScript.REQUEST_UNKNOWN
			request_visual_resources()
		return
	_visual_request_id = SummonVisualRegistryScript.REQUEST_UNKNOWN
	_activate_profile(profile, false)


## Synchronous activation is retained for deterministic test callers. The
## production _ready/_process path uses request_visual_resources() and
## _poll_visual_activation(), so imported textures use the registry's
## bounded ResourceLoader threaded path.
func activate_visual_resources() -> bool:
	var profile := SummonVisualRegistryScript.profile(summon_id)
	return _activate_profile(profile, false)


func _activate_profile(profile: Dictionary, is_streaming_preview := false) -> bool:
	if profile.is_empty():
		return false
	_animation_resources = profile
	domain_state.activate_numeric_visual_profile(profile)
	_visual_preview_active = is_streaming_preview
	_visual_profile_complete = not is_streaming_preview
	var frame_size: Vector2i = profile.get("frame_size", Vector2i.ZERO)
	var foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var actor_ground_offset: Vector2i = profile.get(
		"actor_ground_offset",
		Vector2i.ZERO
	)
	## foot_anchor is the atlas packing origin. actor_ground_offset migrates the
	## classic WIL DrawChr origin to this actor's gameplay origin; neither value
	## is a guessed per-frame visible foot or shadow center.
	_sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	_health_bar_y = _sprite.position.y + float(profile.get("stable_body_top", 0)) - 7.0
	_sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	if summon_id == "divine_beast" and profile.has("fire"):
		if _fire_sprite == null:
			_fire_sprite = Sprite2D.new()
			_fire_sprite.name = "DivineBeastFire"
			_fire_sprite.centered = false
			_fire_sprite.region_enabled = true
			_fire_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(_fire_sprite)
		_fire_sprite.texture = profile.fire
		_fire_sprite.visible = false
		var fire_foot_anchor: Vector2i = profile.get(
			"fire_foot_anchor", Vector2i.ZERO
		)
		var fire_ground_offset: Vector2i = profile.get(
			"fire_actor_ground_offset", Vector2i.ZERO
		)
		_fire_sprite.position = -Vector2(
			fire_foot_anchor + fire_ground_offset
		)
	refresh_visual_after_activation()
	_update_stealth_visual()
	_request_visual_redraw()
	return true


func refresh_visual_after_activation() -> void:
	if _animation_resources.is_empty() or _sprite == null:
		return
	_visual_state = "death" if state == SummonState.DEAD else "idle"
	_visual_direction = ArtSpec.mir2_client_direction_row(_visual_facing)
	_visual_frame = 0
	_visual_elapsed = 0.0
	_apply_visual_frame()


func _apply_visual_frame() -> void:
	if _animation_resources.is_empty() or _sprite == null:
		return
	var frame_size: Vector2i = _animation_resources.get("frame_size", Vector2i.ZERO)
	var next_texture: Texture2D = _animation_resources.get(_visual_state, null)
	var next_region := Rect2(
		_visual_frame * frame_size.x,
		_visual_direction * frame_size.y,
		frame_size.x,
		frame_size.y
	)
	if _sprite.texture == next_texture and _sprite.region_rect == next_region:
		return
	_sprite.texture = next_texture
	_sprite.region_rect = next_region
	_sprite_frame_apply_count += 1


func performance_diagnostics() -> Dictionary:
	return {
		"contract_id": SUSTAINED_FRAME_COST_CONTRACT_ID,
		"target_acquire_interval_seconds": TARGET_ACQUIRE_INTERVAL_SECONDS,
		"target_scan_count": _target_scan_count,
		"target_acquisition_contract_id": TARGET_ACQUISITION_CONTRACT_ID,
		"target_candidate_count": _target_candidate_count,
		"target_acquire_fail_closed_count": (
			_target_acquire_fail_closed_count
		),
		"target_acquire_last_rejection_reason": (
			_target_acquire_last_rejection_reason
		),
		"spatial_index_available": (
			_combat_spatial_index != null
			and is_instance_valid(_combat_spatial_index)
		),
		"custom_draw_request_count": _custom_draw_request_count,
		"sprite_frame_apply_count": _sprite_frame_apply_count,
		"visual_request_active": SummonVisualRegistryScript.request_active(
			_visual_request_id
		),
		"visual_foot_anchor_contract_id": VISUAL_FOOT_ANCHOR_CONTRACT_ID,
		"visual_profile_complete": _visual_profile_complete,
		"visual_preview_active": _visual_preview_active,
	}


func persistence_snapshot() -> Dictionary:
	return domain_state.persistence_snapshot()


func restore_persistence_snapshot(snapshot: Dictionary) -> bool:
	return domain_state.restore_persistence_snapshot(snapshot)


func level_label_layout_snapshot() -> Dictionary:
	var font := ThemeDB.fallback_font
	var display_level := clampi(summon_exp_level, 1, 7)
	var label_text := "Lv.%d" % display_level
	var label_width := font.get_string_size(
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LEVEL_LABEL_FONT_SIZE
	).x
	var descent := font.get_descent(LEVEL_LABEL_FONT_SIZE)
	var ascent := font.get_ascent(LEVEL_LABEL_FONT_SIZE)
	var baseline_y := _health_bar_y - LEVEL_LABEL_GAP_PX - descent
	return {
		"contract_id": LEVEL_LABEL_CONTRACT_ID,
		"internal_pet_level": summon_exp_level,
		"display_level": display_level,
		"text": label_text,
		"origin": Vector2(-label_width * 0.5, baseline_y),
		"bounds": Rect2(
			Vector2(-label_width * 0.5, baseline_y - ascent),
			Vector2(label_width, ascent + descent)
		),
		"health_bar_y": _health_bar_y,
	}


func reset_performance_diagnostics_for_tests() -> void:
	_target_scan_count = 0
	_target_candidate_count = 0
	_target_acquire_fail_closed_count = 0
	_target_acquire_last_rejection_reason = ""
	_custom_draw_request_count = 0
	_sprite_frame_apply_count = 0


func _visual_action_duration(action_name: String) -> float:
	return domain_state._visual_action_duration(action_name)


func _start_fire_visual() -> void:
	if _fire_sprite == null or _animation_resources.is_empty():
		return
	_fire_visual_elapsed = 0.0
	_fire_visual_remaining = (
		float(
			int(_animation_resources.get("fire_frame_count", 0))
			* int(_animation_resources.get("fire_frame_ms", 100))
		) / 1000.0
	)
	_fire_sprite.visible = _fire_visual_remaining > 0.0
	_apply_fire_frame()


func _update_fire_visual(delta: float) -> void:
	if _fire_sprite == null or _fire_visual_remaining <= 0.0:
		return
	_fire_visual_elapsed += delta
	_fire_visual_remaining = maxf(0.0, _fire_visual_remaining - delta)
	if _fire_visual_remaining <= 0.0:
		_fire_sprite.visible = false
		return
	_apply_fire_frame()


func _apply_fire_frame() -> void:
	if _fire_sprite == null:
		return
	var frame_size: Vector2i = _animation_resources.get(
		"fire_frame_size", Vector2i.ZERO
	)
	var frame_count := int(_animation_resources.get("fire_frame_count", 1))
	var frame_ms := int(_animation_resources.get("fire_frame_ms", 100))
	var frame := mini(
		frame_count - 1,
		int(floor(_fire_visual_elapsed * 1000.0 / float(maxi(1, frame_ms))))
	)
	_fire_sprite.region_rect = Rect2(
		frame * frame_size.x,
		ArtSpec.mir2_client_direction_row(_pending_attack_direction) * frame_size.y,
		frame_size.x,
		frame_size.y
	)


func ground_shadow_layout_snapshot() -> Dictionary:
	var shadow_mode := str(
		_animation_resources.get("ground_shadow_mode", "")
	)
	return {
		"contract_id": GROUND_SHADOW_CONTRACT_ID,
		"ground_shadow_mode": shadow_mode,
		"actor_ground_origin_local_px": GROUND_SHADOW_CENTER_LOCAL_PX,
		"authored_body_texture_active": (
			shadow_mode
				== SummonVisualRegistryScript.GROUND_SHADOW_MODE_AUTHORED_BODY_FRAMES
			and _sprite != null
			and _sprite.texture != null
		),
		"procedural_fallback_drawn": _should_draw_procedural_ground_shadow(),
		"vertical_scale": GROUND_SHADOW_VERTICAL_SCALE,
	}


func _should_draw_procedural_ground_shadow() -> bool:
	return (
		str(_animation_resources.get("ground_shadow_mode", ""))
			== SummonVisualRegistryScript.GROUND_SHADOW_MODE_PROCEDURAL_FALLBACK
	)


func _draw() -> void:
	var color := Color(0.88, 0.72, 0.35) if summon_name == "神兽" else Color(0.72, 0.74, 0.70)
	var radius := 21.0 if summon_name == "神兽" else 15.0
	if _should_draw_procedural_ground_shadow():
		draw_set_transform(
			GROUND_SHADOW_CENTER_LOCAL_PX,
			0.0,
			Vector2(1.0, GROUND_SHADOW_VERTICAL_SCALE)
		)
		draw_circle(
			Vector2.ZERO,
			radius,
			Color(0, 0, 0, 0.28)
		)
		draw_circle(
			Vector2.ZERO,
			radius * 0.56,
			Color(0, 0, 0, 0.56)
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sprite == null and summon_id != "divine_beast":
		draw_circle(Vector2(0, -4), radius, color)
		draw_circle(Vector2(-6, -7), 2.5, Color(0.15, 0.75, 0.35))
		draw_circle(Vector2(6, -7), 2.5, Color(0.15, 0.75, 0.35))
	draw_rect(Rect2(-22, _health_bar_y, 44, 4), Color(0.10, 0.03, 0.03, 0.9))
	draw_rect(
		Rect2(
			-22,
			_health_bar_y,
			44.0 * float(current_hp) / float(maxi(1, max_hp)),
			4
		),
		Color(0.22, 0.72, 0.25)
	)
	var level_layout := level_label_layout_snapshot()
	var level_font := ThemeDB.fallback_font
	var level_origin: Vector2 = level_layout.get("origin", Vector2.ZERO)
	var level_text := str(level_layout.get("text", ""))
	var level_bounds: Rect2 = level_layout.get("bounds", Rect2())
	var level_width := level_bounds.size.x
	draw_string_outline(
		level_font,
		level_origin,
		level_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		level_width,
		LEVEL_LABEL_FONT_SIZE,
		3,
		Color(0.0, 0.0, 0.0, 0.9)
	)
	draw_string(
		level_font,
		level_origin,
		level_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		level_width,
		LEVEL_LABEL_FONT_SIZE,
		Color(1.0, 0.9, 0.35)
	)
	var buff_hints := _buff_hint_lines()
	if not buff_hints.is_empty():
		var font := ThemeDB.fallback_font
		var hint_y := _health_bar_y + BUFF_HINT_OFFSET_Y
		for line: String in buff_hints:
			var line_width := font.get_string_size(
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				BUFF_HINT_FONT_SIZE
			).x
			var hint_origin := Vector2(-line_width * 0.5, hint_y)
			draw_string_outline(
				font,
				hint_origin,
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				line_width,
				BUFF_HINT_FONT_SIZE,
				3,
				Color(0.0, 0.0, 0.0, 0.85)
			)
			draw_string(
				font,
				hint_origin,
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				line_width,
				BUFF_HINT_FONT_SIZE,
				Color(0.95, 0.95, 0.72)
			)
			hint_y += BUFF_HINT_LINE_SPACING
