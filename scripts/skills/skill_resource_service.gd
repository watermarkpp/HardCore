class_name SkillResourceService
extends RefCounted

const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)
const SkillDataLoaderScript := preload(
	"res://scripts/skills/skill_data_loader.gd"
)

const MATERIAL_FREE_PROFESSION := "taoist"
const DOUBLE_MP_SKILL_ID := "taoist.poison"
const DUAL_DEFENSE_CAST_CONTRACT_ID := "skills.taoist.dual_defense_cast.v1"
const DEFENSE_SKILL_IDS := {
	"taoist.defense": true,
	"taoist.magic_defense": true,
}
## Stable combined order: source-of-truth order (magic_defense=28,
## defense=29) so integration can share one cooldown/resource transaction.
const DUAL_DEFENSE_COMBINED_SKILL_IDS: Array[String] = [
	"taoist.magic_defense",
	"taoist.defense",
]


static func quote(
	definition: Dictionary,
	rank: int,
	resource_context: Dictionary,
	cast_context := {}
) -> Dictionary:
	var skill_id := str(definition.get("skill_id", ""))
	var dual_context: Variant = cast_context.get("dual_defense_context", {})
	if (
		DEFENSE_SKILL_IDS.has(skill_id)
		and dual_context is Dictionary
		and not (dual_context as Dictionary).is_empty()
	):
		var partner_skill_id := str((dual_context as Dictionary).get(
			"partner_skill_id",
			""
		))
		if not partner_skill_id.is_empty():
			return _quote_dual_defense(
				definition,
				rank,
				partner_skill_id,
				int((dual_context as Dictionary).get("partner_rank", rank)),
				resource_context
			)
	return _quote_single(definition, rank, resource_context, cast_context)


static func committed_context(resource_context: Dictionary, quote_result: Dictionary) -> Dictionary:
	var result := resource_context.duplicate(true)
	if not bool(quote_result.get("valid", false)):
		return result
	result["mana"] = maxi(0, int(result.get("mana", 0)) - int(quote_result.get("mp_cost", 0)))
	var material_id := str(quote_result.get("material_id", ""))
	var material_amount := int(quote_result.get("material_amount", 0))
	if not material_id.is_empty() and material_amount > 0:
		var materials: Dictionary = result.get("materials", {}).duplicate(true)
		materials[material_id] = maxi(0, int(materials.get(material_id, 0)) - material_amount)
		result["materials"] = materials
	return result


static func _quote_single(
	definition: Dictionary,
	rank: int,
	resource_context: Dictionary,
	cast_context: Dictionary,
	skip_mana_check := false
) -> Dictionary:
	var safe_rank := SkillRankResolverScript.safe_effective_rank(rank)
	var mp_costs: Array = definition.get("mp_cost_by_rank", [])
	var mp_cost := (
		maxi(
			0,
			SkillRankResolverScript.linear_int(mp_costs, safe_rank)
		)
		if not mp_costs.is_empty()
		else 0
	)
	var skill_id := str(definition.get("skill_id", ""))
	var material_free := str(definition.get("class", "")) == MATERIAL_FREE_PROFESSION
	if material_free and skill_id == DOUBLE_MP_SKILL_ID:
		mp_cost *= 2
	if (
		str(definition.get("mechanics", {}).get("runtime_family", "")) == "next_melee_charge"
		and bool(cast_context.get("charge_consumed", false))
		and not bool(cast_context.get("direct_toggle_release", false))
	):
		mp_cost = 0
	var resource: Dictionary = definition.get("resource", {})
	var item: Variant = resource.get("item")
	var amounts: Array = resource.get("amount_by_rank", [])
	var item_amount := (
		maxi(
			0,
			SkillRankResolverScript.linear_int(amounts, safe_rank)
		)
		if not amounts.is_empty()
		else 0
	)
	if material_free:
		item = null
		item_amount = 0
	if (
		str(definition.get("mechanics", {}).get("runtime_family", "")) == "persistent_main_pet"
		and bool(cast_context.get("has_main_pet", false))
	):
		item_amount = 0
	var materials: Dictionary = resource_context.get("materials", {})
	var selected_item := str(resource_context.get("selected_material", item if item != null else ""))
	if material_free:
		selected_item = ""
	if item != null and str(item) == "selected_poison_powder" and selected_item not in ["grey_powder", "yellow_powder"]:
		return {"valid": false, "reason": "selected_poison_powder", "mp_cost": mp_cost}
	if (
		not skip_mana_check
		and int(resource_context.get("mana", 0)) < mp_cost
	):
		return {"valid": false, "reason": "insufficient_mana", "mp_cost": mp_cost}
	if item != null and item_amount > 0 and int(materials.get(selected_item, 0)) < item_amount:
		return {
			"valid": false,
			"reason": "insufficient_material",
			"material_id": selected_item,
			"material_amount": item_amount,
			"mp_cost": mp_cost,
		}
	return {
		"valid": true,
		"reason": "",
		"mp_cost": mp_cost,
		"material_id": selected_item,
		"material_amount": item_amount,
		"consume_timing": str(resource.get("consume_timing", resource.get("mp_consume_timing", ""))),
	}


static func _quote_dual_defense(
	primary_definition: Dictionary,
	primary_rank: int,
	partner_skill_id: String,
	partner_rank: int,
	resource_context: Dictionary
) -> Dictionary:
	## Single transaction: one quote call prices both currently-effective
	## levels and returns the summed MP plus per-skill components. No caller
	## may issue two independent quotes that could disagree.
	var primary_skill_id := str(primary_definition.get("skill_id", ""))
	if partner_skill_id == primary_skill_id:
		return _invalid_dual_quote("invalid_combined_defense_partner")
	if not DEFENSE_SKILL_IDS.has(partner_skill_id):
		return _invalid_dual_quote("unknown_skill")
	var partner_definition := SkillDataLoaderScript.skill(partner_skill_id)
	if partner_definition.is_empty():
		return _invalid_dual_quote("unknown_skill")
	var primary_quote := _quote_single(
		primary_definition,
		primary_rank,
		resource_context,
		{},
		true
	)
	var partner_quote := _quote_single(
		partner_definition,
		partner_rank,
		resource_context,
		{},
		true
	)
	var components: Array[Dictionary] = []
	for skill_id: String in DUAL_DEFENSE_COMBINED_SKILL_IDS:
		if skill_id == primary_skill_id:
			components.append({
				"skill_id": skill_id,
				"rank": SkillRankResolverScript.safe_effective_rank(primary_rank),
				"mp_cost": int(primary_quote.get("mp_cost", 0)),
				"material_id": str(primary_quote.get("material_id", "")),
				"material_amount": int(primary_quote.get("material_amount", 0)),
			})
		else:
			components.append({
				"skill_id": skill_id,
				"rank": SkillRankResolverScript.safe_effective_rank(partner_rank),
				"mp_cost": int(partner_quote.get("mp_cost", 0)),
				"material_id": str(partner_quote.get("material_id", "")),
				"material_amount": int(partner_quote.get("material_amount", 0)),
			})
	var primary_valid := bool(primary_quote.get("valid", false))
	var partner_valid := bool(partner_quote.get("valid", false))
	var total_mp := (
		int(primary_quote.get("mp_cost", 0))
		+ int(partner_quote.get("mp_cost", 0))
	)
	var reason := ""
	if not primary_valid:
		reason = str(primary_quote.get("reason", "insufficient_resource"))
	elif not partner_valid:
		reason = str(partner_quote.get("reason", "insufficient_resource"))
	elif int(resource_context.get("mana", 0)) < total_mp:
		reason = "insufficient_mana"
	return {
		"valid": reason.is_empty(),
		"reason": reason,
		"mp_cost": total_mp,
		"material_id": "",
		"material_amount": 0,
		"consume_timing": str(primary_quote.get("consume_timing", "")),
		"dual_defense": true,
		"combined_cast_contract_id": DUAL_DEFENSE_CAST_CONTRACT_ID,
		"combined_skill_ids": DUAL_DEFENSE_COMBINED_SKILL_IDS.duplicate(),
		"mp_components": components,
	}


static func _invalid_dual_quote(reason: String) -> Dictionary:
	return {
		"valid": false,
		"reason": reason,
		"mp_cost": 0,
		"material_id": "",
		"material_amount": 0,
		"consume_timing": "",
		"dual_defense": true,
		"combined_cast_contract_id": DUAL_DEFENSE_CAST_CONTRACT_ID,
		"combined_skill_ids": [],
		"mp_components": [],
	}
