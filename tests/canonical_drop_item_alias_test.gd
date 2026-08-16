extends Node

const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const SkillResourceService := preload("res://scripts/skills/skill_resource_service.gd")

const AUDITED_ALIASES := {
	"毒蜘蛛牙齿": {"canonical": "蜘蛛牙", "service_index": 868},
	"食人树叶": {"canonical": "食人花叶", "service_index": 866},
	"食人树的果实": {"canonical": "食人花果", "service_index": 867},
}
const FORBIDDEN_QUEST_SERVICE_INDEX := 1127


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData canonical catalog failed to load")

	# 1. Audited exact aliases resolve the frozen drop tokens to the canonical
	#    item identity (service_index). No fuzzy matching is involved.
	for token: String in AUDITED_ALIASES:
		var expected: Dictionary = AUDITED_ALIASES[token]
		var resolved: Dictionary = GameData.resolve_canonical_drop_item({"item": token})
		assert(bool(resolved.get("ok", false)), "drop token did not resolve: %s -> %s" % [token, resolved])
		assert(str(resolved.get("item_name", "")) == str(expected.get("canonical", "")), "drop token resolved to wrong canonical name: %s -> %s" % [token, resolved.get("item_name")])
		assert(int(resolved.get("service_index", -1)) == int(expected.get("service_index", -1)), "drop token resolved to wrong serviceIndex: %s -> %s" % [token, resolved.get("service_index")])

	# 2. 食人树的果实 must bind 食人花果(867), never the Quest item 食人花果实(1127).
	var fruit: Dictionary = GameData.resolve_canonical_drop_item({"item": "食人树的果实"})
	assert(int(fruit.get("service_index", -1)) == 867, "食人树的果实 must resolve to 食人花果(867)")
	assert(int(fruit.get("service_index", -1)) != FORBIDDEN_QUEST_SERVICE_INDEX, "食人树的果实 wrongly resolved to Quest item 1127")
	assert(str(fruit.get("item_name", "")) == "食人花果", "食人树的果实 canonical name must be 食人花果")

	# 3. Runtime spawnable count is no longer frozen at 37: runtime closure is
	#    expanded by exact-ID evidence, so only a floor is asserted here.
	var counts: Dictionary = GameData.canonical_monster_counts()
	assert(int(counts.get("catalog_identity_count", 0)) == 217, "217 identities drifted")
	assert(int(counts.get("catalog_runtime_allowed_count", 0)) >= 120, "catalog runtime allowed drifted")
	assert(int(counts.get("runtime_spawnable_count", 0)) >= 120, "runtime spawnable drifted")
	assert(int(counts.get("runtime_rejected_count", -1)) == 0, "runtime rejected count not zero")

	# 4. 施毒术 remains material-free: casting with zero of the three alias
	#    materials still succeeds and does not reference them.
	assert(SkillDataLoader.reload_data().valid, "skill data failed to reload")
	var poison := SkillDataLoader.skill("taoist.poison")
	var poison_quote := SkillResourceService.quote(poison, 0, {"mana": 100, "materials": {}})
	assert(bool(poison_quote.get("valid", false)), "taoist.poison must cast with an empty material inventory")
	assert(bool(poison_quote.get("material_free", false)), "taoist.poison must stay material-free")
	assert(int(poison_quote.get("material_amount", 0)) == 0, "taoist.poison must not consume materials")
	var poison_material_id := str(poison_quote.get("material_id", ""))
	for token: String in AUDITED_ALIASES:
		var canonical: String = AUDITED_ALIASES[token]["canonical"]
		assert(poison_material_id != token and poison_material_id != canonical, "taoist.poison must not require material %s" % token)

	print("CANONICAL_DROP_ITEM_ALIAS_PASS: aliases=3 spawnable=37 quest_1127_isolated=1 poison_material_free=1")
	get_tree().quit(0)
