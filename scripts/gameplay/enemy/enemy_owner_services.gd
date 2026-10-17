extends RefCounted

## Construct once on S and retain across map/WorldCore replacement. The old
## statics were process-owner shared, so transition alone is not a cache reset.
const FrameBudget := preload("res://scripts/gameplay/enemy/enemy_owner_frame_budget.gd")
const DecisionBudget := preload("res://scripts/gameplay/enemy/enemy_owner_decision_budget.gd")
const ContextToken := preload("res://scripts/gameplay/enemy/enemy_owner_context_token.gd")
const Footprint := preload("res://scripts/gameplay/enemy/enemy_owner_skill_footprint.gd")
const Terrain := preload("res://scripts/gameplay/enemy/enemy_owner_terrain_navigation.gd")
const Polygon := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_runtime.gd")
const Crowd := preload("res://scripts/gameplay/enemy/enemy_owner_crowd_position.gd")
var _owner := OS.get_thread_caller_id()
var _configured := false
var frame_budget: RefCounted
var decision_budget: RefCounted
var context_token: RefCounted
var skill_footprint: RefCounted
var terrain: RefCounted
var polygon: RefCounted
var crowd: RefCounted

func owner_thread_id() -> int:
	return _owner

func configure_owner(providers: Dictionary, actor_access: RefCounted) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner:
		push_error("Enemy owner services configured twice or across owners")
		return false
	for name in ["Engine", "Time", "ProjectSettings", "phase", "WorldSpatialRulesScript"]:
		if not providers.has(name):
			push_error("Enemy owner provider missing: " + name)
			return false
	var candidates := [FrameBudget.new(), DecisionBudget.new(), ContextToken.new(), Footprint.new(), Terrain.new(), Polygon.new(), Crowd.new()]
	var bindings: Dictionary = providers.duplicate()
	bindings.FrameBudget = candidates[0]
	bindings.HCPPolyRuntime = candidates[5]
	for service: RefCounted in candidates:
		if not service.configure_owner(bindings, actor_access):
			return false
	frame_budget = candidates[0]
	decision_budget = candidates[1]
	context_token = candidates[2]
	skill_footprint = candidates[3]
	terrain = candidates[4]
	polygon = candidates[5]
	crowd = candidates[6]
	_configured = true
	return true
