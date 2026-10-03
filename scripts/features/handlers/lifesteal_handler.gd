extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const ID := "hc.lifesteal.v1"

# The committed fact is the sole damage basis. This pure handler never
# touches HP, nodes, RNG, resources or another handler.
static func commands(fact: Dictionary, binding: Dictionary) -> Array:
	var definition: Dictionary = binding.definition
	if definition.handler_id != ID or definition.skill_id != fact.skill_id \
		or fact.source_class != "direct" or int(fact.actual_loss) <= 0 or fact.source.is_empty(): return []
	var amount := floori(float(fact.actual_loss)*float(definition.config.fraction))
	if amount <= 0: return []
	var command := Graph.capture({"op":"ModifyResource","handler_id":ID,"resource":"hp","mode":"restore",
		"recipient":fact.source,"amount":amount,"source_handle":binding.handle,"mechanic_id":definition.mechanic_id,
		"damage_basis":"actual_hp_loss","source_class":"reaction"})
	return [command.value] if command.success else []
