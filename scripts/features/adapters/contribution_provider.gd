extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
const Items := preload("res://scripts/items/item_extension_codec.gd")
const SourceRules := preload("res://scripts/features/adapters/contribution_source_rules.gd")

# The caller supplies the existing strict item consumer and skill eligibility.
# This provider owns no item attributes, progression, or saved equipment.
static func collect(bindings: Array, enabled: Array, equipment: Dictionary, profile_id: String,
	item_record: Callable, item_eligible: Callable, skill_learned: Callable) -> Dictionary:
	var sources: Array = []
	var errors: Array = []
	for binding: Dictionary in bindings:
		if binding.module_id not in enabled:
			continue
		match binding.kind:
			"affix":
				var definition:=SourceRules.affix_definition(binding.affix_id)
				if definition.is_empty():
					errors.append("unregistered_feature_affix:"+binding.affix_id); continue
				for slot: String in equipment:
					var instance: Variant=equipment[slot]
					if not instance is Dictionary or not bool(item_eligible.call(instance)): continue
					var base:=Items.base_record(instance)
					var slot_id:=str(Ids.resolve(slot,"slot").get("id",""))
					if slot_id.is_empty(): errors.append("unregistered_feature_slot:"+slot); continue
					for ordinal: int in SourceRules.matching_affix_indices(base,definition):
						var source: Dictionary={"slot":slot_id,"instance_id":base.instance_id,"mechanic_id":binding.mechanic_id,
							"extension_id":JSON.stringify(["affix",binding.affix_id,ordinal])}
						sources.append({"source":source,"mechanic_id":binding.mechanic_id})
			"embedded_item":
				for slot: String in equipment:
					var instance: Variant = equipment[slot]
					if not instance is Dictionary or not bool(item_eligible.call(instance)):
						continue
					var slot_id := str(Ids.resolve(slot, "slot").get("id", ""))
					if slot_id.is_empty():
						errors.append("unregistered_feature_slot:" + slot)
						continue
					for socket: Dictionary in Items.extensions(instance).get(Items.SOCKET_NAMESPACE, {}).get("sockets", []):
						var gem: Dictionary = socket.item
						var record: Dictionary = item_record.call(gem)
						if Ids.from_legacy("item", record.get("itemId", -1)) != binding.item_id: continue
						var source := {"slot": slot_id, "instance_id": gem.instance_id, "mechanic_id": binding.mechanic_id,
							"extension_id": JSON.stringify([instance.instance_id, socket.socket_id])}
						sources.append({"source": source, "mechanic_id": binding.mechanic_id})
			"item":
				for slot: String in equipment:
					var instance: Variant = equipment[slot]
					if not instance is Dictionary or not bool(item_eligible.call(instance)):
						continue
					var record: Dictionary = item_record.call(instance)
					if Ids.from_legacy("item", record.get("itemId", -1)) != binding.item_id:
						continue
					var identity: Variant = instance.get("instance_id", "")
					if not identity is String or identity.is_empty():
						errors.append("feature_item_missing_instance:" + slot)
						continue
					var slot_id := str(Ids.resolve(slot, "slot").get("id", ""))
					if slot_id.is_empty():
						errors.append("unregistered_feature_slot:" + slot)
						continue
					_append(sources, slot_id, identity, binding.mechanic_id)
			"skill":
				if bool(skill_learned.call(binding.skill_id)):
					_append(sources, "hc.slot.skill", "skill:" + profile_id + ":" + binding.skill_id, binding.mechanic_id)
			"rule":
				_append(sources, "hc.slot.rule", "rule:" + binding.rule_id, binding.mechanic_id)
	sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Compiler.source_handle(a.source) < Compiler.source_handle(b.source))
	return {"success":errors.is_empty(), "sources":Graph.capture(sources).value, "errors":errors}

static func _append(sources: Array, slot: String, instance: String, mechanic: String) -> void:
	sources.append({"source":{"slot":slot,"instance_id":instance,"mechanic_id":mechanic}, "mechanic_id":mechanic})
