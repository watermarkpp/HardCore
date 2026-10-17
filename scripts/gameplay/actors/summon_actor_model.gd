extends "res://scripts/gameplay/actors/summon_domain_state.gd"

## Full summon gameplay authority. References to other actors are owner-local
## runtime links; only explicit ports may resolve legacy Nodes or native bodies.
## The inherited growth/support state remains the sole HP and stat storage.
signal summon_state_changed(previous_state: int, current_state: int)

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const CombatUnitLegacyAdapterScript := preload("res://scripts/skills/combat_unit_legacy_adapter.gd")
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

const REST_FORMATION_CONTRACT_ID := (
	"skills.summon.owner_formation_slots.v1"
)

const OWNER_TELEPORT_RELOCATION_CONTRACT_ID := (
	"skills.summon.owner_teleport_relocation.v1"
)

const COLLISION_INTERACTION_CONTRACT_ID := (
	"skills.summon.collision.player_pet_passthrough.v1"
)

const TARGET_ACQUIRE_INTERVAL_SECONDS := 0.25

const FORMATION_WAKE_DISTANCE_GU := 0.35

const FORMATION_SETTLE_DISTANCE_GU := 0.15

const RECALL_OFFSET_GU := (
	42.0 / CombatUnitLegacyAdapterScript.ISO_AREA_EQUIVALENT_PX_PER_GU
)

const SKELETON_ATTACK_LENGTH_GU := 1.5

const DIVINE_BEAST_ATTACK_LENGTH_GU := 3.0

const SUMMON_ATTACK_WIDTH_GU := 1.0

enum SummonState {
	FOLLOW_OWNER,
	ACQUIRE_TARGET,
	CHASE_TARGET,
	ATTACK_TARGET,
	RETURN_TO_OWNER,
	EXPIRED,
	DEAD,
}

var _owner_thread := OS.get_thread_caller_id()
var _runtime_actor_id := 0
var profile_state: Object
var profession_rules: Object
var warrior_rules: Object
var combat_rules: Object
var art_rules: Object
var actor_links: Object
var motion: Object
var lifetime: Object
var presentation: Object
var damage_observer: Object
var landing: Object
var spatial: Object
var owner_link: RefCounted
var current_target_link: RefCounted
var pending_attack_target_link: RefCounted
var _timing_profile: Dictionary = {}

var _monster_source_poison := MonsterSourcePoisonStateScript.new()

var _monster_control_remaining := 0.0

var owner_level := 1

var runtime_map_id: int = -1

var runtime_ground_gu_to_screen_position_px := Callable()

var runtime_screen_to_ground_position_px := Callable()

var _outgoing_magic_stats: Dictionary = {}

var _rest_formation_moving := false

var missing_projection_rejection_count := 0

var projection_rejection_reason := &""

var summon_name := "骷髅"

var skill_id := "taoist.summon_skeleton"

var pet_slot_index := 0

var summon_level := 0

var summon_count := 1

var attack_type := "physical"

var monster_level := 1

var lifetime_seconds := 864000.0

var remaining_lifetime := 864000.0

var attack_range_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(48.0)
)

var aggro_radius_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(330.0)
)

var combat_radius_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(15.0)
)

var collision_radius_px := 15.0

var leash_range_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(560.0)
)

var teleport_range_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(900.0)
)

var follow_distance_gu := (
	CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(75.0)
)

var actual_ground_motion_gu := Vector2.ZERO

var owner_death_rule := "expire"

var reject_when_owner_has_slave := true

var recall_existing_on_create_failure := false

var state := SummonState.FOLLOW_OWNER

var owner_teleport_pending := false

var _owner_teleport_saved_collision_layer := 0

var _owner_teleport_saved_collision_mask := 0

var last_attack_type := ""

var summon_release_id := ""

var summon_spawn_footprint_snapshot: Dictionary = {}

var last_attack_footprint_snapshot: Dictionary = {}

var last_attack_relation := ""

var _attack_timer := 0.0

var _attack_release_sequence := 0

var _rng := RandomNumberGenerator.new()

var _visual_profile_complete := false

var _visual_preview_active := false

var _visual_state := "idle"

var _visual_direction := 0

var _visual_frame := 0

var _visual_elapsed := 0.0

var _visual_facing := Vector2.DOWN

var _attack_visual_remaining := 0.0

var _hit_visual_remaining := 0.0

var _death_visual_remaining := 0.0

var _pending_attack_snapshot: Dictionary = {}

var _pending_attack_release_remaining := 0.0

var _pending_attack_direction := Vector2.DOWN

var _target_acquire_remaining := 0.0

var _target_scan_count := 0

var _target_candidate_count := 0

var _target_acquire_fail_closed_count := 0

var _target_acquire_last_rejection_reason := ""

func _init(rules: Object, ranks: Object, initial_speed: float) -> void:
	super(rules, ranks, initial_speed)


func configure_ports(bindings: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	profile_state = bindings["profile"]
	assert(profile_state != null)
	profession_rules = bindings["profession_rules"]
	assert(profession_rules != null)
	warrior_rules = bindings["warrior_rules"]
	assert(warrior_rules != null)
	combat_rules = bindings["combat_rules"]
	assert(combat_rules != null)
	art_rules = bindings["art_rules"]
	assert(art_rules != null)
	actor_links = bindings["actor_links"]
	assert(actor_links != null)
	motion = bindings["motion"]
	assert(motion != null)
	lifetime = bindings["lifetime"]
	assert(lifetime != null)
	presentation = bindings["presentation"]
	assert(presentation != null)
	damage_observer = bindings["damage_observer"]
	assert(damage_observer != null)
	landing = bindings["landing"]
	assert(landing != null)
	spatial = bindings["spatial"]
	assert(spatial != null)


func bind_runtime_actor_id(value: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if value <= 0 or (_runtime_actor_id != 0 and _runtime_actor_id != value):
		return false
	_runtime_actor_id = value
	return true


func runtime_actor_id() -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	assert(_runtime_actor_id > 0, "summon actor identity must be bound by its registry/legacy adapter")
	return _runtime_actor_id


func initialize_gameplay() -> void:
	_rng.randomize()


func activate_numeric_visual_profile(source: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	# Capture only the active profile's numerical timing. Texture Resources never
	# enter the model. Keep profile presence distinct from missing timing keys.
	if source.is_empty():
		_timing_profile = {}
		return
	var counts: Dictionary = source.get("frame_counts", {}).duplicate(true)
	var periods: Dictionary = source.get("frame_ms", {}).duplicate(true)
	for key: Variant in counts:
		assert((key is String or key is StringName) and (counts[key] is int or counts[key] is float))
	for key: Variant in periods:
		assert((key is String or key is StringName) and (periods[key] is int or periods[key] is float))
	counts.make_read_only()
	periods.make_read_only()
	_timing_profile = {"frame_counts":counts,"frame_ms":periods,"attack_release_ms":source.get("attack_release_ms",-1)}
	assert(_timing_profile.attack_release_ms is int or _timing_profile.attack_release_ms is float)
	_timing_profile.make_read_only()


func gain_growth_from_kill(killed_monster_level: int) -> bool:
	if not super.gain_growth_from_kill(killed_monster_level):
		return false
	presentation.redraw()
	return true


func setup(
	player: RefCounted,
	display_name: String,
	power: int,
	learned_level := -1,
	source_skill_id := "",
	owner_level_value := -1,
	maximum_pet_level_value := -1
) -> void:
	owner_link = player
	var inferred_skill_id := source_skill_id
	if inferred_skill_id.is_empty():
		inferred_skill_id = "taoist.summon_divine_beast" if display_name == "神兽" else "taoist.summon_skeleton"
	var inferred_level := learned_level
	if inferred_level < 0 and profile_state != null:
		inferred_level = profile_state.effective_skill_level(profession_rules.skill_display_name(inferred_skill_id))
	var inferred_owner_level := owner_level_value
	if inferred_owner_level < 1 and profile_state != null:
		inferred_owner_level = profile_state.level
	owner_level = maxi(1, inferred_owner_level)
	var profile = summon_rules.summon_profile(
		inferred_skill_id,
		maxi(0, inferred_level),
		owner_level,
		maxi(1, power)
	)
	skill_id = inferred_skill_id
	effective_skill_rank = maxi(0, inferred_level)
	divine_damage_more = rank_rules.more_multiplier(effective_skill_rank) if inferred_skill_id == "taoist.summon_divine_beast" else 1.0
	skill_level = int(profile.get("skill_level", 0))
	summon_level = int(profile.get("summon_level", skill_level))
	summon_exp_level = int(profile.get("summon_exp_level", skill_level))
	maximum_pet_level = (
		maximum_pet_level_value
		if maximum_pet_level_value >= 0
		else int(profile.get("max_pet_level", 1))
	)
	maximum_pet_level = clampi(maximum_pet_level, summon_exp_level, 7)
	pet_growth_exp = int(profile.get("pet_growth_exp", 0))
	summon_count = int(profile.get("summon_count", 1))
	summon_id = str(profile.get("summon_id", "skeleton"))
	summon_name = str(profile.get("display_name", display_name))
	attack_type = str(profile.get("attack_type", "physical"))
	monster_level = int(profile.get("monster_level", 1))
	max_hp = int(profile.get("max_hp", 60 + power * 12))
	current_hp = max_hp
	attack_min = int(profile.get("attack_min", maxi(1, int(power / 2))))
	attack_max = int(profile.get("attack_max", maxi(attack_min, power)))
	ac_min = int(profile.get("ac_min", 0))
	ac_max = int(profile.get("ac_max", ac_min))
	mac_min = int(profile.get("mac_min", 0))
	mac_max = int(profile.get("mac_max", mac_min))
	accuracy = int(profile.get("accuracy", 1))
	agility = int(profile.get("agility", 1))
	name_color_index = summon_rules.summon_name_color_index(summon_exp_level)
	attack_interval = float(profile.get("attack_interval", 1.25))
	lifetime_seconds = float(profile.get("lifetime_seconds", 864000.0))
	remaining_lifetime = lifetime_seconds
	move_speed_gu_per_sec = float(profile.get(
		"move_speed_gu_per_sec",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			155.0 if summon_id == "divine_beast" else 135.0
		)
	))
	## User-authored combat geometry supersedes the legacy screen-pixel range:
	## skeleton uses the warrior-normal 1.5 GU reach and divine beast uses a
	## 3 GU by 1 GU directed footprint.
	attack_range_gu = _attack_effect_length_gu()
	aggro_radius_gu = float(profile.get(
		"aggro_radius_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			380.0 if summon_id == "divine_beast" else 330.0
		)
	))
	leash_range_gu = float(profile.get(
		"leash_range_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			560.0
		)
	))
	teleport_range_gu = float(profile.get(
		"teleport_range_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			900.0
		)
	))
	follow_distance_gu = float(profile.get(
		"follow_distance_gu",
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			75.0
		)
	))
	owner_death_rule = str(profile.get("owner_death_rule", "expire"))
	reject_when_owner_has_slave = bool(profile.get("reject_when_owner_has_slave", true))
	recall_existing_on_create_failure = bool(profile.get("recall_existing_on_create_failure", false))
	state = SummonState.FOLLOW_OWNER
	presentation.reset_audio_state()


func configure_spawn_release_footprint(source_release_id: String) -> void:
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		# FREEZE-P0.1: mapped summon without a projection must not create a
		# formal spawn snapshot at fake/delta coordinates.
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		summon_spawn_footprint_snapshot = {}
		return
	summon_release_id = (
		source_release_id
		if not source_release_id.is_empty()
		else "%s:summon:%d" % [skill_id, runtime_actor_id()]
	)
	var spawn_combat_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			collision_radius_px
		)
	)
	var spawn_center_ground_gu := (
		_runtime_screen_to_ground_position(motion.position_screen_px())
	)
	summon_spawn_footprint_snapshot = (
		SkillFootprintSnapshotScript.create_target_footprint(
			skill_id,
			summon_release_id,
			spawn_center_ground_gu,
			spawn_combat_radius_gu,
			runtime_actor_id(),
			_snapshot_coordinate_context(spawn_center_ground_gu)
		)
	)


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


func relocate_after_owner_teleport(final_position_px: Vector2) -> Dictionary:
	## The integration owner supplies a position already selected by the
	## canonical map/obstacle-aware summon spawn plan. This method is deliberately
	## not a placement search: it only cancels stale combat/motion state and
	## commits the final legal position after same-map or cross-map travel.
	## The caller must configure the current map projection before calling this
	## method; runtime_map_id is part of target validation and spatial queries.
	if not final_position_px.is_finite():
		return {
			"contract_id": OWNER_TELEPORT_RELOCATION_CONTRACT_ID,
			"relocated": false,
			"reason": "non_finite_final_position",
		}
	if state in [SummonState.DEAD, SummonState.EXPIRED]:
		return {
			"contract_id": OWNER_TELEPORT_RELOCATION_CONTRACT_ID,
			"relocated": false,
			"reason": "summon_not_active",
		}
	var had_target = actor_links.actor_is_present(current_target_link)
	var had_pending_attack := pending_attack_target_link != null
	_reset_combat_after_owner_teleport()
	motion.set_position_screen_px(final_position_px)
	if _runtime_motion_faulted():
		return {"ok":false,"reason":"actor_native_motion_failed"}
	if owner_teleport_pending:
		motion.set_collision_layer(_owner_teleport_saved_collision_layer)
		if _runtime_motion_faulted():
			return {"ok":false,"reason":"actor_native_motion_failed"}
		motion.set_collision_mask(_owner_teleport_saved_collision_mask)
		if _runtime_motion_faulted():
			return {"ok":false,"reason":"actor_native_motion_failed"}
		owner_teleport_pending = false
		presentation.set_visible(true)
	passive_wakeup_changed.emit()
	return {
		"contract_id": OWNER_TELEPORT_RELOCATION_CONTRACT_ID,
		"relocated": true,
		"final_position_px": final_position_px,
		"target_cleared": had_target,
		"pending_attack_cleared": had_pending_attack,
		"motion_cleared": true,
		"state": state_name(),
	}


func defer_owner_teleport_relocation() -> void:
	# A full landing has no legal body slot nearby. Keep HP and lifetime, but
	# remove the old-map body and stale attack until the owner reaches new ground.
	if state in [SummonState.DEAD, SummonState.EXPIRED]:
		return
	if not owner_teleport_pending:
		_owner_teleport_saved_collision_layer = motion.collision_layer()
		_owner_teleport_saved_collision_mask = motion.collision_mask()
	owner_teleport_pending = true
	_reset_combat_after_owner_teleport()
	motion.set_collision_layer(0)
	if _runtime_motion_faulted():
		return
	motion.set_collision_mask(0)
	if _runtime_motion_faulted():
		return
	presentation.set_visible(false)
	passive_wakeup_changed.emit()


func _reset_combat_after_owner_teleport() -> void:
	current_target_link = null
	_clear_pending_attack()
	_target_acquire_remaining = TARGET_ACQUIRE_INTERVAL_SECONDS
	_rest_formation_moving = false
	_attack_timer = 0.0
	_attack_visual_remaining = 0.0
	presentation.reset_fire_visual()
	motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
	if _runtime_motion_faulted():
		return
	actual_ground_motion_gu = Vector2.ZERO
	_set_state(SummonState.FOLLOW_OWNER)
	_visual_state = "idle"
	_visual_elapsed = 0.0
	presentation.redraw()


func projection_ready() -> bool:
	if runtime_map_id < 0:
		return true
	return runtime_screen_to_ground_position_px.is_valid()


func _snapshot_coordinate_context(origin_ground_gu: Vector2) -> Dictionary:
	return SkillFootprintSnapshotScript.make_absolute_runtime_context(
		runtime_map_id,
		origin_ground_gu,
		origin_ground_gu,
		runtime_ground_gu_to_screen_position_px
	)


func step_process(delta: float) -> void:
	update_support_buff_timers(delta)
	presentation.update_stealth_visual()
	presentation.refresh_buff_redraw_if_needed()
	_attack_visual_remaining = maxf(0.0, _attack_visual_remaining - delta)
	_hit_visual_remaining = maxf(0.0, _hit_visual_remaining - delta)
	presentation.update_fire_visual(delta)
	if state == SummonState.DEAD:
		_death_visual_remaining = maxf(0.0, _death_visual_remaining - delta)
		if _death_visual_remaining <= 0.0:
			lifetime.request_retirement()
			return
	if not _visual_profile_complete:
		## The registry can finalize at most one imported texture per poll. Polling
		## each frame makes the idle-first preview visible as soon as its formal
		## Texture2D import completes without adding a blocking load.
		presentation.poll_visual_activation()
	if _timing_profile.is_empty():
		return
	var next_visual_state := "idle"
	if state == SummonState.DEAD:
		next_visual_state = "death"
	elif _hit_visual_remaining > 0.0:
		next_visual_state = "hit"
	elif _attack_visual_remaining > 0.0:
		next_visual_state = "attack"
	elif motion.velocity_screen_px_per_sec().length_squared() > 25.0:
		next_visual_state = "walk"
	if next_visual_state != _visual_state:
		_visual_state = next_visual_state
		_visual_elapsed = 0.0
	else:
		_visual_elapsed += delta
	if pending_attack_target_link != null:
		_visual_facing = _pending_attack_direction
	elif motion.velocity_screen_px_per_sec().length_squared() > 25.0:
		_visual_facing = motion.velocity_screen_px_per_sec().normalized()
	elif actor_links.actor_is_present(current_target_link):
		var target_offset = actor_links.actor_position_screen_px(current_target_link) - motion.position_screen_px()
		if target_offset.length_squared() > 0.001:
			_visual_facing = target_offset.normalized()
	elif actor_links.actor_is_present(owner_link) and actor_links.facing(owner_link).length_squared() > 0.001:
		_visual_facing = actor_links.facing(owner_link).normalized()
	_visual_direction = art_rules.mir2_client_direction_row(_visual_facing)
	var frame_count := int(_timing_profile.get("frame_counts", {}).get(_visual_state, 1))
	var frame_ms := int(_timing_profile.get("frame_ms", {}).get(_visual_state, 100))
	if _visual_state in ["attack", "hit", "death"]:
		_visual_frame = mini(frame_count - 1, int(floor(_visual_elapsed * 1000.0 / float(maxi(1, frame_ms)))))
	else:
		_visual_frame = int(floor(_visual_elapsed * 1000.0 / float(maxi(1, frame_ms)))) % frame_count
	presentation.apply_visual_frame(_visual_state, _visual_direction, _visual_frame)


func step_physics(delta: float) -> void:
	_update_monster_source_poison(delta)
	if state == SummonState.DEAD:
		motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
		if _runtime_motion_faulted():
			return
		actual_ground_motion_gu = Vector2.ZERO
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_target_acquire_remaining = maxf(
		0.0,
		_target_acquire_remaining - delta
	)
	_update_pending_attack(delta)
	if _runtime_motion_faulted(): return
	remaining_lifetime = maxf(0.0, remaining_lifetime - delta)
	if remaining_lifetime <= 0.0:
		_expire()
		return
	if not actor_links.actor_is_present(owner_link) or actor_links.current_hp(owner_link) <= 0:
		_expire()
		return
	if owner_teleport_pending:
		motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
		if _runtime_motion_faulted():
			return
		actual_ground_motion_gu = Vector2.ZERO
		return
	if _monster_control_remaining > 0.0:
		_monster_control_remaining = maxf(0.0, _monster_control_remaining - delta)
		motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
		if _runtime_motion_faulted():
			return
		actual_ground_motion_gu = Vector2.ZERO
		return
	var owner_distance_gu := distance_gu_to_screen_position_px(
		actor_links.actor_position_screen_px(owner_link)
	)
	if owner_distance_gu >= teleport_range_gu:
		_set_state(SummonState.RETURN_TO_OWNER)
		var landing_plan := _canonical_owner_teleport_landing_plan()
		if _runtime_motion_faulted(): return
		if not bool(landing_plan.get("valid", false)):
			# A remote owner never authorizes a raw position write.  Keep the
			# existing body hidden/pending until the canonical map-aware planner
			# finds a legal footprint, exactly as map-arrival relocation does.
			if bool(landing_plan.get("defer_allowed", false)):
				_defer_owner_follow_landing()
			motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
			if _runtime_motion_faulted():
				return
			actual_ground_motion_gu = Vector2.ZERO
			return
		var landing_position: Variant = landing_plan.get("position_screen_px")
		if not landing_position is Vector2 or not (landing_position as Vector2).is_finite():
			_defer_owner_follow_landing()
			return
		# Preserve the established follow action/timing; only its placement now
		# requires a legal footprint. Accepted attacks are not reset by following.
		motion.set_position_screen_px(landing_position as Vector2)
		if _runtime_motion_faulted():
			return
		passive_wakeup_changed.emit()
		_rest_formation_moving = false
		motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
		if _runtime_motion_faulted():
			return
		actual_ground_motion_gu = Vector2.ZERO
		return
	if (
		not actor_links.actor_is_present(current_target_link)
		or actor_links.is_retiring(current_target_link)
		or actor_links.current_hp(current_target_link) <= 0
		or not _enemy_accepts_external_attack(current_target_link)
	):
		current_target_link = null
		if _target_acquire_remaining <= 0.0:
			if state not in [SummonState.FOLLOW_OWNER, SummonState.RETURN_TO_OWNER]:
				_set_state(SummonState.ACQUIRE_TARGET)
			current_target_link = _nearest_enemy()
			_target_acquire_remaining = TARGET_ACQUIRE_INTERVAL_SECONDS
	var enemy := current_target_link
	if (
		enemy != null
		and _distance_gu_between_screen_positions_px(
			actor_links.actor_position_screen_px(enemy), actor_links.actor_position_screen_px(owner_link)
		) > leash_range_gu
	):
		current_target_link = null
		_target_acquire_remaining = 0.0
		enemy = null
	if enemy != null:
		var offset_screen_px = actor_links.actor_position_screen_px(enemy) - motion.position_screen_px()
		if _target_within_attack_geometry(enemy):
			_set_state(SummonState.ATTACK_TARGET)
			motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
			if _runtime_motion_faulted():
				return
			if _attack_timer <= 0.0 and pending_attack_target_link == null:
				_begin_attack(enemy)
		else:
			_set_state(SummonState.CHASE_TARGET)
			motion.set_velocity_screen_px_per_sec(_screen_velocity_toward_delta_px(offset_screen_px))
			if _runtime_motion_faulted():
				return
	else:
		var rest_target_screen_px := _owner_formation_anchor_screen_px()
		var rest_offset_screen_px = rest_target_screen_px - motion.position_screen_px()
		var rest_distance_gu := distance_gu_to_screen_position_px(
			rest_target_screen_px
		)
		if _rest_formation_moving:
			if rest_distance_gu <= FORMATION_SETTLE_DISTANCE_GU:
				_rest_formation_moving = false
		elif rest_distance_gu >= FORMATION_WAKE_DISTANCE_GU:
			_rest_formation_moving = true
		if _rest_formation_moving:
			_set_state(SummonState.RETURN_TO_OWNER)
			motion.set_velocity_screen_px_per_sec(_screen_velocity_toward_arrival_delta_px(
				rest_offset_screen_px,
				delta
			))
			if _runtime_motion_faulted():
				return
		else:
			_set_state(SummonState.FOLLOW_OWNER)
			motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
			if _runtime_motion_faulted():
				return
	var position_before_move_px = motion.position_screen_px()
	motion.move_and_slide()
	if _runtime_motion_faulted():
		return
	actual_ground_motion_gu = (
		GroundUnitSpaceScript.actual_ground_motion_gu_from_screen_positions(
			position_before_move_px,
			motion.position_screen_px()
		)
	)

	if not actual_ground_motion_gu.is_zero_approx():
		passive_wakeup_changed.emit()


func _canonical_owner_teleport_landing_plan() -> Dictionary:
	return landing.canonical_follow_landing_plan()


func _defer_owner_follow_landing() -> void:
	var authority: RefCounted = landing.capture_follow_landing_authority()
	if authority == null:
		return
	defer_owner_teleport_relocation()
	landing.register_pending_arrival(authority)


func _begin_attack(enemy: RefCounted) -> void:
	## Entering an attack breaks group invisibility immediately, rather than
	## waiting for the delayed damage-release frame.
	if is_stealthed():
		stealth_remaining_seconds = 0.0
		stealth_buff_id = ""
		presentation.update_stealth_visual()
		passive_wakeup_changed.emit()
	_attack_timer = attack_interval
	last_attack_type = attack_type
	pending_attack_target_link = enemy
	_pending_attack_snapshot = create_attack_release_footprint_snapshot(enemy)
	last_attack_footprint_snapshot = _pending_attack_snapshot.duplicate(true)
	_pending_attack_release_remaining = _attack_release_delay_seconds()
	var target_offset = actor_links.actor_position_screen_px(enemy) - motion.position_screen_px()
	if target_offset.length_squared() > 0.001:
		_pending_attack_direction = target_offset.normalized()
	_visual_facing = _pending_attack_direction
	_attack_visual_remaining = _visual_action_duration("attack")
	_visual_state = "attack"
	_visual_elapsed = 0.0
	presentation.audio_attack_started()


func _update_pending_attack(delta: float) -> void:
	if pending_attack_target_link == null:
		return
	_pending_attack_release_remaining = maxf(
		0.0, _pending_attack_release_remaining - delta
	)
	if _pending_attack_release_remaining <= 0.0:
		_release_pending_attack()


func _release_pending_attack() -> void:
	var target := pending_attack_target_link
	var snapshot := _pending_attack_snapshot
	presentation.audio_attack_frame()
	if summon_id == "divine_beast":
		presentation.start_fire_visual()
	if (
		actor_links.actor_is_present(target)
		and not actor_links.is_retiring(target)
		and actor_links.current_hp(target) > 0
		and _enemy_accepts_external_attack(target)
		and attack_release_snapshot_intersects_target(snapshot, target)
		and _attack_world_path_clear(target)
		and _attack_hit_succeeds(target)
	):
		var target_model: Object = actor_links.resolve_model(target)
		var hp_before: int = target_model.current_hp
		var damage := _outgoing_damage_after_defense(target_model)
		if damage > 0:
			actor_links.apply_enemy_damage(target_model, damage)
		if hp_before > 0 and target_model.current_hp <= 0:
			gain_growth_from_kill(int(target_model.monster_data.get("level", 0)))
	if _runtime_motion_faulted(): return
	_clear_pending_attack()


func _outgoing_damage_after_defense(target: Object) -> int:
	var raw_damage := _rng.randi_range(attack_min, attack_max)
	if attack_type == "physical":
		return int(warrior_rules.resolve_enemy_physical_damage(
			raw_damage, target.effective_physical_defense()
		).get("final_damage", 0))
	if attack_type == "fire":
		# Primary TElfWarriorMonster/TSpitSpider uses its own accuracy roll and
		# GetMagStruckDamage (MAC). It is not a player direct spell: do not add
		# its anti-magic gate or RM_MAGSTRUCK movement delay to the pet's breath.
		if not target.direct_spell_runtime_stats_into(_outgoing_magic_stats):
			return 0
		var minimum := int(_outgoing_magic_stats.get("magic_defense_min", 0))
		var maximum := int(_outgoing_magic_stats.get("magic_defense_max", minimum))
		var boosted_raw := raw_damage if effective_skill_rank <= 3 else roundi(float(raw_damage) * divine_damage_more)
		return maxi(0, boosted_raw - _rng.randi_range(minimum, maximum))
	return 0


func _attack_hit_succeeds(target: RefCounted) -> bool:
	if profile_state.test_mode:
		return true
	return warrior_rules.roll_hit(accuracy, actor_links.agility(target), _rng)


func _attack_release_delay_seconds() -> float:
	if not _timing_profile.is_empty():
		var explicit_ms := int(_timing_profile.get("attack_release_ms", -1))
		if explicit_ms >= 0:
			return float(explicit_ms) / 1000.0
		var release_frame_index := 5
		var frame_ms := int(
			_timing_profile.get("frame_ms", {}).get("attack", 100)
		)
		return float(release_frame_index * frame_ms) / 1000.0
	return 0.5


func _clear_pending_attack() -> void:
	pending_attack_target_link = null
	_pending_attack_snapshot = {}
	_pending_attack_release_remaining = 0.0


func retire_for_rank_cap() -> void:
	_expire()


func _expire() -> void:
	if state == SummonState.EXPIRED or state == SummonState.DEAD:
		return
	_set_state(SummonState.EXPIRED)
	_clear_pending_attack()
	motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
	if _runtime_motion_faulted():
		return
	lifetime.request_retirement()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	var previous_state := state
	state = next_state
	summon_state_changed.emit(previous_state, state)


func _nearest_enemy() -> RefCounted:
	_target_scan_count += 1
	if runtime_map_id < 0:
		_reject_target_acquisition("runtime_map_unavailable")
		return null
	if not runtime_screen_to_ground_position_px.is_valid():
		_reject_target_acquisition("screen_to_ground_projection_unavailable")
		return null
	if not spatial.available():
		_reject_target_acquisition("spatial_index_unavailable")
		return null
	var origin_ground_gu = _runtime_screen_to_ground_position(motion.position_screen_px())
	if not origin_ground_gu.is_finite():
		_reject_target_acquisition("origin_ground_position_invalid")
		return null
	_target_acquire_last_rejection_reason = ""
	var nearest: RefCounted
	var nearest_distance_gu := INF
	var nearest_stable_combat_order := 0
	var nearest_actor_runtime_id := 0
	var candidates = spatial.query_aabb_candidates(
		runtime_map_id,
		Rect2(origin_ground_gu, Vector2.ZERO),
		aggro_radius_gu + combat_radius_gu + GroundUnitSpaceScript.EPSILON_GU
	)
	_target_candidate_count += candidates.size()
	for candidate: Dictionary in candidates:
		var enemy: RefCounted = candidate.get("actor", null)
		if not actor_links.is_enemy(enemy):
			continue
		if (
			not actor_links.actor_is_present(enemy)
			or actor_links.is_retiring(enemy)
			or actor_links.current_hp(enemy) <= 0
			or actor_links.runtime_map_id(enemy) != runtime_map_id
			or not _enemy_accepts_external_attack(enemy)
		):
			continue
		var target_ground_gu = actor_links.position_ground_gu(enemy)
		if not target_ground_gu.is_finite():
			continue
		var target_bounds_gu := maxf(
			0.0, float(candidate.get("bounds_gu", 0.0))
		)
		var distance_gu := maxf(
			0.0,
			origin_ground_gu.distance_to(target_ground_gu)
				- combat_radius_gu
				- target_bounds_gu
		)
		if distance_gu > aggro_radius_gu + GroundUnitSpaceScript.EPSILON_GU:
			continue
		var stable_combat_order := int(
			candidate.get("stable_combat_order", 0)
		)
		var actor_runtime_id := int(candidate.get("actor_runtime_id", 0))
		if (
			distance_gu < nearest_distance_gu - GroundUnitSpaceScript.EPSILON_GU
			or (
				absf(distance_gu - nearest_distance_gu)
					<= GroundUnitSpaceScript.EPSILON_GU
				and (
					nearest == null
					or stable_combat_order < nearest_stable_combat_order
					or (
						stable_combat_order == nearest_stable_combat_order
						and actor_runtime_id < nearest_actor_runtime_id
					)
				)
			)
		):
			nearest = enemy
			nearest_distance_gu = distance_gu
			nearest_stable_combat_order = stable_combat_order
			nearest_actor_runtime_id = actor_runtime_id
	return nearest


func _enemy_accepts_external_attack(enemy: RefCounted) -> bool:
	if not actor_links.actor_is_present(enemy) or actor_links.is_retiring(enemy):
		return false
	return actor_links.accepts_external_attack(enemy)


func _reject_target_acquisition(reason: String) -> void:
	_target_acquire_fail_closed_count += 1
	_target_acquire_last_rejection_reason = reason


func _owner_formation_anchor_screen_px() -> Vector2:
	var owner_forward_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			actor_links.movement_facing(owner_link)
		)
	)
	if (
		owner_forward_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		owner_forward_ground_gu = Vector2(1.0, 1.0)
	owner_forward_ground_gu = owner_forward_ground_gu.normalized()
	var lateral_ground_gu := Vector2(
		-owner_forward_ground_gu.y,
		owner_forward_ground_gu.x
	)
	var typed_side := -1.0 if summon_id == "skeleton" else 1.0
	var slot_offset_ground_gu := (
		lateral_ground_gu
		* typed_side
		* RECALL_OFFSET_GU
		* float(1 + floori(float(pet_slot_index) / 2.0))
	)
	if summon_id == "skeleton" and pet_slot_index % 2 == 1:
		slot_offset_ground_gu -= owner_forward_ground_gu * RECALL_OFFSET_GU
	return (
		actor_links.actor_position_screen_px(owner_link)
		+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			slot_offset_ground_gu
		)
	)


func rest_formation_contract_snapshot() -> Dictionary:
	return {
		"contract_id": REST_FORMATION_CONTRACT_ID,
		"collision_contract_id": COLLISION_INTERACTION_CONTRACT_ID,
		"typed_slot_id": "%s:%d" % [summon_id, pet_slot_index],
		"direction_source": "owner_movement_facing",
		"slot_offset_gu": RECALL_OFFSET_GU,
		"expected_dual_separation_gu": RECALL_OFFSET_GU * 2.0,
		"wake_distance_gu": FORMATION_WAKE_DISTANCE_GU,
		"settle_distance_gu": FORMATION_SETTLE_DISTANCE_GU,
		"desired_screen_position_px": _owner_formation_anchor_screen_px(),
		"player_pass_through": (
			motion.collision_layer() == WorldSpatialRulesScript.PLAYER_LAYER
			and (
				motion.collision_mask() & WorldSpatialRulesScript.PLAYER_LAYER
			) == 0
		),
		"pet_hard_collision_enabled": (
			motion.collision_mask() & WorldSpatialRulesScript.PLAYER_LAYER
		) != 0,
		"world_collision_preserved": (
			motion.collision_mask() & WorldSpatialRulesScript.WORLD_LAYER
		) != 0,
		"enemy_collision_preserved": (
			motion.collision_mask() & WorldSpatialRulesScript.ENEMY_LAYER
		) != 0,
	}


func spatial_contract_snapshot() -> Dictionary:
	return {
		"contract_id": SPATIAL_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"move_speed_gu_per_sec": move_speed_gu_per_sec,
		"attack_range_gu": attack_range_gu,
		"attack_footprint_contract_id": ATTACK_FOOTPRINT_CONTRACT_ID,
		"attack_effect_length_gu": _attack_effect_length_gu(),
		"attack_effect_width_gu": SUMMON_ATTACK_WIDTH_GU,
		"attack_interval_seconds": attack_interval,
		"aggro_radius_gu": aggro_radius_gu,
		"combat_radius_gu": combat_radius_gu,
		"leash_range_gu": leash_range_gu,
		"teleport_range_gu": teleport_range_gu,
		"follow_distance_gu": follow_distance_gu,
		"owner_teleport_relocation_contract_id": (
			OWNER_TELEPORT_RELOCATION_CONTRACT_ID
		),
	}


func create_attack_release_footprint_snapshot(target: RefCounted) -> Dictionary:
	if not actor_links.actor_is_present(target):
		return {}
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		last_attack_footprint_snapshot = {}
		return {}
	var origin_ground_gu := (
		_runtime_screen_to_ground_position(motion.position_screen_px())
	)
	var target_ground_gu := (
		_runtime_screen_to_ground_position(actor_links.actor_position_screen_px(target))
	)
	var release_id := "%s:attack:%d:%d" % [
		skill_id,
		runtime_actor_id(),
		_attack_release_sequence,
	]
	_attack_release_sequence += 1
	last_attack_relation = "directed_ground_gu"
	return SkillFootprintSnapshotScript.create_directed_rectangle(
		skill_id,
		release_id,
		origin_ground_gu,
		GroundUnitSpaceScript.normalized_ground_direction(
			origin_ground_gu, target_ground_gu
		),
		_attack_effect_length_gu(),
		SUMMON_ATTACK_WIDTH_GU,
		0.0,
		0.0,
		0.0,
		"",
		_snapshot_coordinate_context(origin_ground_gu)
	)


func _attack_effect_length_gu() -> float:
	return (
		DIVINE_BEAST_ATTACK_LENGTH_GU
		if summon_id == "divine_beast"
		else SKELETON_ATTACK_LENGTH_GU
	)


func _target_within_attack_geometry(target: RefCounted) -> bool:
	if not actor_links.actor_is_present(target):
		return false
	var origin_ground_gu = _runtime_screen_to_ground_position(motion.position_screen_px())
	var target_ground_gu := _runtime_screen_to_ground_position(
		actor_links.actor_position_screen_px(target)
	)
	if not origin_ground_gu.is_finite() or not target_ground_gu.is_finite():
		return false
	## The target is the aiming axis, so the exact directed-rectangle contact
	## condition reduces to length plus the target's canonical GU footprint.
	## Release still uses the frozen polygon snapshot, preserving width when a
	## target moves sideways during the attack animation.
	return (
		origin_ground_gu.distance_to(target_ground_gu)
		<= _attack_effect_length_gu()
			+ _target_combat_radius_gu(target)
			+ GroundUnitSpaceScript.EPSILON_GU
		and _attack_world_path_clear(target)
	)


func _attack_world_path_clear(target: RefCounted) -> bool:
	if not lifetime.is_present() or not actor_links.actor_is_present(target):
		return false
	return motion.world_path_clear(motion.position_screen_px(), actor_links.actor_position_screen_px(target))


func attack_release_snapshot_intersects_target(
	attack_snapshot: Dictionary,
	target: RefCounted
) -> bool:
	if attack_snapshot.is_empty():
		return false
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		attack_snapshot,
		_snapshot_coordinate_context(
			_runtime_screen_to_ground_position(motion.position_screen_px())
		),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		attack_snapshot,
		_runtime_screen_to_ground_position(actor_links.actor_position_screen_px(target)),
		_target_combat_radius_gu(target)
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


func distance_gu_to_screen_position_px(target_screen_position_px: Vector2) -> float:
	return _distance_gu_between_screen_positions_px(
		motion.position_screen_px(),
		target_screen_position_px
	)


func target_footprint_surface_distance_gu(
	target_screen_position_px: Vector2,
	target_combat_radius_gu: float
) -> float:
	return maxf(
		0.0,
		distance_gu_to_screen_position_px(target_screen_position_px)
		- combat_radius_gu
		- maxf(0.0, target_combat_radius_gu)
	)


func _target_combat_radius_gu(target: RefCounted) -> float:
	return actor_links.enemy_combat_radius_gu(target)


func _screen_velocity_toward_delta_px(delta_screen_px: Vector2) -> Vector2:
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			delta_screen_px
		)
	)
	return GroundUnitSpaceScript.desired_screen_velocity_px_per_sec(
		direction_ground_gu,
		move_speed_gu_per_sec
	)


static func _distance_gu_between_screen_positions_px(
	first_screen_position_px: Vector2,
	second_screen_position_px: Vector2
) -> float:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		second_screen_position_px - first_screen_position_px
	).length()


func apply_control(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0 or state in [SummonState.DEAD, SummonState.EXPIRED]:
		return
	_monster_control_remaining = maxf(_monster_control_remaining, seconds)
	pending_attack_target_link = null
	_pending_attack_snapshot = {}
	_pending_attack_release_remaining = 0.0
	motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
	if _runtime_motion_faulted():
		return
	actual_ground_motion_gu = Vector2.ZERO


func apply_monster_poison(tick_damage: int, seconds: float, interval_seconds: float) -> bool:
	if current_hp <= 0 or state in [SummonState.DEAD, SummonState.EXPIRED]:
		return false
	if actor_links.actor_is_present(owner_link) and actor_links.combat_transition_is_active(owner_link):
		return false
	return _monster_source_poison.apply(tick_damage, seconds, interval_seconds)


func _update_monster_source_poison(delta: float) -> void:
	if current_hp <= 0 or state in [SummonState.DEAD, SummonState.EXPIRED]:
		_monster_source_poison.clear()
		return
	if actor_links.actor_is_present(owner_link) and actor_links.combat_transition_is_active(owner_link):
		return
	var ticks: int = _monster_source_poison.advance(delta)
	for _tick in range(ticks):
		if current_hp <= 0 or state in [SummonState.DEAD, SummonState.EXPIRED]:
			_monster_source_poison.clear()
			break
		_apply_resolved_damage(_monster_source_poison.tick_damage, false)


func take_damage(
	amount: int,
	source_or_defense_roll: Variant = null,
	defense_roll := -1,
	delivery_identity: Variant = null,
) -> void:
	## The runtime service supplies the source actor as the second argument. A
	## numeric second argument is also accepted as a deterministic test hook;
	## neither form changes the canonical summon defence range.
	var resolved_roll := defense_roll
	if resolved_roll < 0 and (source_or_defense_roll is int or source_or_defense_roll is float):
		resolved_roll = int(source_or_defense_roll)
	var absorbed := _roll_defense(
		ac_min,
		ac_max,
		physical_defence_bonus(),
		resolved_roll,
	)
	_apply_resolved_damage(maxi(1, amount - absorbed), true, delivery_identity)


func take_monster_mixed_damage(
	physical_raw: int,
	magic_raw: int,
	context: Dictionary,
	delivery_identity: Variant = null,
) -> Dictionary:
	if current_hp <= 0 or state in [SummonState.DEAD, SummonState.EXPIRED]:
		damage_observer.record_terminal(delivery_identity, "rejected", "summon_dead")
		return {"success": false, "applied_damage": 0, "failure_reason": "summon_dead"}
	if actor_links.actor_is_present(owner_link) and actor_links.combat_transition_is_active(owner_link):
		damage_observer.record_terminal(delivery_identity, "rejected", "owner_combat_isolated")
		return {"success": false, "applied_damage": 0, "failure_reason": "owner_combat_isolated"}
	if physical_raw < 0 or magic_raw < 0:
		damage_observer.record_terminal(delivery_identity, "rejected", "invalid_mixed_damage")
		return {"success": false, "applied_damage": 0, "failure_reason": "invalid_mixed_damage"}
	var ac_roll := _roll_defense(ac_min, ac_max, physical_defence_bonus(), -1)
	var mac_roll := _roll_defense(mac_min, mac_max, magic_defence_bonus(), -1)
	var physical_damage := maxi(0, physical_raw - ac_roll)
	var magic_damage := maxi(0, magic_raw - mac_roll)
	var total := physical_damage + magic_damage
	var hp_before := current_hp
	if total > 0:
		_apply_resolved_damage(total, true, delivery_identity)
	elif damage_observer.recording_enabled:
		damage_observer.record_terminal(delivery_identity, "mitigated", "summon_mixed_zero")
	return {
		"success": true, "runtime_contract": "monster_mixed_damage.v1",
		"physical_defense_roll": ac_roll, "magic_defense_roll": mac_roll,
		"physical_damage": physical_damage, "magic_damage": magic_damage,
		"pipeline_input": total, "applied_damage": maxi(0, hp_before - current_hp),
		"release_id": str(context.get("release_id", "")),
	}


func take_magic_damage(amount: int, magic_defense_roll := -1) -> void:
	var absorbed := _roll_defense(
		mac_min,
		mac_max,
		magic_defence_bonus(),
		magic_defense_roll,
	)
	_apply_resolved_damage(maxi(1, amount - absorbed))


func take_direct_spell_damage(
	skill_id_value: String,
	raw_damage: int,
	anti_magic_roll := -1,
	magic_defense_roll := -1,
	causes_struck := true,
	delivery_identity: Variant = null,
) -> Dictionary:
	## Boss target-magic, special-magic melee and area-magic all settle through
	## this same direct-spell contract. Summons currently have no anti-magic
	## points; their canonical MAC range (plus an active MAC buff) is consumed by
	## the shared anti-magic -> MAC -> damage pipeline. AC is intentionally not
	## part of direct spell settlement.
	var stable_skill_id = profession_rules.skill_id(skill_id_value)
	var adapted_stats := {
		"magic_defense_min": maxi(0, mac_min + magic_defence_bonus()),
		"magic_defense_max": maxi(
			maxi(0, mac_min + magic_defence_bonus()),
			mac_max + magic_defence_bonus(),
		),
	}
	var checked_anti_magic_roll := anti_magic_roll
	if checked_anti_magic_roll < 0:
		checked_anti_magic_roll = _rng.randi_range(
			0,
			combat_rules.ANTI_MAGIC_ROLL_SIDES - 1,
		)
	var magic_defense_state := {}
	var magic_defense_adapter := Callable(
		self,
		"_resolve_direct_spell_magic_defense",
	).bind(magic_defense_roll, magic_defense_state)
	var resolution = combat_rules.resolve_direct_spell_damage(
		stable_skill_id,
		raw_damage,
		adapted_stats,
		checked_anti_magic_roll,
		magic_defense_adapter,
	)
	resolution["runtime_contract"] = DIRECT_SPELL_DAMAGE_RUNTIME_ID
	resolution["mac_buff_applied"] = magic_defence_bonus()
	resolution["magic_defense_min"] = int(adapted_stats.magic_defense_min)
	resolution["magic_defense_max"] = int(adapted_stats.magic_defense_max)
	resolution["magic_defense_roll"] = int(magic_defense_state.get("roll", -1))
	resolution["physical_defense_bypassed"] = true
	var hp_before := current_hp
	if int(resolution.get("final_damage", 0)) > 0:
		_apply_resolved_damage(int(resolution.final_damage), true, delivery_identity)
	elif damage_observer.recording_enabled:
		damage_observer.record_terminal(delivery_identity, "mitigated", "summon_spell_zero")
	resolution["summon_pipeline_input"] = int(resolution.final_damage)
	resolution["applied_damage"] = maxi(0, hp_before - current_hp)
	return resolution


func _resolve_direct_spell_magic_defense(
	_skill_id_value: String,
	incoming_damage: int,
	target_stats: Dictionary,
	roll_override: int,
	resolution_state: Dictionary,
) -> int:
	var minimum := maxi(0, int(target_stats.get("magic_defense_min", 0)))
	var maximum := maxi(
		minimum,
		int(target_stats.get("magic_defense_max", minimum)),
	)
	var roll := (
		clampi(roll_override, minimum, maximum)
		if roll_override >= 0
		else _rng.randi_range(minimum, maximum)
	)
	resolution_state["roll"] = roll
	return maxi(0, incoming_damage - roll)


func _roll_defense(
	base_minimum: int,
	base_maximum: int,
	active_bonus: int,
	roll_override: int,
) -> int:
	var minimum := maxi(0, base_minimum) + maxi(0, active_bonus)
	var maximum := maxi(minimum, maxi(0, base_maximum) + maxi(0, active_bonus))
	return (
		clampi(roll_override, minimum, maximum)
		if roll_override >= 0
		else _rng.randi_range(minimum, maximum)
	)


func restore_health(amount: int) -> int:
	if amount <= 0 or state in [SummonState.DEAD, SummonState.EXPIRED]:
		return 0
	var hp_before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	var actual_restored := current_hp - hp_before
	if actual_restored > 0:
		presentation.redraw()
	return actual_restored


func _apply_resolved_damage(amount: int, causes_struck := true, delivery_identity: Variant = null) -> void:
	if _runtime_motion_faulted(): return
	if state in [SummonState.DEAD, SummonState.EXPIRED]:
		damage_observer.record_terminal(delivery_identity, "rejected", "summon_dead_or_expired")
		return
	var hp_before := current_hp
	current_hp = maxi(0, current_hp - maxi(1, amount))
	if damage_observer.recording_enabled:
		damage_observer.record_hp_mutation(maxi(1, amount), hp_before, current_hp, "summon_damage", delivery_identity)
	if current_hp == 0:
		_set_state(SummonState.DEAD)
		presentation.audio_death_once()
		lifetime.unregister_combat_target()
		motion.set_collision_layer(0)
		if _runtime_motion_faulted():
			return
		motion.set_collision_mask(0)
		if _runtime_motion_faulted():
			return
		motion.set_velocity_screen_px_per_sec(Vector2.ZERO)
		if _runtime_motion_faulted():
			return
		current_target_link = null
		_clear_pending_attack()
		_hit_visual_remaining = 0.0
		_attack_visual_remaining = 0.0
		_death_visual_remaining = _visual_action_duration("death")
		_visual_state = "death"
		_visual_elapsed = 0.0
	elif causes_struck:
		_hit_visual_remaining = _visual_action_duration("hit")
		_visual_state = "hit"
		_visual_elapsed = 0.0
		if current_hp < hp_before:
			presentation.audio_hurt()
	presentation.redraw()


func _screen_velocity_toward_arrival_delta_px(
	delta_screen_px: Vector2,
	delta: float
) -> Vector2:
	var desired_velocity := _screen_velocity_toward_delta_px(delta_screen_px)
	if delta <= 0.0:
		return desired_velocity
	var maximum_step_px := desired_velocity.length() * delta
	if maximum_step_px > delta_screen_px.length():
		return delta_screen_px / delta
	return desired_velocity


func state_name() -> String:
	return SummonState.keys()[state]


func persistence_snapshot() -> Dictionary:
	return {
		"contract_id": PERSISTENCE_CONTRACT_ID,
		"alive": (
			current_hp > 0
			and state not in [SummonState.EXPIRED, SummonState.DEAD]
		),
		"runtime_state": state_name(),
		"summon_id": summon_id,
		"skill_id": skill_id,
		"skill_rank": skill_level,
		"pet_slot_index": pet_slot_index,
		"effective_skill_rank": effective_skill_rank,
		"owner_level": owner_level,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"summon_exp_level": summon_exp_level,
		"maximum_pet_level": maximum_pet_level,
		"pet_growth_exp": pet_growth_exp,
		"remaining_lifetime": remaining_lifetime,
		"stealth": {
			"remaining_seconds": stealth_remaining_seconds,
			"buff_id": stealth_buff_id,
		},
		"physical_defence": {
			"bonus": ac_buff_bonus,
			"remaining_seconds": ac_buff_remaining_seconds,
			"buff_id": ac_buff_id,
		},
		"magic_defence": {
			"bonus": mac_buff_bonus,
			"remaining_seconds": mac_buff_remaining_seconds,
			"buff_id": mac_buff_id,
		},
	}


func restore_persistence_snapshot(snapshot: Dictionary) -> bool:
	if str(snapshot.get("contract_id", "")) != PERSISTENCE_CONTRACT_ID:
		return false
	if not bool(snapshot.get("alive", true)):
		return false
	var restored_summon_id := str(snapshot.get("summon_id", ""))
	if restored_summon_id not in ["skeleton", "divine_beast"]:
		return false
	summon_id = restored_summon_id
	skill_id = str(snapshot.get("skill_id", skill_id))
	skill_level = maxi(0, int(snapshot.get("skill_rank", skill_level)))
	pet_slot_index = maxi(0, int(snapshot.get("pet_slot_index", 0)))
	effective_skill_rank = maxi(0, int(snapshot.get("effective_skill_rank", skill_level)))
	divine_damage_more = rank_rules.more_multiplier(effective_skill_rank) if summon_id == "divine_beast" else 1.0
	owner_level = maxi(1, int(snapshot.get("owner_level", owner_level)))
	var restored_current_hp := maxi(0, int(snapshot.get("current_hp", current_hp)))
	summon_exp_level = clampi(
		int(snapshot.get("summon_exp_level", summon_exp_level)), 0, 7
	)
	maximum_pet_level = clampi(
		int(snapshot.get("maximum_pet_level", maximum_pet_level)),
		summon_exp_level,
		7
	)
	pet_growth_exp = maxi(0, int(snapshot.get("pet_growth_exp", pet_growth_exp)))
	remaining_lifetime = maxf(
		0.0, float(snapshot.get("remaining_lifetime", remaining_lifetime))
	)
	var stealth: Dictionary = snapshot.get("stealth", {})
	stealth_remaining_seconds = maxf(
		0.0, float(stealth.get("remaining_seconds", 0.0))
	)
	stealth_buff_id = str(stealth.get("buff_id", ""))
	var physical: Dictionary = snapshot.get("physical_defence", {})
	ac_buff_bonus = maxi(0, int(physical.get("bonus", 0)))
	ac_buff_remaining_seconds = maxf(
		0.0, float(physical.get("remaining_seconds", 0.0))
	)
	ac_buff_id = str(physical.get("buff_id", ""))
	var magic: Dictionary = snapshot.get("magic_defence", {})
	mac_buff_bonus = maxi(0, int(magic.get("bonus", 0)))
	mac_buff_remaining_seconds = maxf(
		0.0, float(magic.get("remaining_seconds", 0.0))
	)
	mac_buff_id = str(magic.get("buff_id", ""))
	## max_hp and every combat stat are derived from the canonical pet level.
	## The persisted max_hp is retained only for backward-readable snapshots;
	## trusting it would allow a stale/edited snapshot to restore level-3 HP with
	## level-0 AC/MAC/DC (the historical restore bug).
	apply_growth_stats_preserving_current_hp()
	current_hp = clampi(restored_current_hp, 0, max_hp)
	name_color_index = summon_rules.summon_name_color_index(summon_exp_level)
	attack_range_gu = _attack_effect_length_gu()
	presentation.refresh_buff_draw_signature()
	presentation.update_stealth_visual()
	presentation.redraw()
	return true


func _visual_action_duration(action_name: String) -> float:
	if _timing_profile.is_empty():
		return 1.2 if action_name == "death" else 0.2
	var frame_count := int(_timing_profile.get("frame_counts", {}).get(action_name, 1))
	var frame_ms := int(_timing_profile.get("frame_ms", {}).get(action_name, 100))
	return float(frame_count * frame_ms) / 1000.0


func _runtime_motion_faulted() -> bool:
	return motion != null and motion.has_method("faulted") and bool(motion.call("faulted"))
