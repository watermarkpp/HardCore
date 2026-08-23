extends Node

## Q2-B lifecycle: register, natural expiry, manual cancel, node queue_free,
## caster death, map clear, generation change and index-unavailable rejection.
## No residual registration, no double tick, no invalid reference access.

const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_A := 9601
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _damage_count := 0
var _lifecycle_log: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_normal_registration_case()
	_natural_expiry_case()
	_manual_cancel_case()
	_node_freed_case()
	_caster_death_case()
	_generation_change_case()
	_index_unavailable_case()
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_LIFECYCLE_PASS")
	get_tree().quit(0)


func _normal_registration_case() -> void:
	_fresh_world()
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	var effect := _make_effect("normal", 1, 60.0, 2.0)
	assert(
		_manager.registered_effect_count() == 1,
		"normal registration must be tracked"
	)
	_manager.tick_frame(1.0)
	assert(
		_damage_count == 1,
		"registered effect must tick normally"
	)
	_manager.clear_all()
	_cleanup_world()


func _natural_expiry_case() -> void:
	_fresh_world()
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	var effect := _make_effect("expiry", 1, 1.0, 2.0)
	_manager.tick_frame(0.6)
	assert(
		_damage_count == 1 and _manager.registered_effect_count() == 1,
		"effect must tick before expiry"
	)
	_manager.tick_frame(0.6)
	assert(
		_damage_count == 1 and _manager.registered_effect_count() == 0,
		"effect must expire after its duration"
	)
	assert(
		_lifecycle_log[-1] == "expired",
		"natural expiry must call the lifecycle callback with expired"
	)
	var before := _damage_count
	_manager.tick_frame(1.0)
	assert(
		_damage_count == before,
		"expired effect must never tick again"
	)
	_cleanup_world()


func _manual_cancel_case() -> void:
	_fresh_world()
	var effect := _make_effect("cancel", 1, 60.0, 2.0)
	_manager.unregister(1, "cancelled")
	assert(
		_manager.registered_effect_count() == 0,
		"manual cancel must unregister"
	)
	assert(
		_lifecycle_log[-1] == "cancelled",
		"manual cancel must report cancelled"
	)
	var before := _damage_count
	_manager.tick_frame(1.0)
	assert(
		_damage_count == before,
		"cancelled effect must never tick again"
	)
	_cleanup_world()


func _node_freed_case() -> void:
	_fresh_world()
	var effect := _make_effect("node_freed", 1, 60.0, 2.0)
	effect.queue_free()
	_manager.tick_frame(0.016)
	assert(
		_manager.registered_effect_count() == 0,
		"a queue_freed effect must be unregistered on the next tick"
	)
	assert(
		_lifecycle_log[-1] == "node_freed",
		"external node teardown must report node_freed"
	)
	_cleanup_world()


func _caster_death_case() -> void:
	_fresh_world()
	var caster := Node2D.new()
	caster.name = "DoomedCaster"
	add_child(caster)
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	var effect := Fixtures.create_effect(
		self,
		SKILL_ID,
		"q2b:life:caster_death",
		MAP_A,
		Vector2.ZERO,
		2.0,
		1.0,
		60.0,
		3,
		caster,
		Callable(self, "_record_damage")
	)
	add_child(effect)
	Fixtures.register_effect(
		_manager,
		effect,
		1,
		MAP_A,
		Callable(self, "_record_damage")
	)
	_effects.append(effect)
	caster.queue_free()
	_manager.tick_frame(1.0)
	assert(
		_damage_count == 1,
		"legacy contract: a dead caster does not cancel its ground effect"
	)
	_manager.clear_all()
	_cleanup_world()


func _generation_change_case() -> void:
	_fresh_world()
	var first := _make_effect("gen_first", 1, 60.0, 2.0)
	_manager.clear_all()
	assert(
		_manager.registered_effect_count() == 0,
		"generation change must clear the old world"
	)
	var second := _make_effect("gen_second", 2, 60.0, 2.0)
	assert(
		_manager.registered_effect_count() == 1,
		"the new generation must register cleanly"
	)
	_manager.clear_all()
	_cleanup_world()


func _index_unavailable_case() -> void:
	_fresh_world()
	_manager = ManagerScript.new(null)
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	var effect := _make_effect("no_index", 1, 60.0, 2.0)
	_manager.tick_frame(1.0)
	var diagnostics: Dictionary = _manager.persistent_ground_effect_diagnostics()
	assert(
		_damage_count == 0,
		"index-unavailable tick must not damage"
	)
	assert(
		int(diagnostics.get("spatial_index_unavailable_count", 0)) == 1,
		"index-unavailable tick must be counted"
	)
	assert(
		str(diagnostics.get("rejection_reason", ""))
		== "spatial_index_unavailable",
		"index-unavailable tick must record the rejection reason"
	)
	assert(
		int(diagnostics.get("group_scan_count", -1)) == 0
		and int(diagnostics.get("group_nodes_examined", -1)) == 0,
		"index-unavailable tick must never fall back to a group scan"
	)
	_manager.clear_all()
	_cleanup_world()


func _make_effect(
	label: String,
	effect_id: int,
	duration_s: float,
	interval_s: float
) -> GroundSkillEffect:
	var effect := Fixtures.create_effect(
		self,
		SKILL_ID,
		"q2b:life:%s" % label,
		MAP_A,
		Vector2.ZERO,
		2.0,
		interval_s,
		duration_s,
		3,
		null,
		Callable(self, "_record_damage")
	)
	add_child(effect)
	var registered := Fixtures.register_effect(
		_manager,
		effect,
		effect_id,
		MAP_A,
		Callable(self, "_record_damage"),
		Callable(self, "_record_lifecycle")
	)
	assert(registered, "lifecycle effect must register")
	_effects.append(effect)
	return effect


func _fresh_world() -> void:
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	_enemies.clear()
	_effects.clear()
	_damage_count = 0
	_lifecycle_log.clear()


func _cleanup_world() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_enemies.clear()
	_effects.clear()


func _cleanup() -> void:
	_cleanup_world()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_count += 1
	enemy.take_damage(amount, null)


func _record_lifecycle(reason: String, effect: Variant) -> void:
	_lifecycle_log.append(reason)
	if effect is Node and is_instance_valid(effect):
		(effect as Node).queue_free()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)


func _snapshot_contains_enemy(
	enemy: EnemyActor,
	snapshot: Dictionary
) -> bool:
	return Snapshot.intersects_target_combat_footprint_ground_gu(
		snapshot,
		GroundUnit.screen_delta_px_to_ground_delta_gu(enemy.global_position),
		enemy.combat_radius_gu
	)
