extends RefCounted

const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")

# Trusted built-in presentation handlers. Authoring selects a stable cue;
# it cannot load arbitrary scripts or introduce a second audio mapping.
const DEFINITIONS := {
	"hc.cue.ignite.v1":{"policy":"optional_procedural","resource_ids":[]},
	"hc.cue.ignite.fire_sword.v1":{"policy":"required_procedural","resource_ids":["hc.resource.sound.fire_sword.attack"]},
	"hc.cue.ignite.ice_storm.v1":{"policy":"required_procedural","resource_ids":["hc.resource.sound.ice_storm.effect"]}
}

static func definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id,{})

static func requirements(id: String) -> Dictionary:
	var cue := definition(id)
	if cue.is_empty(): return {"success":false,"paths":[],"records":[]}
	var records: Array = []
	var paths: Array = []
	for resource_id: String in cue.resource_ids:
		var record := Registry.record_by_id(resource_id)
		if record.is_empty(): return {"success":false,"paths":[],"records":[]}
		records.append(record)
		paths.append(record.path)
	return {"success":true,"paths":paths,"records":records}
