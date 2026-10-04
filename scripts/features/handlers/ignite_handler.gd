extends RefCounted
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Cues := preload("res://scripts/features/presentation/cue_definitions.gd")
const ID := "hc.ignite.v1"
const EFFECT_ID := "hc.effect.ignite.v1"

# Pure handler: its only output is a closed command. It owns no HP, nodes,
# global random stream, lifecycle, timer or source registration.
static func commands(fact: Dictionary, binding: Dictionary) -> Array:
	var definition: Dictionary = binding.get("definition", {})
	var input_skill: Variant=fact.get("skill_id")
	if fact.get("source_class")=="child" and input_skill=="hc.child.death_burst.v1" \
		and fact.get("chain_context") is Dictionary \
		and fact.chain_context.get("contract_id")=="hardcore.combat.chain_context.v1":
		input_skill=fact.chain_context.get("root_skill_id")
	if definition.get("handler_id") != ID or definition.get("skill_id") != input_skill \
		or fact.get("source_class") not in definition.get("source_classes", []) \
		or not bool(fact.get("target_survived_commit",false)) or int(fact.get("actual_loss",0)) <= 0:
		return []
	var config: Dictionary = definition.config
	var domain := JSON.stringify(["hc.rng.trigger.v1",fact.release_id,fact.target,binding.handle,definition.mechanic_id])
	var rng := RandomNumberGenerator.new()
	rng.seed = domain.sha256_text().substr(0,15).hex_to_int()
	if rng.randf() >= float(config.chance): return []
	var raw := roundi(float(fact.actual_loss)*float(config.fraction))
	if raw <= 0: return []
	var cue_id: String = definition.get("cue_id","hc.cue.ignite.v1")
	var cue := Cues.definition(cue_id)
	if cue.is_empty(): return []
	var command := Graph.capture({"op":"ApplyStatus","effect_id":EFFECT_ID,"handler_id":ID,
		"source_handle":binding.handle,"mechanic_id":definition.mechanic_id,"target":fact.target,
		"historical_credit":fact.historical_credit,"raw_per_tick":raw,"period_usec":int(config.period_usec),
		"duration_usec":int(config.duration_usec),"time_domain":"simulation","damage_basis":"actual_hp_loss",
		"damage_channel":"magic_defense","source_class":"periodic","causes_struck":false,
		"direct_magic_walk_delay":false,"refresh_policy":"strongest_keep_phase","source_removed":"until_expired",
		"target_defense_sampling":"per_tick","expires_order":"tick_before_expiry",
		"cue_id":cue_id,"cue_policy":cue.policy})
	return [command.value] if bool(command.success) else []
