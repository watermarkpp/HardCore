extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const EnemyActorScript := preload("res://scripts/enemy.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()

	# Identity and boss rules are canonical-ID APIs.  A display name is opaque
	# metadata and a caller's boss flag cannot upgrade or downgrade a record.
	var ordinary_entry := MonsterIdentityScript.require_catalog_entry(64, "runtime")
	assert(not ordinary_entry.is_empty() and ordinary_entry.get("classification", "") == "ordinary", "ID 64 ordinary identity missing")
	var boss_entry := MonsterIdentityScript.require_catalog_entry(76, "runtime")
	assert(not boss_entry.is_empty() and boss_entry.get("classification", "") == "boss", "ID 76 boss identity missing")
	assert(int(MonsterIdentityScript.boss_rule({"monster_id": 76, "name": "wrong"}).get("monsterId", -1)) == 76, "ID 76 boss rule did not resolve canonically")
	assert(MonsterIdentityScript.boss_rule({"name": "old boss name"}).is_empty(), "name-only boss rule must fail closed")
	assert(MonsterIdentityScript.boss_rule({"monster_id": 64, "name": "wrong"}).is_empty(), "ordinary ID must not gain a boss rule from its name")

	var ordinary := EnemyActorScript.new()
	ordinary.setup({
		"monster_id": 64,
		"name": "local rename",
		"hp": 1,
		"attackMin": 1,
		"attackMax": 1,
	}, null, true)
	assert(ordinary.monster_id == 64 and not ordinary.is_boss, "caller boss flag changed ordinary ID 64")
	assert(ordinary.max_hp == 265 and ordinary.attack_min == 14 and ordinary.attack_max == 28, "ID 64 did not project canonical combat stats")
	assert(bool(ordinary.get_meta("caller_boss_ignored", false)), "ignored caller boss flag was not recorded")
	ordinary.free()

	var boss := EnemyActorScript.new()
	boss.setup({"monster_id": 76, "name": "local rename"}, null, false)
	assert(boss.monster_id == 76 and boss.is_boss, "caller false boss flag downgraded canonical boss ID 76")
	assert(boss.max_hp == 2200 and boss.attack_min == 35 and boss.attack_max == 60, "ID 76 did not project canonical service stats")
	boss.free()

	var name_only := EnemyActorScript.new()
	name_only.setup({"name": "old boss name", "hp": 9999}, null, true)
	assert(name_only.monster_id == -1 and bool(name_only.get_meta("canonical_rejected", false)), "name-only spawn did not fail closed")
	name_only.free()

	var unknown := EnemyActorScript.new()
	unknown.setup({"monster_id": 999999, "name": "wrong"}, null, true)
	assert(unknown.monster_id == -1 and bool(unknown.get_meta("canonical_rejected", false)), "unknown ID did not fail closed")
	unknown.free()

	# P3C keeps the exact Wooma variants active with independent IDs and formal
	# appearance/drop closure; never collapse them into the 76 identity.
	assert(not MonsterIdentityScript.require_catalog_entry(77, "runtime").is_empty(), "Wooma 77 must remain runtime-enabled")
	assert(not MonsterIdentityScript.require_catalog_entry(78, "editor").is_empty(), "Wooma 78 must remain editor-placeable")
	assert(not MonsterIdentityScript.require_catalog_entry(239, "runtime").is_empty(), "Wooma 239 must remain runtime-enabled")
	assert(MonsterIdentityScript.catalog_entry(239).get("classification", "") == "boss", "Wooma 239 must remain an independent boss identity")

	print("MONSTER_ID_CANONICAL_CONTRACT_PASS: id_only=1 caller_boss_ignored=1 fail_closed=1")
	get_tree().quit(0)
