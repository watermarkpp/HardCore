extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Service := preload("res://scripts/layers/runtime/relic_synthesis_service.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_process(false)
	PlayerState.level = 35
	PlayerState.gold = 800000
	check(Rules.recipe_professions(950101) == ["hc.profession.warrior", "hc.profession.wizard", "hc.profession.taoist"],
		"the actual relic recipe exposes the three existing formal profession owners in original order")
	check(Rules.recipe_professions(950202) == ["hc.profession.wizard"], "actual badge affinity is the registered wizard ID")
	var expected: Array[String] = ["wizard.lightning", "wizard.hell_lightning", "wizard.laser", "wizard.fire_wall", "wizard.ice_storm", "wizard.exploding_flame"]
	check(Rules.skill_ids_for("hc.profession.wizard") == expected,
		"formal profession selects the exact original ordered primary skill pool")
	var rng := RandomNumberGenerator.new()
	var old_rng := RandomNumberGenerator.new()
	rng.seed = 4816
	old_rng.seed = 4816
	var legacy := Rules.roll_instance(950101, "法师", old_rng)
	check(str(legacy.get("relic_roll", {}).get("skill_id", "")) == "wizard.ice_storm"
		and old_rng.state == 9008858216091737753, "original native seed 4816 keeps the exact primary roll and RNG state")
	var typed := Rules.roll_instance(950101, "hc.profession.wizard", rng)
	check(not typed.is_empty() and typed == legacy and rng.state == old_rng.state,
		"formal and explicit legacy-import entrances preserve the existing entire roll and RNG sequence")
	print("RELIC_IDENTITY_LEGACY_ROLL ", JSON.stringify(legacy), " state=", old_rng.state)
	var renamed := legacy.duplicate(true)
	renamed["name"] = "可改变的圣物展示文字"
	check(Rules.valid_instance(renamed, 950101), "actual relic validation is owned by its ID, roll and modifiers rather than display text")
	var forged := renamed.duplicate(true)
	forged["item_id"] = 950102
	check(not Rules.valid_instance(forged, 950101), "a matching display cannot override the explicit relic item ID")
	var initial_rng := rng.state
	for invalid: String in ["未知职业", "hc.profession.missing", "hc.skill.wizard.lightning"]:
		check(Rules.roll_instance(950101, invalid, rng).is_empty() and rng.state == initial_rng,
			"invalid profession rejects before real random draws: " + invalid)
	var authority: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Rules.DATA_PATH))
	var pools: Variant = authority.get("skill_pools", {})
	check(pools is Dictionary and pools.size() == 3, "the existing authoring source declares the profession-to-skill ID relations")
	var relation_count := 0
	if pools is Dictionary:
		for profession_id: String in pools:
			var skills: Array = pools[profession_id]
			for skill_id: String in skills:
				check(not Ids.resolve(profession_id, "profession").is_empty() and not Ids.resolve(skill_id, "skill").is_empty(),
					"declared primary relation has registered endpoints: " + profession_id + "/" + skill_id)
				relation_count += 1
	check(relation_count == 17, "all original seventeen skill choices have explicit stable endpoints")
	PlayerState.synthesis_tray = [{}, {}, {}, {}, {}, {}, {}, {}, {}]
	for index in range(4):
		var fragment := GameData.get_entity_record("hc.item.950001")
		PlayerState.synthesis_tray[index] = PlayerState._make_item_instance(str(fragment.name), fragment)
	var service := Service.new(PlayerState)
	service.configure_rng(rng)
	var quote := service.quote_synthesis(950102, [0, 1, 2, 3])
	check(quote.get("valid", false) and quote.get("profession_id") == "hc.profession.warrior" and not quote.has("skill_profession"),
		"the actual default recipe quote reads the sole player profession ID")
	quote = service.quote_synthesis(950102, [0, 1, 2, 3], "hc.profession.wizard")
	check(quote.get("valid", false) and quote.get("profession_id") == "hc.profession.wizard",
		"explicit formal recipe selection is kept as a typed quote owner")
	var before_tray: Array = PlayerState.synthesis_tray.duplicate(true)
	var before_gold := PlayerState.gold
	initial_rng = rng.state
	var invalid_quote := service.quote_synthesis(950102, [0, 1, 2, 3], "hc.skill.wizard.fireball")
	check(not invalid_quote.get("valid", false) and PlayerState.synthesis_tray == before_tray
		and PlayerState.gold == before_gold and rng.state == initial_rng, "cross-kind recipe identity cannot change materials, gold or randomness")
	if quote.get("valid", false):
		var committed := service.commit_synthesis(quote)
		check(committed.get("committed", false) and PlayerState.gold == before_gold - 400000
			and Rules.valid_instance(PlayerState.synthesis_tray[0], 950102), "actual typed quote reaches the real synthesis transaction exactly once")
		check(Rules.skill_ids_for("hc.profession.wizard").has(str(PlayerState.synthesis_tray[0].get("relic_roll", {}).get("skill_id", ""))),
			"the real output roll belongs to the selected formal skill pool")
		var output: Array = PlayerState.synthesis_tray.duplicate(true)
		check(not service.commit_synthesis(quote).get("committed", false) and PlayerState.synthesis_tray == output,
			"a completed typed quote cannot consume or reroll again")
	proof.write_receipt("relic_identity_relation_test", proof.records.size(), failures.size())
	print("RELIC_IDENTITY_RELATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
