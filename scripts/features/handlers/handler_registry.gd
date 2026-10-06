extends RefCounted

const Ignite := preload("res://scripts/features/handlers/ignite_handler.gd")
const Lifesteal := preload("res://scripts/features/handlers/lifesteal_handler.gd")
const DeathBurst := preload("res://scripts/features/handlers/death_burst_handler.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const IDS := [Ignite.ID,Lifesteal.ID,DeathBurst.ID]
const CONTRACTS := {
	"hc.ignite.v1":{"capabilities":["combat.post_hit","effects.periodic","effects.layered_status"],"commands":1,"states":1,
		"lifecycle":"until_expired","effect_id":"hc.effect.ignite.v1","cue":true},
	"hc.lifesteal.v1":{"capabilities":["combat.post_hit","combat.heal"],"commands":1,"states":0,
		"lifecycle":"immediate","effect_id":"","cue":false},
	"hc.death_burst.v1":{"capabilities":["combat.post_hit","combat.child_action"],"commands":1,"states":0,
		"lifecycle":"finite_chain","effect_id":"","cue":false}
}

static func contract(id: String) -> Dictionary:
	return Graph.capture(CONTRACTS.get(id,{})).value

static func commands(fact: Dictionary, binding: Dictionary) -> Array:
	match binding.definition.handler_id:
		Ignite.ID: return Ignite.commands(fact,binding)
		Lifesteal.ID: return Lifesteal.commands(fact,binding)
		DeathBurst.ID: return DeathBurst.commands(fact,binding)
	return []

static func persistent_binding_count(bindings: Array) -> int:
	var result := 0
	for binding: Dictionary in bindings:
		result += int(CONTRACTS.get(binding.definition.handler_id,{}).get("states",0))
	return result
