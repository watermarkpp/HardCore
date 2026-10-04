extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan_contract.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Handlers := preload("res://scripts/features/handlers/handler_registry.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
var _zone_generation := 1
var current_map_id := 910002
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var router: Variant = Router

func _ready() -> void: _run.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks += 1; proof.record(ok,label)
	if not ok: errors.append(label)
func _to_screen(p: Vector2) -> Vector2: return p*10.0-Vector2(50,25)
func _to_ground(p: Vector2) -> Vector2: return (p+Vector2(50,25))/10.0

func _command(world: RefCounted) -> Dictionary:
	var fact := {"contract_id":"hardcore.combat.damage_fact.v1","fact_id":"root:1:hp:0",
		"release_id":"root:1","skill_id":"hc.skill.wizard.ice_storm","source_class":"direct",
		"damage_channel":"magic_defense","requested_damage":30,"hp_before":24,"hp_after":0,
		"actual_loss":24,"target_survived_commit":false,
		"target":{"world":world.capture_world(),"runtime_id":123,"life_generation":1},
		"historical_credit":{"profile_id":PlayerState.active_profile_id},
		"commit_ground_origin":{"x":12.5,"y":-3.0},
		"chain_context":{"contract_id":"hardcore.combat.chain_context.v1","root_release_id":"root:1",
		"release_id":"root:1","parent_release_id":"","root_skill_id":"hc.skill.wizard.ice_storm",
		"generation":0,"maximum_generation":2}}
	var binding := {"handle":"child:source:1","definition":{"handler_id":"hc.death_burst.v1",
		"mechanic_id":"hc.death_burst.fixture","skill_id":"hc.skill.wizard.ice_storm",
		"source_classes":["direct","periodic","child"],
		"config":{"fraction":0.5,"radius_gu":2.0,"maximum_generation":2}}}
	var commands := Handlers.commands(fact,binding)
	return commands[0] if commands.size()==1 else {}

func _context(release: String) -> Dictionary:
	return {"release_id":release,"runtime_map_id":current_map_id,
		"origin_screen_px":Vector2(999,999),"target_position_screen_px":Vector2(999,999),
		"screen_to_ground_position_px":_to_ground,"ground_gu_to_screen_position_px":_to_screen,
		"snapshot_validation_context":{"expected_runtime_map_id":current_map_id}}

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	var supported := false
	for method: Dictionary in Router.new().get_script().get_script_method_list():
		if method.name=="create_child_request": supported=true
	_check(supported,"the one formal router must accept a registered, owned child request instead of a Chinese or vanilla alias")
	if not supported: _finish(); return
	var world := World.new(); world.configure(self,PlayerState)
	var command := _command(world)
	_check(not command.is_empty(),"the pure first-death handler supplies the closed finite command")
	var made: Dictionary = router.create_child_request(command,world,"child:1")
	_check(made.success,"finite command owns a registered child request")
	if not made.success: _finish(); return
	var request: Dictionary = made.request
	_check(request.is_read_only() and request.skill_id=="hc.child.death_burst.v1",
		"child identity stays separate and request is immutable")
	var counts_before := Plan.canonical_plan_build_count
	var snapshot_before := Plan.snapshot_build_count
	var plan: Dictionary = Router.build_canonical_plan(request,_context("child:1"))
	_check(plan.rejection.accepted,"child uses the existing build_canonical_plan entry: "+str(plan.rejection.reason))
	if not plan.rejection.accepted: print("CHILD_PLAN_DIAGNOSTIC ",JSON.stringify(plan))
	if not plan.rejection.accepted: _finish(); return
	_check(plan.created_by==Plan.CANONICAL_PLANNER_ID and Plan.canonical_plan_build_count==counts_before+1,
		"the same canonical envelope is built exactly once")
	_check(Plan.snapshot_build_count==snapshot_before+1,"one fresh release snapshot is built by the existing builder")
	_check(plan.skill_id=="hc.child.death_burst.v1" and plan.release_id=="child:1",
		"plan preserves the actual child ID and release, not the root player spell")
	_check(plan.gameplay_actions.size()==1 and plan.gameplay_actions[0].raw_power==12,
		"child damage basis remains the original committed HP loss fraction")
	_check(plan.canonical_snapshot.center_ground_gu==Vector2(12.5,-3.0)
		and plan.canonical_snapshot.radius_gu==2.0,
		"caller-provided later screen position cannot replace committed death geometry")
	_check(bool(Snapshot.validate_for_consumer(plan.canonical_snapshot,
		{"expected_runtime_map_id":current_map_id,"ground_position_gu_to_screen_position_px":_to_screen},Snapshot.VALIDATION_STRICT_V2).valid),
		"child circle is an absolute mapped STRICT_V2 footprint")
	_check(not plan.resource_commit_required and plan.resource_cost.mp_cost==0,
		"child does not charge player resources or initiate another cooldown")
	_check(plan.chain_context.root_release_id=="root:1" and plan.chain_context.parent_release_id=="root:1"
		and plan.chain_context.generation==1 and plan.chain_context.maximum_generation==2,
		"canonical plan hash owns complete root/parent/child finite lineage")
	_check(Loader.stable_skill_id("hc.child.death_burst.v1").is_empty() and Loader.skill_ids().size()==33,
		"the frozen 33-skill table is not expanded with a fake player spell")
	var repeated := Router.build_canonical_plan(request,_context("child:1"))
	_check(plan.plan_hash==repeated.plan_hash,"pure repeated planning has deterministic independent child seed")
	_check(plan.skill_definition_revision.length()==64,"child revision fingerprints its exact registered descriptor")
	for field: String in ["chain_context","historical_credit","child_command"]:
		var changed := plan.duplicate(true)
		changed[field]={"changed":true}
		_check(Plan.plan_hash(changed)!=plan.plan_hash,"child ownership field is protected by the existing plan hash: "+field)
	for field: String in ["skill_id","seed","rank","client_claimed_damage"]:
		var forged := request.duplicate(false)
		forged[field] = "wizard.ice_storm" if field=="skill_id" else 999
		var rejected := Router.build_canonical_plan(forged,_context("child:1"))
		_check(not rejected.rejection.accepted,"altered child request is rejected before planning side effects: "+field)
	var plain := request.duplicate(false); plain.erase("child_action_lease")
	_check(not Router.build_canonical_plan(plain,_context("child:1")).rejection.accepted,
		"a raw child ID without its typed owner never becomes a vanilla fallback")
	var wrong := _context("other:release")
	_check(not Router.build_canonical_plan(request,wrong).rejection.accepted,"another release cannot adopt this child")
	wrong=_context("child:1"); wrong.runtime_map_id=910003
	_check(not Router.build_canonical_plan(request,wrong).rejection.accepted,"another map cannot adopt this geometry")
	wrong=_context("child:1"); wrong.erase("screen_to_ground_position_px")
	_check(not Router.build_canonical_plan(request,wrong).rejection.accepted,"missing map projection fails closed")
	wrong=_context("child:1"); wrong.erase("ground_gu_to_screen_position_px")
	_check(not Router.build_canonical_plan(request,wrong).rejection.accepted,"missing reverse projection fails closed")
	wrong=_context("child:1"); wrong.canonical_snapshot=Snapshot.create_circle("forged","old",Vector2.ZERO,99.0)
	var overridden := Router.build_canonical_plan(request,wrong)
	_check(overridden.rejection.accepted and overridden.canonical_snapshot.center_ground_gu==Vector2(12.5,-3.0)
		and overridden.canonical_snapshot.radius_gu==2.0,"a supplied old snapshot cannot override child geometry")
	for field: String in ["action_id","source_class","damage_channel","causes_struck","direct_magic_walk_delay","damage_basis","generation","maximum_generation","raw_damage","radius_gu"]:
		var bad := command.duplicate(true)
		bad[field] = 0 if field in ["generation","maximum_generation","raw_damage","radius_gu"] else true if field in ["causes_struck","direct_magic_walk_delay"] else "wrong"
		_check(not router.create_child_request(bad,world,"child:bad").success,
			"unsupported child contract never produces a request: "+field)
	var replay := command.duplicate(true); replay.parent_target.world.world_epoch+=1
	_check(not router.create_child_request(replay,world,"child:bad").success,"foreign parent world cannot produce a child")
	_check(not router.create_child_request(command,world,"root:1").success,"child cannot reuse root/parent release identity")
	var unrelated := command.duplicate(true); unrelated.parent_release_id="unrelated"
	_check(not router.create_child_request(unrelated,world,"child:bad").success,"first child parent must match root")
	unrelated=command.duplicate(true); unrelated.parent_fact_id="unrelated:hp:0"
	_check(not router.create_child_request(unrelated,world,"child:bad").success,"parent fact must belong to the declared release")
	var mapped_id:=current_map_id
	current_map_id=-1
	var unmapped: Dictionary=router.create_child_request(_command(world),world,"child:unmapped")
	var unmapped_plan: Dictionary={}
	if unmapped.success: unmapped_plan=Router.build_canonical_plan(unmapped.request,_context("child:unmapped"))
	var unmapped_accepted: bool=not unmapped_plan.is_empty() and bool(unmapped_plan.rejection.accepted)
	_check(not unmapped_accepted,"child cannot enter the old unbound-map compatibility branch as an accepted plan")
	_check(not unmapped_accepted or bool(Snapshot.validate_for_consumer(unmapped_plan.canonical_snapshot,
		{"expected_runtime_map_id":-1,"ground_position_gu_to_screen_position_px":_to_screen},Snapshot.VALIDATION_STRICT_V2).valid),
		"every accepted child snapshot remains STRICT_V2 even when the owner's map is unbound")
	current_map_id=mapped_id
	_zone_generation+=1
	_check(not Router.build_canonical_plan(request,_context("child:1")).rejection.accepted,
		"world generation change invalidates an already-owned child before it can be planned")
	_finish()

func _finish() -> void:
	var written := proof.write_receipt("feature_child_planner_test",checks,errors.size())
	if written and errors.is_empty(): print("FEATURE_CHILD_PLANNER_PASS checks=",checks)
	else: print("FEATURE_CHILD_PLANNER_FAIL checks=",checks," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
