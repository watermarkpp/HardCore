extends Node

## Accuracy is a monster runtime attribute, not a catalog-only decoration.
## This test exercises the shared EnemyActor physical settlement gate with the
## audited strict-< combat rule, then drives both ordinary melee and physical
## projectile release paths.  Magic delivery is intentionally not covered by
## this gate.

const EnemyActorScript := preload("res://scripts/enemy.gd")
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

var _target: EnemyActor
var _melee_attacker: EnemyActor
var _projectile_attacker: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = false
	MonsterIdentityScript.reset_caches_for_test()

	_target = EnemyActorScript.new()
	_target.name = "MonsterAccuracyTarget"
	_target.agility = 15
	_target.max_hp = 100
	_target.current_hp = 100
	_target.set_physics_process(false)
	_target.setup({"monster_id": 18}, null, false)
	_target.agility = 15
	_target.max_hp = 100
	_target.current_hp = 100
	_target.set_meta("runtime_map_id", 1)
	add_child(_target)

	_melee_attacker = EnemyActorScript.new()
	_melee_attacker.name = "MonsterAccuracyMeleeAttacker"
	_melee_attacker.set_physics_process(false)
	_melee_attacker.setup({"monster_id": 18}, null, false)
	_melee_attacker.environment_blocker = self
	_melee_attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	add_child(_melee_attacker)

	_projectile_attacker = EnemyActorScript.new()
	_projectile_attacker.name = "MonsterAccuracyProjectileAttacker"
	_projectile_attacker.set_physics_process(false)
	_projectile_attacker.environment_blocker = self
	_projectile_attacker.setup({"monster_id": 150}, null, false)
	_projectile_attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	add_child(_projectile_attacker)

	# Primary server rule: Random(target agility) < attacker accuracy.
	_assert_fixed_roll(8, 15, 7, true, "accuracy8_roll7_hit")
	_assert_fixed_roll(7, 15, 7, false, "accuracy7_roll7_miss")
	_assert_fixed_roll(8, 15, 8, false, "accuracy8_roll8_miss")
	_assert_fixed_roll(0, 15, 0, false, "accuracy0_miss")

	# Enemy.setup must carry the canonical accuracy and life flags into the
	# actor, while keeping the caller payload out of the authority boundary.
	var canonical_entry := MonsterIdentityScript.catalog_entry(18)
	var canonical_projection: Dictionary = canonical_entry.get("combat", {}).get("runtime_projection", {})
	var configured := EnemyActorScript.new()
	configured.setup({"monster_id": 18, "accuracy": 999, "name": "wrong"}, null, false)
	assert(configured.accuracy == int(canonical_projection.get("accuracy", -1)), "Enemy.setup did not consume canonical accuracy")
	assert(configured.monster_data.get("accuracy", -1) == configured.accuracy, "Enemy payload omitted canonical accuracy")
	assert(configured.life_type == str(canonical_projection.get("life_type", "")), "Enemy.setup did not consume canonical life_type")
	assert(configured.undead == bool(canonical_projection.get("undead", false)), "Enemy.setup did not consume canonical undead flag")
	assert(configured.anti_stealth == bool(canonical_projection.get("anti_stealth", false)), "Enemy.setup did not consume canonical anti_stealth flag")
	configured.free()

	# Ordinary melee uses the same production settlement function. Accuracy 0
	# must miss regardless of the RNG result; a value above target agility must
	# hit regardless of the RNG result.
	_target.current_hp = 100
	_melee_attacker.accuracy = 0
	_melee_attacker._deal_melee_hit(_target, 10)
	assert(_target.current_hp == 100, "ordinary monster melee ignored accuracy=0")
	assert(not bool(_melee_attacker.last_physical_hit_resolution.get("success", true)), "ordinary melee miss was not recorded")
	_target.current_hp = 100
	_melee_attacker.accuracy = 16
	_melee_attacker._deal_melee_hit(_target, 10)
	assert(_target.current_hp == 90, "ordinary monster melee did not use accuracy")
	assert(bool(_melee_attacker.last_physical_hit_resolution.get("success", false)), "ordinary melee hit was not recorded")

	# Physical projectile release also settles through the same gate.  The
	# release/visual timing is unchanged; only damage submission is gated.
	_target.current_hp = 100
	_projectile_attacker.accuracy = 0
	assert(_projectile_attacker._launch_physical_projectile(_target, 10), "physical projectile release fixture did not launch")
	_projectile_attacker._settle_physical_projectile_release(_projectile_attacker._pending_attack_release_record)
	assert(_target.current_hp == 100, "physical projectile ignored accuracy=0")
	assert(not bool(_projectile_attacker.last_physical_hit_resolution.get("success", true)), "projectile miss was not recorded")
	_target.current_hp = 100
	_projectile_attacker.accuracy = 16
	assert(_projectile_attacker._launch_physical_projectile(_target, 10), "physical projectile hit fixture did not launch")
	_projectile_attacker._settle_physical_projectile_release(_projectile_attacker._pending_attack_release_record)
	assert(_target.current_hp == 90, "physical projectile did not use accuracy")
	assert(bool(_projectile_attacker.last_physical_hit_resolution.get("success", false)), "projectile hit was not recorded")

	# The fixed-area/special path opts out explicitly; this keeps the existing
	# magic damage contract independent from physical accuracy.
	_target.current_hp = 100
	_projectile_attacker.accuracy = 0
	_projectile_attacker._apply_attack_damage(_target, 10, false, 7)
	assert(_target.current_hp == 90, "non-physical settlement was incorrectly accuracy-gated")

	_target.queue_free()
	_melee_attacker.queue_free()
	_projectile_attacker.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"MONSTER_ACCURACY_RUNTIME_PASS "
		+ "strict_lt_boundaries=4 canonical_projection=1 "
		+ "melee_accuracy_gate=1 projectile_accuracy_gate=1 special_opt_out=1"
	)
	get_tree().quit(0)


func _assert_fixed_roll(
	attacker_accuracy: int,
	target_agility: int,
	random_roll: int,
	expected_hit: bool,
	case_name: String,
) -> void:
	_target.agility = target_agility
	_target.current_hp = 100
	_melee_attacker.accuracy = attacker_accuracy
	_melee_attacker._apply_attack_damage(_target, 10, true, random_roll)
	assert(
		(_target.current_hp == 90) == expected_hit,
		"%s damage outcome mismatch" % case_name,
	)
	var resolution: Dictionary = _melee_attacker.last_physical_hit_resolution
	assert(str(resolution.get("policy_id", "")) == CombatResolutionRules.PHYSICAL_HIT_POLICY_ID, "%s policy mismatch" % case_name)
	assert(int(resolution.get("accuracy", -1)) == attacker_accuracy, "%s accuracy evidence mismatch" % case_name)
	assert(int(resolution.get("target_agility", -1)) == target_agility, "%s agility evidence mismatch" % case_name)
	assert(int(resolution.get("random_roll", -1)) == random_roll, "%s roll evidence mismatch" % case_name)
	assert(bool(resolution.get("success", not expected_hit)) == expected_hit, "%s success evidence mismatch" % case_name)


func is_environment_point_blocked(_world_px: Vector2) -> bool:
	return false


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)
