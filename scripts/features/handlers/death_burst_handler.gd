extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const ID := "hc.death_burst.v1"
const ACTION_ID := "hc.child.death_burst.v1"
const CHAIN_CONTEXT := "hardcore.combat.chain_context.v1"
const MAX_EXACT_INTEGER := 9007199254740991

# Pure closed-command construction. It has no actor, HP, planner, signal,
# random stream or queue authority. Registry publication stays disabled until
# the complete admitted child port and producer lifecycle are installed.
static func commands(fact: Dictionary, binding: Dictionary) -> Array:
	var definition: Variant=binding.get("definition")
	if not definition is Dictionary or definition.get("handler_id")!=ID \
		or not definition.get("mechanic_id") is String or definition.mechanic_id.is_empty() \
		or not binding.get("handle") is String or binding.handle.is_empty(): return []
	var config: Variant=definition.get("config")
	if not config is Dictionary or not _keys(config,["fraction","radius_gu","maximum_generation"]) \
		or not _number(config.fraction) or float(config.fraction)<=0 or float(config.fraction)>1 \
		or not _number(config.radius_gu) or float(config.radius_gu)<=0 \
		or not _integer(config.maximum_generation) or int(config.maximum_generation)<=0: return []
	if not Vector2(float(config.radius_gu),0.0).is_finite(): return []
	if not _first_death(fact) or not definition.get("source_classes") is Array \
		or fact.get("source_class") not in ["direct","periodic","child"] \
		or fact.source_class not in definition.source_classes: return []
	var chain: Variant=fact.get("chain_context")
	if not chain is Dictionary or not _keys(chain,["contract_id","root_release_id","release_id",
		"parent_release_id","root_skill_id","generation","maximum_generation"]) \
		or chain.contract_id!=CHAIN_CONTEXT: return []
	for key: String in ["root_release_id","release_id","root_skill_id"]:
		if not chain[key] is String or chain[key].is_empty(): return []
	if not chain.parent_release_id is String or not _integer(chain.generation) or not _integer(chain.maximum_generation) \
		or chain.maximum_generation!=config.maximum_generation or chain.generation>chain.maximum_generation \
		or chain.release_id!=fact.get("release_id") or chain.root_skill_id!=definition.get("skill_id"): return []
	var generation:=int(chain.generation)
	if generation==0 and (chain.release_id!=chain.root_release_id or not chain.parent_release_id.is_empty()): return []
	if generation>0 and (chain.parent_release_id.is_empty() or chain.release_id==chain.root_release_id): return []
	if (fact.source_class=="direct" and generation!=0) or (fact.source_class=="child" and generation==0): return []
	# This is the authored finite transition rule. Its entire potential work
	# must already have been compiled and reserved by the eventual root port.
	if generation==int(chain.maximum_generation): return []
	if not fact.get("fact_id") is String or fact.fact_id.is_empty() or not fact.get("historical_credit") is Dictionary \
		or not fact.get("target") is Dictionary or not _keys(fact.target,["world","runtime_id","life_generation"]) \
		or not fact.target.world is Dictionary or fact.target.world.is_empty() \
		or not _integer(fact.target.runtime_id) or int(fact.target.runtime_id)<=0 \
		or not _integer(fact.target.life_generation) or int(fact.target.life_generation)<=0: return []
	var origin: Variant=fact.get("commit_ground_origin")
	if not origin is Dictionary or not _keys(origin,["x","y"]) or not _number(origin.x) or not _number(origin.y): return []
	if not Vector2(float(origin.x),float(origin.y)).is_finite(): return []
	var raw:=roundi(float(fact.actual_loss)*float(config.fraction))
	if raw<=0: return []
	var captured:=Graph.capture({"op":"RequestChildAction","handler_id":ID,"action_id":ACTION_ID,
		"source_handle":binding.handle,"mechanic_id":definition.mechanic_id,
		"root_release_id":chain.root_release_id,"root_skill_id":chain.root_skill_id,
		"parent_release_id":fact.release_id,"parent_fact_id":fact.fact_id,"parent_target":fact.target,
		"generation":generation+1,"maximum_generation":int(chain.maximum_generation),
		"origin":origin,"radius_gu":float(config.radius_gu),"raw_damage":raw,"damage_basis":"actual_hp_loss",
		"historical_credit":fact.historical_credit,"source_class":"child","damage_channel":"magic_defense",
		"causes_struck":false,"direct_magic_walk_delay":false},128,8)
	return [captured.value] if captured.success else []

static func _first_death(fact: Dictionary) -> bool:
	if fact.get("contract_id")!="hardcore.combat.damage_fact.v1" \
		or fact.get("damage_channel") not in ["physical","magic_defense"] \
		or not fact.get("target_survived_commit") is bool or fact.target_survived_commit: return false
	for field: String in ["hp_before","hp_after","actual_loss","requested_damage"]:
		if not _integer(fact.get(field)): return false
	return int(fact.hp_before)>0 and int(fact.hp_after)==0 and int(fact.actual_loss)==int(fact.hp_before) \
		and int(fact.requested_damage)>=int(fact.actual_loss)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value)>=0 and float(value)<=MAX_EXACT_INTEGER and float(value)==floor(float(value))

static func _keys(value: Dictionary, required: Array) -> bool:
	if value.size()!=required.size(): return false
	for key: String in required:
		if not value.has(key): return false
	return true
