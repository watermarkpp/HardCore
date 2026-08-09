class_name SkillResourceService
extends RefCounted

const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)

const MATERIAL_FREE_PROFESSION := "taoist"
const DOUBLE_MP_SKILL_ID := "taoist.poison"


static func quote(
	definition: Dictionary,
	rank: int,
	resource_context: Dictionary,
	cast_context := {}
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
	if int(resource_context.get("mana", 0)) < mp_cost:
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
