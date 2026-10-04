extends RefCounted

# A pure request owner. It does not accept gameplay, reserve capacity, query
# targets, write HP or allocate another planner. Root admission is a separate
# prerequisite before the eventual domain consumer executes a planned child.
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
const Cast := preload("res://scripts/skills/skill_cast_request.gd")
const PATH := "res://assets/data/features/child_actions_v1.json"
const CONTRACT := "hardcore.child_action_definitions.v1"
const COMMAND_FIELDS := ["op","handler_id","action_id","source_handle","mechanic_id",
	"root_release_id","root_skill_id","parent_release_id","parent_fact_id","parent_target",
	"generation","maximum_generation","origin","radius_gu","raw_damage","damage_basis",
	"historical_credit","source_class","damage_channel","causes_struck","direct_magic_walk_delay"]
var _world: RefCounted
var _command: Dictionary = {}
var _definition: Dictionary = {}
var _release_id := ""
var _seed := 0
static var _definitions: Dictionary = {}
static var _catalog_attempted := false

static func create(command: Dictionary, world: RefCounted, release_id: String) -> Dictionary:
	var rejected := {"success":false,"reason":"invalid_child_request","request":{}}
	if world == null or world.get_script()!=preload("res://scripts/layers/runtime/execution/world_context.gd") \
		or release_id.is_empty() or not _keys(command,COMMAND_FIELDS): return rejected
	var bound_world: Dictionary=world.capture_world()
	if not bound_world.get("runtime_map_id") is int or int(bound_world.runtime_map_id)<0: return rejected
	var row := _definition_for(command.get("action_id"))
	if row.is_empty() or command.op!="RequestChildAction" or command.handler_id!=row.handler_id \
		or command.damage_basis!="actual_hp_loss": return rejected
	for field: String in ["source_class","damage_channel","causes_struck","direct_magic_walk_delay"]:
		if typeof(command[field])!=typeof(row[field]) or command[field]!=row[field]: return rejected
	for field: String in ["source_handle","mechanic_id","root_release_id","root_skill_id","parent_release_id","parent_fact_id"]:
		if not command[field] is String or command[field].is_empty(): return rejected
	if Ids.resolve(command.root_skill_id,"skill").is_empty() or release_id in [command.root_release_id,command.parent_release_id]: return rejected
	for field: String in ["generation","maximum_generation","raw_damage"]:
		if not _positive_integer(command[field]): return rejected
	if command.generation>command.maximum_generation or not _number(command.radius_gu) or float(command.radius_gu)<=0: return rejected
	if (int(command.generation)==1 and command.parent_release_id!=command.root_release_id) \
		or (int(command.generation)>1 and command.parent_release_id==command.root_release_id): return rejected
	var prefix: String=command.parent_release_id+":hp:"
	if not command.parent_fact_id.begins_with(prefix): return rejected
	var fact_index: String=command.parent_fact_id.trim_prefix(prefix)
	if not fact_index.is_valid_int() or int(fact_index)<0 or str(int(fact_index))!=fact_index: return rejected
	if not command.origin is Dictionary or not _keys(command.origin,["x","y"]) \
		or not _number(command.origin.x) or not _number(command.origin.y) \
		or not Vector2(float(command.origin.x),float(command.origin.y)).is_finite() \
		or not Vector2(float(command.radius_gu),0).is_finite(): return rejected
	if not command.parent_target is Dictionary or not _keys(command.parent_target,["world","runtime_id","life_generation"]) \
		or not command.parent_target.world is Dictionary or not world.matches_world(command.parent_target.world) \
		or not _positive_integer(command.parent_target.runtime_id) or not _positive_integer(command.parent_target.life_generation) \
		or not command.historical_credit is Dictionary: return rejected
	var captured := Graph.capture(command,128,8)
	if not captured.success: return rejected
	var lease := new()
	lease._world=world; lease._command=captured.value; lease._release_id=release_id
	lease._definition=Graph.capture({"skill_id":row.action_id,"class":"child_action",
		"child_definition":row,"timing":{},"target":{"mode":"caster_surrounding_area","relation":"hostile"},
		"resource":{},"mp_cost_by_rank":[0,0,0,0],"geometry":{"shape":"continuous_circle"},
		"mechanics":{"runtime_family":"finite_death_child"}}).value
	lease._seed=JSON.stringify([command.root_release_id,command.parent_fact_id,command.source_handle,
		command.action_id,command.generation,release_id]).sha256_text().substr(0,15).hex_to_int()
	var target_context := {"has_target":true}; target_context.make_read_only()
	var resource_context := {}; resource_context.make_read_only()
	var request := {"contract_id":Cast.CONTRACT_ID,"skill_id":row.action_id,"rank":0,"caster_level":1,
		"origin_tile":Vector2i.ZERO,"facing":Vector2i.DOWN,"target_context":target_context,
		"resource_context":resource_context,"seed":lease._seed,"client_claimed_damage":null,
		"client_claimed_success":null,"child_action_lease":lease}
	request.make_read_only()
	return {"success":true,"reason":"","request":request}

static func from_request(request: Variant) -> RefCounted:
	if not request is Dictionary: return null
	var lease: Variant=request.get("child_action_lease")
	if not lease is RefCounted or lease.get_script()!=load("res://scripts/features/contracts/child_action_lease.gd"): return null
	return lease if lease.matches_request(request) else null

func matches_request(request: Dictionary) -> bool:
	if _world==null or _command.is_empty() or not _world.matches_world(_command.parent_target.world) \
		or not _keys(request,["contract_id","skill_id","rank","caster_level","origin_tile","facing",
		"target_context","resource_context","seed","client_claimed_damage","client_claimed_success","child_action_lease"]): return false
	return request.contract_id is String and request.contract_id==Cast.CONTRACT_ID \
		and request.skill_id is String and request.skill_id==_definition.skill_id \
		and request.rank is int and request.rank==0 and request.caster_level is int and request.caster_level==1 \
		and request.origin_tile is Vector2i and request.origin_tile==Vector2i.ZERO \
		and request.facing is Vector2i and request.facing==Vector2i.DOWN \
		and request.target_context is Dictionary and request.target_context=={"has_target":true} \
		and request.resource_context is Dictionary and request.resource_context=={} \
		and request.seed is int and request.seed==_seed and request.client_claimed_damage==null \
		and request.client_claimed_success==null and request.child_action_lease==self

func definition() -> Dictionary: return _definition
func command() -> Dictionary: return _command

func planning_context(context: Dictionary) -> Dictionary:
	if _world==null or not _world.matches_world(_command.parent_target.world) \
		or context.get("release_id")!=_release_id or not context.get("runtime_map_id") is int \
		or context.runtime_map_id!=_command.parent_target.world.runtime_map_id: return {}
	var to_screen: Variant=context.get("ground_gu_to_screen_position_px")
	var to_ground: Variant=context.get("screen_to_ground_position_px")
	if not to_screen is Callable or not to_screen.is_valid() or not to_ground is Callable or not to_ground.is_valid(): return {}
	var origin := Vector2(float(_command.origin.x),float(_command.origin.y))
	var screen: Variant=to_screen.call(origin)
	if not screen is Vector2 or not screen.is_finite(): return {}
	var restored: Variant=to_ground.call(screen)
	if not restored is Vector2 or not restored.is_finite() or not restored.is_equal_approx(origin): return {}
	var owned := context.duplicate(false)
	# Supplied snapshots and custom geometry builders must never replace the
	# command-owned child center/radius. Build one new snapshot on release.
	for key: String in ["canonical_snapshot","line_strip_builder","effective_cells_builder"]: owned.erase(key)
	owned["origin_screen_px"]=screen; owned["target_position_screen_px"]=screen
	owned["snapshot_validation_context"]={"expected_runtime_map_id":context.runtime_map_id,
		"ground_position_gu_to_screen_position_px":to_screen}
	return owned

func chain_context() -> Dictionary:
	return Graph.capture({"contract_id":"hardcore.combat.chain_context.v1","root_release_id":_command.root_release_id,
		"release_id":_release_id,"parent_release_id":_command.parent_release_id,"root_skill_id":_command.root_skill_id,
		"generation":int(_command.generation),"maximum_generation":int(_command.maximum_generation)}).value

static func _definition_for(id: Variant) -> Dictionary:
	if not id is String: return {}
	if _catalog_attempted: return _definitions.get(id,{})
	_catalog_attempted=true
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or not _keys(parsed,["schema_version","contract_id","actions"]) \
		or parsed.schema_version!=1 or parsed.contract_id!=CONTRACT or not parsed.actions is Array: return {}
	var ids := {}
	for row: Variant in parsed.actions:
		if not row is Dictionary or not _keys(row,["action_id","handler_id","revision","operation",
			"source_class","damage_channel","causes_struck","direct_magic_walk_delay"]) \
			or row.action_id!="hc.child.death_burst.v1" or row.handler_id!="hc.death_burst.v1" \
			or row.revision!=1 or row.operation!="area_damage" or row.source_class!="child" \
			or row.damage_channel!="magic_defense" or not row.causes_struck is bool or row.causes_struck \
			or not row.direct_magic_walk_delay is bool or row.direct_magic_walk_delay or ids.has(row.action_id): return {}
		ids[row.action_id]=row
	var captured := Graph.capture(ids,1024,8)
	if not captured.success: return {}
	_definitions=captured.value
	return _definitions.get(id,{})

static func _number(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value))
static func _positive_integer(value: Variant) -> bool:
	return _number(value) and float(value)>0 and float(value)<=9007199254740991.0 and floor(float(value))==float(value)
static func _keys(value: Dictionary, fields: Array) -> bool:
	if value.size()!=fields.size(): return false
	for key: String in fields:
		if not value.has(key): return false
	return true
