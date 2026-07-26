class_name TaoistSkillRuntime
extends RefCounted

## Implemented in the taoist phase. This typed stub keeps the router loadable
## while the feature flag remains integration-disabled.
static func execute(definition: Dictionary, _request: Dictionary, _rng: RefCounted) -> Dictionary:
	return {
		"accepted": false,
		"effect_success": false,
		"reason": "taoist_runtime_not_enabled",
		"runtime_family": str(definition.get("mechanics", {}).get("runtime_family", "")),
	}
