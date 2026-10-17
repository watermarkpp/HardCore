extends Node
const LootModel := preload("res://scripts/gameplay/profile/loot_model.gd")
const RuleSet := preload("res://scripts/gameplay/profile/profile_rule_set.gd")
const Proof = preload("res://tests/framework/helpers/check_receipt.gd")
var proof = Proof.new()
var failures: Array[String] = []
var checks = 0
func _ready() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	check(PlayerState.has_method("profile_core_for_owner"), "legacy profile uses one explicit domain core")
	if failures.is_empty():
		var core: Variant = PlayerState.call("profile_core_for_owner")
		check(not core is Node, "profile authority lives outside SceneTree")
		var gold_before: int = PlayerState.gold
		core.gold = 123
		check(PlayerState.gold == 123, "legacy reads the core economic state")
		PlayerState.gold = 140
		check(core.gold == 140, "legacy writes the same core economic state")
		PlayerState.gold = gold_before
		var saved_inventory: Array = core.inventory
		core.inventory = [{"item_id": 1, "instance_id": "old", "count": 1}]
		var merged: Array = core._loot_inventory_after_immediate_uses(
			[{"item_id": 1, "instance_id": "old", "count": 3}],
			[{"item_id": 1, "instance_id": "old", "count": 8}])
		check(merged == [{"item_id": 1, "instance_id": "old", "count": 6}], "inflight loot retains exact immediate consumption delta")
		core.inventory = [{}]
		merged = core._loot_inventory_after_immediate_uses(
			[{"item_id": 1, "instance_id": "old", "count": 3}],
			[{"item_id": 1, "instance_id": "old", "count": 8}])
		check(merged == [{"item_id": 1, "instance_id": "old", "count": 5}], "consuming last old item preserves newly collected remainder")
		core.inventory = saved_inventory
		check(core._json_persistence == PlayerState._json_persistence and core._world_json_persistence == PlayerState._world_json_persistence, "legacy and domain share the existing two ordered writers")
		var old_buffs: Dictionary = core.temporary_item_buffs
		core.temporary_item_buffs = {"u_service": {"remaining": 12.0}}
		core.service_receipts()
		check(core.temporary_item_buffs.u_service.remaining == 12.0, "receipt U service never advances profile gameplay clocks")
		core.temporary_item_buffs = old_buffs
	check(LootRuntime.has_method("loot_core_for_owner"), "legacy loot uses one explicit domain core")
	if failures.is_empty():
		var core: Variant = PlayerState.profile_core_for_owner()
		var local_rules := RuleSet.new(core._content_port)
		var local_instances: Variant = local_rules.item_instances
		check(not local_instances is Node and local_instances != core._rules.item_instances, "each domain owns its rule caches outside SceneTree")
		var catalog: Dictionary = GameData.get_item_record("木剑")
		var generated: Dictionary = local_rules.item_instances.create_instance(catalog, "profile_rules_same_source_seed")
		var expected: Dictionary = core._rules.item_instances.create_instance(catalog, "profile_rules_same_source_seed")
		check(not generated.is_empty() and generated == expected, "owner-local item creation preserves the exact same seeded instance")
		var main_cache_count: int = core._rules.item_instances._validated_snapshots.size()
		check(local_rules.item_instances.validate_instance(generated, catalog), "owner-local item validation accepts actual generated instance")
		check(local_rules.item_instances._validated_snapshots.size() > 0 and core._rules.item_instances._validated_snapshots.size() == main_cache_count, "validation mutates only its owning cache")
		var local_stats: Dictionary = local_rules.professions.stats_for_level("hc.profession.warrior", 51)
		check(local_stats == core._rules.professions.stats_for_level("hc.profession.warrior", 51) and local_rules.professions._base_growth_cache.size() == 1, "profession growth shares rules while retaining owner-local cache")
		var model := LootModel.new(core._content_port)
		var legacy_loot_core: Variant = LootRuntime.loot_core_for_owner()
		check(not legacy_loot_core is Node, "legacy loot authority lives outside SceneTree")
		for monster_id: int in [64, 76]:
			var legacy_rng := RandomNumberGenerator.new()
			var domain_rng := RandomNumberGenerator.new()
			legacy_rng.seed = 20261014 + monster_id
			domain_rng.seed = legacy_rng.seed
			var legacy_roll: Dictionary = LootRuntime.roll_monster_drops(monster_id, legacy_rng, true)
			var domain_roll: Dictionary = model.roll_monster_drops(monster_id, domain_rng, true)
			check(bool(domain_roll.configured) and legacy_roll == domain_roll, "legacy and domain share exact audited drop result for %d" % monster_id)
			check(legacy_rng.state == domain_rng.state, "drop extraction preserves RNG consumption for %d" % monster_id)
	if not proof.write_receipt("multicore_profile_model_20261014", checks, failures.size()): failures.append("receipt")
	print("MULTICORE_PROFILE_MODEL_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)