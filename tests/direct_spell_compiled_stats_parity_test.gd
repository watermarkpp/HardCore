extends Node

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const CombatRuntimeService := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)

var _checks := 0
var _failures: Array[String] = []
var _owned_enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	_assert_canonical_compilation()
	_assert_compiled_alias_inputs()
	_assert_runtime_aliases_and_red_poison()
	_assert_reference_rng_parity()
	_assert_projectile_resolves_once()
	_assert_fail_closed_compilation()
	var counters := RuntimeDiagnostics.performance_counters()
	_assert(
		int(counters.get("direct_spell_full_monster_data_duplicates", -1)) == 0,
		"formal Enemy direct spell path must not deep-copy monster_data",
	)
	if not _failures.is_empty():
		push_error("DIRECT_SPELL_COMPILED_STATS_PARITY_FAIL: %s" % "; ".join(_failures))
		print("DIRECT_SPELL_COMPILED_STATS_PARITY_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		_cleanup_owned_enemies()
		RuntimeDiagnostics.set_device_lab_performance_enabled(false)
		get_tree().quit(1)
		return
	print(
		"DIRECT_SPELL_COMPILED_STATS_PARITY_PASS checks=%d snapshots=%d duplicates=%d"
		% [
			_checks,
			int(counters.get("direct_spell_stats_snapshot_count", 0)),
			int(counters.get("direct_spell_full_monster_data_duplicates", 0)),
		]
	)
	_cleanup_owned_enemies()
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	get_tree().quit(0)


func _assert_canonical_compilation() -> void:
	for monster_id: int in [74, 124, 218]:
		var entry := GameData.get_monster_by_id(monster_id)
		_assert(not entry.is_empty(), "canonical fixture missing ID%d" % monster_id)
		var enemy := _make_enemy(monster_id)
		var scalar := int(entry.get("combat", {}).get("stats", {}).get("magic_defense", -1))
		_assert(enemy.direct_spell_stats_valid, "ID%d direct spell stats rejected" % monster_id)
		_assert(
			enemy.direct_spell_magic_defense_min == maxi(0, scalar)
			and enemy.direct_spell_magic_defense_max == maxi(0, scalar),
			"ID%d scalar magic_defense did not compile to a fixed MAC range" % monster_id,
		)
		_assert(enemy.direct_spell_anti_magic_points == 0, "ID%d missing AntiMagic must be legal zero" % monster_id)


func _assert_runtime_aliases_and_red_poison() -> void:
	var enemy := _make_enemy(218)
	var base: Dictionary = {}
	_assert(enemy.direct_spell_runtime_stats_into(base), "compiled direct stats API rejected a valid target")
	_assert(
		int(base.get("anti_magic_points", -1)) == 0
		and int(base.get("magicEvasionPoints", -1)) == 0
		and int(base.get("antiMagicPoints", -1)) == 0
		and int(base.get("antiMagic", -1)) == 0
		and int(base.get("magic_evasion_percent", -1)) == 0
		and int(base.get("magicEvasionPercent", -1)) == 0,
		"direct spell AntiMagic aliases are incomplete",
	)
	_assert(
		int(base.get("magic_defense_min", -1)) == enemy.magic_defense
		and int(base.get("magic_defense_max", -1)) == enemy.magic_defense
		and int(base.get("mdefMin", -1)) == enemy.magic_defense
		and int(base.get("mdefMax", -1)) == enemy.magic_defense
		and int(base.get("MinMAC", -1)) == enemy.magic_defense
		and int(base.get("MaxMAC", -1)) == enemy.magic_defense,
		"direct spell MAC aliases are incomplete",
	)
	enemy.set_meta("canonical_red_poison", {
		"contract_id": "buff.taoist.red_poison.v1",
		"flat_ac_reduction": 7,
		"flat_mac_reduction": 2,
		"flat_reduction": 99,
		"expires_at_ms": Time.get_ticks_msec() + 60000,
	})
	_assert(enemy.direct_spell_runtime_stats_into(base), "active red poison rejected")
	_assert(
		int(base.get("flat_ac_reduction", -1)) == 7
		and int(base.get("flat_mac_reduction", -1)) == 2
		and int(base.get("magic_defense_min", -1)) == maxi(0, enemy.magic_defense - 2)
		and int(base.get("magic_defense_max", -1)) == maxi(0, enemy.magic_defense - 2),
		"red poison AC/MAC reductions were conflated",
	)
	enemy.set_meta("canonical_red_poison", {
		"flat_reduction": 5,
		"expires_at_ms": Time.get_ticks_msec() + 60000,
	})
	_assert(enemy.direct_spell_runtime_stats_into(base), "legacy red poison metadata rejected")
	_assert(
		int(base.get("magic_defense_min", -1)) == enemy.magic_defense,
		"legacy flat_reduction was applied without an explicit fallback flag",
	)
	enemy.set_meta("canonical_red_poison", {
		"flat_reduction": 5,
		"legacy_metadata_fallback": true,
		"expires_at_ms": Time.get_ticks_msec() + 60000,
	})
	_assert(enemy.direct_spell_runtime_stats_into(base), "explicit legacy red poison fallback rejected")
	_assert(
		int(base.get("magic_defense_min", -1)) == maxi(0, enemy.magic_defense - 5),
		"explicit legacy flat_reduction fallback did not affect MAC",
	)
	enemy.set_meta("canonical_red_poison", {
		"contract_id": "buff.taoist.red_poison.v1",
		"flat_ac_reduction": 7,
		"flat_mac_reduction": 2,
		"flat_reduction": 99,
		"expires_at_ms": Time.get_ticks_msec() - 1,
	})
	_assert(enemy.direct_spell_runtime_stats_into(base), "expired red poison rejected base stats")
	_assert(not enemy.has_meta("canonical_red_poison"), "expired red poison metadata was not cleared")
	_assert(
		int(base.get("magic_defense_min", -1)) == enemy.magic_defense,
		"expired red poison left a stale MAC reduction",
	)


func _assert_compiled_alias_inputs() -> void:
	var base_entry: Dictionary = GameData.get_monster_by_id(74).duplicate(true)
	var base_stats: Dictionary = base_entry.get("combat", {}).get("stats", {})
	base_stats.erase("magic_defense")
	base_stats["mdefMin"] = 4
	base_stats["mdefMax"] = 6
	for alias_pair: Array in [
		["magic_defense_min", "magic_defense_max"],
		["mdefMin", "mdefMax"],
		["MinMAC", "MaxMAC"],
	]:
		var alias_entry: Dictionary = base_entry.duplicate(true)
		var alias_stats: Dictionary = alias_entry["combat"]["stats"]
		alias_stats[str(alias_pair[0])] = 4
		alias_stats[str(alias_pair[1])] = 6
		var alias_enemy := EnemyActor.new()
		alias_enemy._compile_direct_spell_runtime_stats(alias_entry)
		_assert(
			alias_enemy.direct_spell_stats_valid
			and alias_enemy.direct_spell_magic_defense_min == 4
			and alias_enemy.direct_spell_magic_defense_max == 6,
			"MAC alias pair %s/%s did not compile"
			% [str(alias_pair[0]), str(alias_pair[1])],
		)
		alias_enemy.free()
	for anti_alias: String in [
		"anti_magic_points",
		"magicEvasionPoints",
		"antiMagicPoints",
		"antiMagic",
	]:
		var alias_entry: Dictionary = base_entry.duplicate(true)
		var alias_stats: Dictionary = alias_entry["combat"]["stats"]
		alias_stats[anti_alias] = 2
		var alias_enemy := EnemyActor.new()
		alias_enemy._compile_direct_spell_runtime_stats(alias_entry)
		_assert(
			alias_enemy.direct_spell_stats_valid
			and alias_enemy.direct_spell_anti_magic_points == 2,
			"AntiMagic alias %s did not compile" % anti_alias,
		)
		alias_enemy.free()
	var display_entry: Dictionary = base_entry.duplicate(true)
	var display_stats: Dictionary = display_entry["combat"]["stats"]
	display_stats["magic_evasion_percent"] = 20
	var display_enemy := EnemyActor.new()
	display_enemy._compile_direct_spell_runtime_stats(display_entry)
	_assert(
		display_enemy.direct_spell_stats_valid
		and display_enemy.direct_spell_anti_magic_points == 2,
		"magic_evasion_percent alias did not compile",
	)
	display_enemy.free()


func _assert_reference_rng_parity() -> void:
	var enemy := _make_enemy(218)
	enemy.max_hp = 100000
	enemy.current_hp = enemy.max_hp
	var runtime := CombatRuntimeService.new()
	var target_stats: Dictionary = {}
	for sample: int in range(64):
		var reference_rng := RandomNumberGenerator.new()
		var actual_rng := RandomNumberGenerator.new()
		reference_rng.seed = 9000 + sample
		actual_rng.seed = 9000 + sample
		var reference_stats: Dictionary = {}
		enemy.direct_spell_runtime_stats_into(reference_stats)
		var reference_anti_magic_roll := reference_rng.randi_range(
			0,
			CombatResolutionRules.ANTI_MAGIC_ROLL_SIDES - 1,
		)
		var expected := CombatResolutionRules.resolve_direct_spell_damage(
			"wizard.fireball",
			37,
			reference_stats,
			reference_anti_magic_roll,
			Callable(self, "_resolve_mac").bind(reference_rng),
		)
		enemy.current_hp = enemy.max_hp
		var actual: Dictionary = runtime.apply_enemy_direct_spell_damage(
			enemy,
			"wizard.fireball",
			37,
			null,
			actual_rng,
			Callable(self, "_resolve_mac").bind(actual_rng),
			-1,
			target_stats,
		)
		_assert(
			int(actual.get("anti_magic_roll", -1)) == int(expected.get("anti_magic_roll", -2))
			and int(actual.get("magic_defense_roll", -1)) == int(expected.get("magic_defense_roll", -1))
			and int(actual.get("final_damage", -1)) == int(expected.get("final_damage", -2))
			and reference_rng.state == actual_rng.state,
			"direct spell RNG or final damage diverged at sample %d" % sample,
		)
		_assert(
			enemy.current_hp == enemy.max_hp - int(expected.get("final_damage", 0)),
			"direct spell HP commit diverged at sample %d" % sample,
		)
		_assert(
			actual_rng.randi() == reference_rng.randi(),
			"direct spell RNG continuation diverged at sample %d" % sample,
		)
	runtime.free()


func _assert_projectile_resolves_once() -> void:
	var enemy := _make_enemy(218)
	enemy.max_hp = 100
	enemy.current_hp = 100
	var projectile := SkillProjectile.new()
	projectile.effect = "damage"
	projectile.damage = 7
	projectile.resolution_skill_id = "wizard.fireball"
	projectile.magic_defense_adapter = Callable(self, "_zero_magic_defense")
	projectile.anti_magic_roll_override = 0
	projectile._apply_hit(enemy)
	_assert(
		enemy.current_hp == 93,
		"projectile direct-spell path applied damage more than once",
	)
	projectile.free()


func _resolve_mac(
	_skill_id: String,
	damage_after_anti_magic: int,
	target_stats: Dictionary,
	rng: RandomNumberGenerator,
) -> int:
	var defense_min := int(target_stats.get("magic_defense_min", 0))
	var defense_max := int(target_stats.get("magic_defense_max", defense_min))
	return maxi(0, damage_after_anti_magic - rng.randi_range(defense_min, defense_max))


func _zero_magic_defense(
	_skill_id: String,
	damage_after_anti_magic: int,
	_target_stats: Dictionary,
) -> int:
	return damage_after_anti_magic


func _assert_fail_closed_compilation() -> void:
	var unknown := EnemyActor.new()
	unknown.setup({"monster_id": 999999}, null, false)
	_assert(not unknown.direct_spell_stats_valid, "unknown monster compiled direct spell stats")
	unknown.free()
	var retired := EnemyActor.new()
	retired.setup({"monster_id": 71}, null, false)
	_assert(not retired.direct_spell_stats_valid, "retired monster compiled direct spell stats")
	retired.free()
	var malformed := _make_enemy(74)
	var malformed_entry := GameData.get_monster_by_id(74).duplicate(true)
	malformed_entry["combat"]["stats"]["magic_defense"] = "not-a-number"
	malformed._compile_direct_spell_runtime_stats(malformed_entry)
	_assert(
		not malformed.direct_spell_stats_valid
		and str(malformed.get_meta("direct_spell_stats_rejection_reason", ""))
		== "canonical_magic_defense_malformed",
		"malformed canonical MAC did not fail closed",
	)


func _make_enemy(monster_id: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), null, false)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.set_process(false)
	enemy.set_physics_process(false)
	add_child(enemy)
	_owned_enemies.append(enemy)
	return enemy


func _cleanup_owned_enemies() -> void:
	for enemy: EnemyActor in _owned_enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_owned_enemies.clear()


func _assert(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
