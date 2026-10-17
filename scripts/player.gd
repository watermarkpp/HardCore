class_name PlayerCharacter
extends CharacterBody2D

signal passive_wakeup_changed()

const PlayerActorModelScript := preload("res://scripts/gameplay/actors/player_actor_model.gd")
const LegacyActorPortsScript := preload("res://scripts/gameplay/actors/player_legacy_actor_ports.gd")
var domain_model := PlayerActorModelScript.new()

const CombatActionStateScript := preload("res://scripts/gameplay/actors/player_combat_action_state.gd")
var combat_actions: CombatActionStateScript:
	get: return domain_model.combat_actions
	set(value): domain_model.combat_actions = value

const DamageLedgerObserverScript := preload("res://scripts/damage_ledger_observer.gd")
# Explicit test-only seam; the observer never controls gameplay writes.
var test_damage_write_hook: Callable:
	get: return domain_model.test_damage_write_hook
	set(value): domain_model.test_damage_write_hook = value
const PlayerGroundRuntimeDiagnosticOverlayScript := preload(
	"res://scripts/player_ground_runtime_diagnostic_overlay.gd"
)
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillResourceServiceScript := preload(
	"res://scripts/skills/skill_resource_service.gd"
)
const SkillVisibilityPolicyScript := preload(
	"res://scripts/skills/skill_visibility_policy.gd"
)
const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const CombatReleaseGeometryScript := preload(
	"res://scripts/skills/combat_release_geometry.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const LocomotionDirections := preload("res://scripts/monster_neighbor_step_policy.gd")
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const CasterSkillVisualRegistryScript := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)

const PlayerVisualScript := preload("res://scripts/player_visual.gd")
const PlayerHealthBarScript := preload("res://scripts/player_health_bar.gd")
const RelicSynthesisRulesScript := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const MonsterSourcePoisonStateScript := preload("res://scripts/monster_source_poison_state.gd")
const DIRECT_SPELL_DAMAGE_RUNTIME_ID := "player.direct_spell_damage.openmir2.v1"
const SOUL_FIRE_TALISMAN_LAUNCH_TIMING_CONTRACT_ID := (
	"skills.taoist.soul_fire_talisman.body_release_frame_launch.v1"
)
const MAGIC_SHIELD_CAPACITY_CONTRACT_ID := (
	"skills.wizard.magic_shield.absorption_capacity.v1"
)
const MAGIC_SHIELD_AUTO_REFRESH_RATIO := 0.20
const WARRIOR_STATE_SKILL_IDS = PlayerActorModelScript.WARRIOR_STATE_SKILL_IDS
const WALK_MOVE_SPEED_GU_PER_SEC = PlayerActorModelScript.WALK_MOVE_SPEED_GU_PER_SEC
const WALK_TO_RUN_DISTANCE_GU = PlayerActorModelScript.WALK_TO_RUN_DISTANCE_GU
const LOCOMOTION_WALK := "walk"
const LOCOMOTION_RUN = PlayerActorModelScript.LOCOMOTION_RUN

# GameOfMir server evidence:
# - M2Server/ObjBase.pas RM_STRUCK only records m_dwStruckTick when nPower > 0.
# - ClientWalkXY/ClientRunXY call CheckActionStatus before moving.
# - CheckActionStatus rejects the action while dwStruckTime has not elapsed.
# - M2Server/Mir200/!Setup.txt configures StruckTime=100 (milliseconds).
# That source identifies itself as a modified 1.5 build, not an exact 1.76 source.
# HardCore keeps source evidence and its custom balance values in ProfessionRules.

signal stats_changed(current_hp: int, max_hp: int)
signal attack_requested(origin: Vector2, direction: Vector2, damage: int)
signal skill_requested(skill_name: String, origin: Vector2, direction: Vector2, damage: int)
signal skill_cast_started(stable_skill_id: String)
signal warrior_skill_state_changed(skill_name: String, enabled: bool, message: String)
signal resources_changed(current_hp: int, max_hp: int, current_mp: int, max_mp: int)
## R2: fired once when a potion-granted combat buff (ac/mac) fully expires, so
## the central notice layer can report the end of the effect exactly once.
signal potion_buff_expired(kind: String)
signal movement_performed(position: Vector2, facing: Vector2)
signal death_requested

@export var move_speed_gu_per_sec: float = (
	CombatUnitLegacyAdapterScript.PLAYER_MOVE_SPEED_GU_PER_SEC
):
	get: return domain_model.move_speed_gu_per_sec
	set(value): domain_model.move_speed_gu_per_sec = value
@export var max_hp: int = 120:
	get: return domain_model.max_hp
	set(value): domain_model.max_hp = value
@export var attack_min: int = 2:
	get: return domain_model.attack_min
	set(value): domain_model.attack_min = value
@export var attack_max: int = 5:
	get: return domain_model.attack_max
	set(value): domain_model.attack_max = value
@export var attack_cooldown: float = 0.9:
	get: return domain_model.attack_cooldown
	set(value): domain_model.attack_cooldown = value
@export var attack_animation_duration: float = 0.51:
	get: return domain_model.attack_animation_duration
	set(value): domain_model.attack_animation_duration = value
@export var attack_hit_windup: float = 0.17:
	get: return domain_model.attack_hit_windup
	set(value): domain_model.attack_hit_windup = value

var current_hp: int:
	get: return domain_model.current_hp
	set(value): domain_model.current_hp = value
var max_mp: int:
	get: return domain_model.max_mp
	set(value): domain_model.max_mp = value
var current_mp: int:
	get: return domain_model.current_mp
	set(value): domain_model.current_mp = value
var _badge_recovery_elapsed: float:
	get: return domain_model._badge_recovery_elapsed
	set(value): domain_model._badge_recovery_elapsed = value
var _badge_recovery_item_id: int:
	get: return domain_model._badge_recovery_item_id
	set(value): domain_model._badge_recovery_item_id = value
var _badge_recovery_effect: String:
	get: return domain_model._badge_recovery_effect
	set(value): domain_model._badge_recovery_effect = value
var _badge_recovery_equipment_snapshot: Dictionary:
	get: return domain_model._badge_recovery_equipment_snapshot
	set(value): domain_model._badge_recovery_equipment_snapshot = value
var defense_min: int:
	get: return domain_model.defense_min
	set(value): domain_model.defense_min = value
var defense_max: int:
	get: return domain_model.defense_max
	set(value): domain_model.defense_max = value
var damage_reduction: float:
	get: return domain_model.damage_reduction
	set(value): domain_model.damage_reduction = value
var shield_time: float:
	get: return domain_model.shield_time
	set(value): domain_model.shield_time = value
var shield_initial_duration: float:
	get: return domain_model.shield_initial_duration
	set(value): domain_model.shield_initial_duration = value
var shield_capacity: float:
	get: return domain_model.shield_capacity
	set(value): domain_model.shield_capacity = value
var shield_capacity_max: float:
	get: return domain_model.shield_capacity_max
	set(value): domain_model.shield_capacity_max = value
var stealth_time: float:
	get: return domain_model.stealth_time
	set(value): domain_model.stealth_time = value
## Runtime stealth break latch. Equipment-derived stealth remains registered in
## PlayerState, but an attack/skill submission suppresses its visibility until
## a new runtime stealth application explicitly refreshes the state.
var _stealth_break_override: bool:
	get: return domain_model._stealth_break_override
	set(value): domain_model._stealth_break_override = value
var _equipment_stealth_active: bool:
	get: return domain_model._equipment_stealth_active
	set(value): domain_model._equipment_stealth_active = value
var defense_buff: int:
	get: return domain_model.defense_buff
	set(value): domain_model.defense_buff = value
var defense_buff_time: float:
	get: return domain_model.defense_buff_time
	set(value): domain_model.defense_buff_time = value
var mac_buff: int:
	get: return domain_model.mac_buff
	set(value): domain_model.mac_buff = value
var mac_buff_time: float:
	get: return domain_model.mac_buff_time
	set(value): domain_model.mac_buff_time = value
var status_buff_started_at: Dictionary:
	get: return domain_model.status_buff_started_at
	set(value): domain_model.status_buff_started_at = value
var control_time: float:
	get: return domain_model.control_time
	set(value): domain_model.control_time = value
var poison_time: float:
	get: return domain_model.poison_time
	set(value): domain_model.poison_time = value
var _monster_source_poison: RefCounted:
	get: return domain_model._monster_source_poison
	set(value): domain_model._monster_source_poison = value
var poison_damage: int:
	get: return domain_model.poison_damage
	set(value): domain_model.poison_damage = value
var touch_vector: Vector2:
	get: return domain_model.touch_vector
	set(value): domain_model.touch_vector = value
var facing: Vector2:
	get: return domain_model.facing
	set(value): domain_model.facing = value
var _attack_timer: float:
	get: return combat_actions.attack_timer
	set(value): combat_actions.attack_timer = value
var _attack_action_timer: float:
	get: return combat_actions.action_timer
	set(value): combat_actions.action_timer = value
var _movement_visual_lock_timer: float:
	get: return combat_actions.movement_visual_lock_timer
	set(value): combat_actions.movement_visual_lock_timer = value
var _skill_cooldown_remaining: Dictionary:
	get: return combat_actions.skill_cooldowns
	set(value): combat_actions.skill_cooldowns = value
var _struck_lock_remaining: float:
	get: return combat_actions.struck_lock_remaining
	set(value): combat_actions.struck_lock_remaining = value
var _struck_reaction_lock_remaining: float:
	get: return combat_actions.struck_reaction_lock_remaining
	set(value): combat_actions.struck_reaction_lock_remaining = value
var _queued_struck_reaction: bool:
	get: return combat_actions.queued_struck_reaction
	set(value): combat_actions.queued_struck_reaction = value
## Protection begins when the hit presentation actually starts. Damage still
## applies during the window, but it cannot restart the reaction, refresh the
## 100ms action lock, or create another cooldown pause.
const STRUCK_PROTECTION_SECONDS := CombatActionStateScript.STRUCK_PROTECTION_SECONDS
var _struck_protection_remaining: float:
	get: return combat_actions.struck_protection_remaining
	set(value): combat_actions.struck_protection_remaining = value
## Cooldown-only pause owned by the actual player hit presentation.  This is
## deliberately separate from the 100ms server action lock and from the
## queued-reaction flag: an accepted attack/cast must finish before this clock
## starts, while the hit animation itself pauses attack/skill cooldowns.
var _struck_cooldown_pause_remaining: float:
	get: return combat_actions.struck_cooldown_pause_remaining
	set(value): combat_actions.struck_cooldown_pause_remaining = value
var _rng: RandomNumberGenerator:
	get: return domain_model._rng
	set(value): domain_model._rng = value
var visual: Node2D
var health_bar: PlayerHealthBar
var thrusting_enabled: bool:
	get: return domain_model.thrusting_enabled
	set(value): domain_model.thrusting_enabled = value
var half_moon_enabled: bool:
	get: return domain_model.half_moon_enabled
	set(value): domain_model.half_moon_enabled = value
var fire_sword_enabled: bool:
	get: return domain_model.fire_sword_enabled
	set(value): domain_model.fire_sword_enabled = value
# Read-only presentation mirror; GameRoot owns charge creation, expiry, and consumption.
var _fire_sword_charge_expires_at_ms: int:
	get: return domain_model._fire_sword_charge_expires_at_ms
	set(value): domain_model._fire_sword_charge_expires_at_ms = value
var _pending_attack_context: Dictionary:
	get: return domain_model._pending_attack_context
	set(value): domain_model._pending_attack_context = value
var _pending_skill_context: Dictionary:
	get: return domain_model._pending_skill_context
	set(value): domain_model._pending_skill_context = value
var _combat_action_sequence: int:
	get: return combat_actions.action_sequence
	set(value): combat_actions.action_sequence = value
var _pending_combat_action_id: int:
	get: return combat_actions.pending_action_id
	set(value): combat_actions.pending_action_id = value
var _pending_combat_action_active: bool:
	get: return combat_actions.pending_action_active
	set(value): combat_actions.pending_action_active = value
var _pending_combat_action_committed: bool:
	get: return combat_actions.pending_action_committed
	set(value): combat_actions.pending_action_committed = value
# RV14-01: lifecycle identity frozen when the action is accepted. A delayed
# release carries the epoch it was admitted under; transitions, formal death
# and leaving the tree all advance the epoch, which voids stale releases even
# when the actor is alive and back inside the tree by the time the timer fires.
var _pending_combat_action_epoch: int:
	get: return combat_actions.pending_action_epoch
	set(value): combat_actions.pending_action_epoch = value
var _pending_combat_action_kind: String:
	get: return combat_actions.pending_action_kind
	set(value): combat_actions.pending_action_kind = value
var _accepted_release_producers: Dictionary:
	get: return domain_model._accepted_release_producers
	set(value): domain_model._accepted_release_producers = value
var _test_combat_time_ms: int:
	get: return domain_model._test_combat_time_ms
	set(value): domain_model._test_combat_time_ms = value
## Formal player action clock advanced only by the owner physics loop.
var _combat_action_time_s: float:
	get: return combat_actions.time_s
	set(value): combat_actions.time_s = value
var _last_temporary_item_buff_revision: int:
	get: return domain_model._last_temporary_item_buff_revision
	set(value): domain_model._last_temporary_item_buff_revision = value
var _last_revival_at_ms: int:
	get: return domain_model._last_revival_at_ms
	set(value): domain_model._last_revival_at_ms = value
# HC-MONSTER-COMBAT-R3 W5 (R3-06): the death lifecycle generation. Every
# formal death opens a new generation; the deferred death notification task
# captures its own generation and re-checks it after the await, so a revival
# (or a later formal death) voids the old life's pending notification.
var _death_lifecycle_generation: int:
	get: return domain_model._death_lifecycle_generation
	set(value): domain_model._death_lifecycle_generation = value
var _pending_potion_health: int:
	get: return domain_model._pending_potion_health
	set(value): domain_model._pending_potion_health = value
var _pending_potion_mana: int:
	get: return domain_model._pending_potion_mana
	set(value): domain_model._pending_potion_mana = value
var _potion_tick_remaining: float:
	get: return domain_model._potion_tick_remaining
	set(value): domain_model._potion_tick_remaining = value
var _attack_speed_tier: int:
	get: return domain_model._attack_speed_tier
	set(value): domain_model._attack_speed_tier = value
var _cast_speed_multiplier: float:
	get: return domain_model._cast_speed_multiplier
	set(value): domain_model._cast_speed_multiplier = value
var _equipment_spell_time_scale: float:
	get: return domain_model._equipment_spell_time_scale
	set(value): domain_model._equipment_spell_time_scale = value
var _dead: bool:
	get: return domain_model._dead
	set(value): domain_model._dead = value
var _combat_transition_token: String:
	get: return domain_model._combat_transition_token
	set(value): domain_model._combat_transition_token = value
var combat_epoch: int:
	get: return domain_model.combat_epoch
	set(value): domain_model.combat_epoch = value
var hc_world_skill_preflight: Callable:
	get: return domain_model.hc_world_skill_preflight
	set(value): domain_model.hc_world_skill_preflight = value
var hc_action_configuration_provider: Callable:
	get: return domain_model.hc_action_configuration_provider
	set(value): domain_model.hc_action_configuration_provider = value
var hc_melee_configuration_provider: Callable:
	get: return domain_model.hc_melee_configuration_provider
	set(value): domain_model.hc_melee_configuration_provider = value
var hc_action_configuration_identity: Callable:
	get: return domain_model.hc_action_configuration_identity
	set(value): domain_model.hc_action_configuration_identity = value
var _preflight_action_configurations: Array:
	get: return domain_model._preflight_action_configurations
	set(value): domain_model._preflight_action_configurations = value
var movement_input_active: bool:
	get: return domain_model.movement_input_active
	set(value): domain_model.movement_input_active = value
var movement_facing: Vector2:
	get: return domain_model.movement_facing
	set(value): domain_model.movement_facing = value
var actual_motion_facing: Vector2:
	get: return domain_model.actual_motion_facing
	set(value): domain_model.actual_motion_facing = value
var actual_ground_motion_gu: Vector2:
	get: return domain_model.actual_ground_motion_gu
	set(value): domain_model.actual_ground_motion_gu = value
## Gameplay locomotion state. This is driven by successful Ground GU motion,
## never by screen velocity or animation timing.
var locomotion_state: String:
	get: return domain_model.locomotion_state
	set(value): domain_model.locomotion_state = value
var locomotion_distance_gu: float:
	get: return domain_model.locomotion_distance_gu
	set(value): domain_model.locomotion_distance_gu = value
var environment_blocker: Node
var ground_runtime_diagnostic_overlay: Node2D

const FACING_DIRECTIONS = PlayerActorModelScript.FACING_DIRECTIONS


func _init() -> void:
	var legacy := LegacyActorPortsScript.new(self)
	domain_model.configure_ports({
		"profile": PlayerState, "content": GameData,
		"profession_rules": ProfessionRules, "equipment_rules": EquipmentRulesScript,
		"relic_rules": RelicSynthesisRulesScript, "warrior_rules": WarriorCombatMath,
		"combat_rules": CombatResolutionRules,
		"phase_scheduler": legacy, "lifetime": legacy, "motion": legacy,
		"presentation": legacy, "damage_observer": legacy, "status": legacy,
	})
	domain_model.configure_execution_ports({
		"input_state": legacy, "actor_lookup": legacy,
		"action_timing": CasterSkillVisualRegistryScript,
		"art_rules": preload("res://scripts/art_spec.gd"),
		"skill_data": SkillDataLoaderScript, "skill_resources": SkillResourceServiceScript,
		"skill_visibility": SkillVisibilityPolicyScript, "skill_input": SkillInputPolicyScript,
	})
	# Legacy actors retain their actual Node identity. A new S model is instead
	# bound once by ActorRegistry to its positive, manually-owned ActorHandle.
	assert(domain_model.bind_runtime_actor_id(get_instance_id()))
	domain_model.stats_changed.connect(stats_changed.emit)
	domain_model.resources_changed.connect(resources_changed.emit)
	domain_model.passive_wakeup_changed.connect(passive_wakeup_changed.emit)
	domain_model.attack_requested.connect(attack_requested.emit)
	domain_model.skill_requested.connect(skill_requested.emit)
	domain_model.skill_cast_started.connect(skill_cast_started.emit)
	domain_model.warrior_skill_state_changed.connect(warrior_skill_state_changed.emit)
	domain_model.movement_performed.connect(movement_performed.emit)
	domain_model.death_requested.connect(death_requested.emit)


func get_canonical_red_poison() -> Variant:
	return domain_model.get_canonical_red_poison()


func set_canonical_red_poison(value: Dictionary) -> void:
	domain_model.set_canonical_red_poison(value)


func approved_ground_footpoint_local_px() -> Vector2:
	if visual != null and visual.has_method("approved_ground_footpoint_in_actor_px"):
		var point: Variant = visual.call("approved_ground_footpoint_in_actor_px")
		if point is Vector2 and point.is_finite():
			return point
	return Vector2.ZERO


func approved_ground_footpoint_world_px() -> Vector2:
	return to_global(approved_ground_footpoint_local_px())


func _exit_tree() -> void:
	domain_model.on_world_exit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and domain_model != null:
		# Dispatch to the still-live model, not to this deleting Node.
		domain_model.release_profile_subscription()


func _ready() -> void:
	add_to_group("player")
	add_to_group("combat_targets")
	collision_layer = WorldSpatialRulesScript.PLAYER_LAYER
	collision_mask = WorldSpatialRulesScript.PLAYER_MASK
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	domain_model.initialize_gameplay()
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = WorldSpatialRulesScript.actor_footprint_shape_px(
		ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)
	add_child(collision)
	visual = PlayerVisualScript.new()
	visual.name = "PlayerVisual"
	visual.setup(self)
	add_child(visual)
	visual._combat_clock_s = Callable(self, "_combat_action_time_getter")
	if PlayerGroundRuntimeDiagnosticOverlayScript.enabled_for_runtime():
		ground_runtime_diagnostic_overlay = (
			PlayerGroundRuntimeDiagnosticOverlayScript.new()
		)
		ground_runtime_diagnostic_overlay.name = "GroundRuntimeDiagnosticOverlay"
		ground_runtime_diagnostic_overlay.setup(self)
		add_child(ground_runtime_diagnostic_overlay)
	health_bar = PlayerHealthBarScript.new()
	health_bar.name = "HealthBar"
	health_bar.position = ArtSpec.PLAYER_HEALTH_BAR_OFFSET
	health_bar.z_index = 20
	health_bar.setup(current_hp, max_hp)
	add_child(health_bar)
	stats_changed.connect(health_bar.set_health)
	queue_redraw()
	stats_changed.emit(current_hp, max_hp)
	resources_changed.emit(current_hp, max_hp, current_mp, max_mp)


func _physics_process(delta: float) -> void:
	var profile_started_usec := RuntimeDiagnostics.timing_start()
	domain_model.step_physics(delta)
	var elapsed_usec := RuntimeDiagnostics.timing_elapsed_usec(profile_started_usec)
	if elapsed_usec > 0:
		RuntimeDiagnostics.record_performance_max(&"player_physics_max_ms", float(elapsed_usec) / 1000.0)


func set_touch_vector(value: Vector2) -> void:
	domain_model.set_touch_vector(value)


func reset_locomotion() -> void:
	domain_model.reset_locomotion()


func locomotion_snapshot() -> Dictionary:
	return domain_model.locomotion_snapshot()


func _keyboard_movement_vector() -> Vector2:
	# Keyboard movement passes through the same GameRoot-owned gate as touch
	# input. A terminal map failure can therefore retain the existing gameplay
	# lock without leaving a keyboard-only path into an unsafe world.
	var gameplay_owner := get_parent()
	if (
		is_instance_valid(gameplay_owner)
		and gameplay_owner.has_method("gameplay_input_is_enabled")
		and not bool(gameplay_owner.call("gameplay_input_is_enabled"))
	):
		return Vector2.ZERO
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action):
			return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func set_combat_facing(direction: Vector2) -> void:
	domain_model.set_combat_facing(direction)


func can_start_attack() -> bool:
	return domain_model.can_start_attack()


func request_attack(has_combat_target := false, locked_target_instance_id := 0, configuration: RefCounted = null) -> bool:
	return domain_model.request_attack(has_combat_target, locked_target_instance_id, configuration)


func request_attack_toward(
	direction: Vector2,
	has_combat_target := false,
	locked_target_instance_id := 0,
	configuration: RefCounted = null
) -> bool:
	return domain_model.request_attack_toward(direction, has_combat_target, locked_target_instance_id, configuration)


func can_request_skill(skill_name: String, configuration: RefCounted = null) -> bool:
	return domain_model.can_request_skill(skill_name, configuration)


func request_skill(skill_name: String, locked_target_instance_id := 0, configuration: RefCounted = null) -> bool:
	return domain_model.request_skill(skill_name, locked_target_instance_id, configuration)


func _request_active_skill(skill_name: String, locked_target_instance_id := 0, configuration: RefCounted = null) -> bool:
	return domain_model._request_active_skill(skill_name, locked_target_instance_id, configuration)


func _action_configuration_current(configuration: RefCounted) -> bool:
	return domain_model._action_configuration_current(configuration)


func current_preflight_action_configuration() -> RefCounted:
	return domain_model.current_preflight_action_configuration()


func _freeze_partner_resource_context(context: Dictionary, configuration: RefCounted) -> void:
	domain_model._freeze_partner_resource_context(context, configuration)


func apply_confirmed_physical_hit_durability(damage: int, context := {}) -> Dictionary:
	return domain_model.apply_confirmed_physical_hit_durability(damage, context)


func combat_transition_is_active() -> bool:
	return domain_model.combat_transition_is_active()


func begin_combat_transition(token: String, allow_dead := false) -> bool:
	return domain_model.begin_combat_transition(token, allow_dead)


func finish_combat_transition(token: String) -> bool:
	return domain_model.finish_combat_transition(token)


func restore_level_up_resources() -> bool:
	return domain_model.restore_level_up_resources()


func take_damage(
	amount: int,
	causes_struck: bool = true,
	durability_context := {},
	force_struck_reaction := false,
	delivery_identity: Variant = null,
) -> void:
	domain_model.take_damage(amount, causes_struck, durability_context, force_struck_reaction, delivery_identity)


func _resolve_incoming_evasion(amount: int, forced_roll := -1) -> Dictionary:
	return domain_model._resolve_incoming_evasion(amount, forced_roll)


func take_ranged_damage(amount: int, causes_struck := true, force_struck_reaction := false, forced_evasion_roll := -1, delivery_identity: Variant = null) -> Dictionary:
	return domain_model.take_ranged_damage(amount, causes_struck, force_struck_reaction, forced_evasion_roll, delivery_identity)


func take_monster_mixed_damage(
	physical_raw: int,
	magic_raw: int,
	context: Dictionary,
	delivery_identity: Variant = null,
) -> Dictionary:
	return domain_model.take_monster_mixed_damage(physical_raw, magic_raw, context, delivery_identity)


func take_direct_spell_damage(
	skill_id: String,
	raw_damage: int,
	anti_magic_roll := -1,
	magic_defense_roll := -1,
	causes_struck := true,
	delivery_identity: Variant = null,
) -> Dictionary:
	return domain_model.take_direct_spell_damage(skill_id, raw_damage, anti_magic_roll, magic_defense_roll, causes_struck, delivery_identity)


func _resolve_direct_spell_magic_defense(
	_skill_id: String,
	incoming_damage: int,
	target_stats: Dictionary,
	roll_override: int,
	resolution_state: Dictionary
) -> int:
	return domain_model._resolve_direct_spell_magic_defense(_skill_id, incoming_damage, target_stats, roll_override, resolution_state)


func _commit_observed_hp_write(amount: int, damage_type: String, delivery_identity: Variant, mp_before := -1, mp_after := -1) -> void:
	domain_model._commit_observed_hp_write(amount, damage_type, delivery_identity, mp_before, mp_after)


func _apply_resolved_damage(
	amount: int,
	causes_struck: bool,
	damage_type := "physical",
	durability_context := {},
	force_struck_reaction := false,
	delivery_identity: Variant = null,
) -> void:
	domain_model._apply_resolved_damage(amount, causes_struck, damage_type, durability_context, force_struck_reaction, delivery_identity)


func complete_death_revival() -> void:
	domain_model.complete_death_revival()


func _incoming_red_poison_active(context: Dictionary) -> bool:
	return domain_model._incoming_red_poison_active(context)


func _emit_attack_after_windup(
	damage: int,
	windup: float,
	context: Dictionary,
	action_id: int,
	action_epoch: int,
	input_direction: Vector2,
	locked_target_instance_id: int
) -> void:
	domain_model._emit_attack_after_windup(damage, windup, context, action_id, action_epoch, input_direction, locked_target_instance_id)


func _emit_skill_after_windup(
	skill_name: String,
	damage: int,
	windup: float,
	action_id: int,
	action_epoch: int,
	input_direction: Vector2,
	locked_target_instance_id: int,
	track_locked_target: bool,
	configuration: RefCounted = null
) -> void:
	domain_model._emit_skill_after_windup(skill_name, damage, windup, action_id, action_epoch, input_direction, locked_target_instance_id, track_locked_target, configuration)


static func combat_release_signal_payload(
	release_geometry: Dictionary
) -> Dictionary:
	return PlayerActorModelScript.combat_release_signal_payload(release_geometry)


func _resolve_combat_release_geometry(
	input_direction: Vector2,
	locked_target_instance_id: int,
	track_locked_target: bool,
	release_facing_policy := CombatReleaseGeometryScript.FACING_POLICY_LIVE_LOCKED_TARGET
) -> Dictionary:
	return domain_model._resolve_combat_release_geometry(input_direction, locked_target_instance_id, track_locked_target, release_facing_policy)


func _begin_combat_action(action_kind: String) -> int:
	return domain_model._begin_combat_action(action_kind)


func _commit_combat_action(action_id: int) -> bool:
	return domain_model._commit_combat_action(action_id)


func _finish_combat_action(action_id: int) -> void:
	domain_model._finish_combat_action(action_id)


func _start_struck_reaction() -> void:
	domain_model._start_struck_reaction()


func _start_queued_struck_reaction() -> void:
	domain_model._start_queued_struck_reaction()


func has_pending_combat_release() -> bool:
	return domain_model.has_pending_combat_release()


func _finish_accepted_release(action_id: int, configuration: RefCounted = null) -> void:
	domain_model._finish_accepted_release(action_id, configuration)


func _close_accepted_releases() -> void:
	domain_model._close_accepted_releases()


func combat_action_snapshot() -> Dictionary:
	return domain_model.combat_action_snapshot()


func struck_reaction_snapshot() -> Dictionary:
	return domain_model.struck_reaction_snapshot()


func consume_attack_context() -> Dictionary:
	return domain_model.consume_attack_context()


func consume_skill_context() -> Dictionary:
	return domain_model.consume_skill_context()


func set_test_combat_time_ms(value: int) -> void:
	domain_model.set_test_combat_time_ms(value)


func set_combat_seed(seed_value: int) -> void:
	domain_model.set_combat_seed(seed_value)


func set_fire_sword_charge_display(expires_at_ms: int) -> void:
	domain_model.set_fire_sword_charge_display(expires_at_ms)


func skill_cooldown_remaining_ms(stable_skill_id: String) -> int:
	return domain_model.skill_cooldown_remaining_ms(stable_skill_id)


func commit_fire_sword_cooldown(configuration: RefCounted = null) -> void:
	domain_model.commit_fire_sword_cooldown(configuration)


func warrior_state_snapshot() -> Dictionary:
	return domain_model.warrior_state_snapshot()


func warrior_runtime_state_for_save() -> Dictionary:
	return domain_model.warrior_runtime_state_for_save()


func restore_warrior_runtime_state(saved_state: Dictionary) -> bool:
	return domain_model.restore_warrior_runtime_state(saved_state)


func _combat_time_ms() -> int:
	return domain_model._combat_time_ms()


func _combat_action_time_getter() -> float:
	return domain_model._combat_action_time_getter()


func _request_warrior_state_skill(skill_id: String, _level: int) -> bool:
	return domain_model._request_warrior_state_skill(skill_id, _level)


func _build_warrior_attack_context(has_combat_target := false, configuration: RefCounted = null) -> Dictionary:
	return domain_model._build_warrior_attack_context(has_combat_target, configuration)


func restore_health(amount: int) -> int:
	return domain_model.restore_health(amount)


func restore_mana(amount: int) -> void:
	domain_model.restore_mana(amount)


func _tick_badge_recovery(delta: float) -> void:
	domain_model._tick_badge_recovery(delta)


func queue_potion_restore(health_amount: int, mana_amount: int) -> void:
	domain_model.queue_potion_restore(health_amount, mana_amount)


func _process_potion_restore(delta: float) -> void:
	domain_model._process_potion_restore(delta)


func spend_mana(amount: int) -> bool:
	return domain_model.spend_mana(amount)


func apply_magic_shield(seconds: float, reduction: float) -> void:
	domain_model.apply_magic_shield(seconds, reduction)


func magic_shield_snapshot() -> Dictionary:
	return domain_model.magic_shield_snapshot()


func magic_shield_requires_refresh(
	capacity_ratio_threshold := MAGIC_SHIELD_AUTO_REFRESH_RATIO,
	expiry_lead_seconds := 0.6
) -> bool:
	return domain_model.magic_shield_requires_refresh(capacity_ratio_threshold, expiry_lead_seconds)


func apply_stealth(seconds: float) -> void:
	domain_model.apply_stealth(seconds)


func break_stealth() -> void:
	domain_model.break_stealth()


func recover_equipment_stealth_after_combat_exit() -> bool:
	return domain_model.recover_equipment_stealth_after_combat_exit()


func apply_defense_buff(seconds: float, amount: int) -> void:
	domain_model.apply_defense_buff(seconds, amount)


func apply_ac_buff(seconds: float, amount: int) -> void:
	domain_model.apply_ac_buff(seconds, amount)


func apply_mac_buff(seconds: float, amount: int) -> void:
	domain_model.apply_mac_buff(seconds, amount)


func defence_buff_snapshot() -> Dictionary:
	return domain_model.defence_buff_snapshot()


func apply_control(seconds: float) -> void:
	domain_model.apply_control(seconds)


func apply_poison(tick_damage: int, seconds: float) -> void:
	domain_model.apply_poison(tick_damage, seconds)


func apply_monster_poison(tick_damage: int, seconds: float, interval_seconds: float) -> bool:
	return domain_model.apply_monster_poison(tick_damage, seconds, interval_seconds)


## Presentation-facing accessor for the unified poison status flag. Reads both
## poison sources (legacy + monster-source) without mutating any gameplay
## state. The HUD status strip uses this to show exactly one 中毒 flag.
func poison_status_remaining() -> float:
	return domain_model.poison_status_remaining()


func _update_monster_source_poison(delta: float) -> void:
	domain_model._update_monster_source_poison(delta)


func is_stealthed() -> bool:
	return domain_model.is_stealthed()


func _draw() -> void:
	# Final MIR2 character frames already contain their own direction-aware
	# ground shadow. Drawing another ellipse at the actor origin creates two
	# separated shadows and makes the body look airborne.
	if visual == null or not visual.uses_final_art():
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.48))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if visual == null or not visual.uses_final_art():
		draw_circle(Vector2(0, -8), 17.0, Color(0.76, 0.66, 0.46))
		var profession_color: Color = {"hc.profession.warrior": Color(0.24, 0.34, 0.48), "hc.profession.wizard": Color(0.20, 0.28, 0.56), "hc.profession.taoist": Color(0.36, 0.42, 0.24)}.get(PlayerState.profession_id, Color(0.24, 0.34, 0.48))
		draw_colored_polygon(PackedVector2Array([Vector2(-17, -5), Vector2(17, -5), Vector2(13, 23), Vector2(-13, 23)]), profession_color)
		draw_line(Vector2(0, 7), facing * 27.0 + Vector2(0, 7), Color(0.92, 0.86, 0.65), 5.0)
	# Neither paralysis nor poison draws a ground ring under the character any
	# more (R1.1). Both states present as fixed-slot dots on the status marker
	# row under the overhead HP bar (see PlayerStatusMarkerStrip attached by
	# player_health_bar.gd). Gameplay timers are only read, never changed here.


func _apply_profile_stats() -> void:
	domain_model._apply_profile_stats()
