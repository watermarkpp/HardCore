extends Node

## Q2-B tick cadence: the manager must reproduce the legacy per-effect
## _physics_process timing exactly:
##   - first tick on the first physics frame (timer starts at 0)
##   - one tick per physics frame, timer resets to a full interval
##   - long frames never catch up multiple ticks
##   - the expiry frame ticks first (if due) and then unregisters

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

const MAP_A := 9201
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _manager: ManagerScript
var _effect: GroundSkillEffect
var _enemy: EnemyActor
var _damage_count := 0
var _case_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_run_cadence_case(
		"normal_cadence",
		1.0,
		6.0,
		[0.5, 0.5, 0.5, 0.5, 2.0, 1.0, 2.0]
	)
	_run_cadence_case("first_tick_creation", 5.0, 20.0, [0.25])
	_run_cadence_case("long_frame_no_catchup", 1.0, 10.0, [0.1, 3.0])
	_run_cadence_case("multi_interval_crossing", 1.0, 10.0, [0.25, 3.0])
	_run_cadence_case("expiry_exact", 1.0, 2.0, [0.5, 0.5, 0.5, 0.5])
	_run_cadence_case("expiry_before_tick", 1.0, 1.9, [0.5, 0.5, 0.5, 0.5])
	_run_cadence_case("expiry_after_tick", 1.0, 2.5, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	assert(
		_case_count == 7,
		"all cadence cases must run"
	)
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_TICK_CADENCE_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _run_cadence_case(
	label: String,
	interval: float,
	duration: float,
	deltas: Array
) -> void:
	_case_count += 1
	_fresh_world()
	_effect = Fixtures.create_effect(
		self,
		SKILL_ID,
		"q2b:cadence:%s" % label,
		MAP_A,
		Vector2.ZERO,
		2.0,
		interval,
		duration,
		1,
		null,
		Callable(self, "_record_damage")
	)
	add_child(_effect)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_A,
		Vector2.ZERO,
		0.25
	)
	var registered := Fixtures.register_effect(
		_manager,
		_effect,
		1,
		MAP_A,
		Callable(self, "_record_damage")
	)
	assert(registered, "cadence effect must register")
	assert(
		_damage_count == 0,
		"registration must not tick; first tick happens on the first frame"
	)
	assert(
		_manager.registered_effect_count() == 1,
		"effect must stay registered until expiry"
	)

	var legacy: Dictionary = _legacy_cadence(interval, duration, deltas)
	var manager_ticks: Array[float] = []
	var elapsed := 0.0
	for raw_delta: Variant in deltas:
		var delta := float(raw_delta)
		elapsed += delta
		var before := _damage_count
		_manager.tick_frame(delta)
		if _damage_count > before:
			manager_ticks.append(elapsed)

	var legacy_ticks: Array = legacy.get("ticks", [])
	assert(
		manager_ticks.size() == legacy_ticks.size(),
		"%s: manager tick count %d must equal legacy %d"
		% [label, manager_ticks.size(), legacy_ticks.size()]
	)
	for i: int in range(legacy_ticks.size()):
		assert(
			is_equal_approx(
				float(manager_ticks[i]),
				float(legacy_ticks[i])
			),
			"%s: tick time %d manager=%f legacy=%f"
			% [label, i, float(manager_ticks[i]), float(legacy_ticks[i])]
		)
	var total_elapsed := 0.0
	for raw_delta: Variant in deltas:
		total_elapsed += float(raw_delta)
	if total_elapsed >= duration - 0.0001:
		assert(
			_manager.registered_effect_count() == 0,
			"%s: effect must be unregistered after expiry" % label
		)
	else:
		assert(
			_manager.registered_effect_count() == 1,
			"%s: effect must stay registered before expiry" % label
		)
		_manager.clear_all()
	assert(
		_damage_count == legacy_ticks.size(),
		"%s: damage count must equal tick count" % label
	)
	_cleanup_world()


static func _legacy_cadence(
	interval: float,
	duration: float,
	deltas: Array
) -> Dictionary:
	## Replicates the old GroundSkillEffect._physics_process timer semantics.
	var elapsed := 0.0
	var timer := 0.0
	var remaining := duration
	var ticks: Array[float] = []
	var expiry_elapsed := -1.0
	for raw_delta: Variant in deltas:
		var delta := float(raw_delta)
		elapsed += delta
		remaining -= delta
		timer -= delta
		if timer <= 0.0:
			timer = interval
			ticks.append(elapsed)
		if remaining <= 0.0:
			expiry_elapsed = elapsed
			break
	return {
		"ticks": ticks,
		"expiry_elapsed": expiry_elapsed,
	}


func _fresh_world() -> void:
	_cleanup_world()
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	_effect = null
	_enemy = null
	_damage_count = 0


func _cleanup_world() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	if _effect != null and is_instance_valid(_effect):
		_effect.queue_free()


func _cleanup() -> void:
	_cleanup_world()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_count += 1
	enemy.take_damage(amount, null)


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
