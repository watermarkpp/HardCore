extends Node

## Inventory is structural evidence, not proof of unexecuted attack families.
func _ready() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/runtime/canonical_monster_catalog.json"))
	var rows: Array = []
	var seen: Dictionary = {}
	for entry: Dictionary in catalog.entries:
		var mid := int(entry.monster_id)
		assert(not seen.has(mid), "duplicate actual catalog identity")
		seen[mid] = true
		var actor := EnemyActor.new()
		actor.setup(GameData.get_monster_by_id(mid), null, false)
		var profile := actor.behavior_profile
		rows.append({"monster_id": mid, "canonical_name": entry.canonical_name,
			"runtime_allowed": entry.runtime_allowed, "combat_enabled": actor.combat_enabled,
			"body_tier": entry.combat.get("body_profile", {}).get("tier", ""), "radius_gu": actor.combat_radius_gu,
			"delivery_kind": str(actor.attack_delivery_rule.get("kind", "")),
			"hc_melee": actor._hc_standard_melee(), "area_magic": actor._uses_area_magic_delivery(),
			"area_attack": bool(actor.area_attack_rule.get("enabled", false)),
			"summon": bool(actor.summon_rule.get("enabled", false)),
			"raw_attack_ms": profile.get("timing", {}).get("attackIntervalMs", null),
			"effective_attack_s": actor._attack_interval,
			"ai_resolution": profile.get("serviceBehavior", {}).get("resolutionStatus", ""),
			"behavior_verification": "NOT_RUN", "inventory": "PASS"})
		actor.free()
	assert(seen.size() == catalog.entries_by_id.size(), "actual ID-index cardinality mismatch")
	FileAccess.open("res://outputs/test_logs/r4_runtime_capabilities.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "catalog_count": rows.size(), "meaning": "inventory only; behavior_verification is updated by evidence table, never inferred from an ID count"}, "  "))
	print("R4_RUNTIME_CAPABILITY_INVENTORY_PASS count=%d" % rows.size())
	get_tree().quit(0)
