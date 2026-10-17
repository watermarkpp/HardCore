extends Node

## Structural/negative component fixture only. Positive gameplay publication,
## genuine Loading pin admission and original Source P replay require the
## actual Root providers and are deliberately not fabricated here.
const Contract := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
const Shell := preload("res://scripts/gameplay/presentation/actor_main_visual_shell.gd")
const Registry := preload("res://scripts/gameplay/presentation/main_actor_visual_registry.gd")
const Assets := preload("res://scripts/gameplay/presentation/actor_main_asset_port.gd")
const Proof:=preload("res://tests/framework/helpers/check_receipt.gd")
var _proof:=Proof.new()
var _checks := 0
var _failed := false
func _check(value: bool, name: String) -> void:
    _checks += 1
    _proof.record(value,name)
    if not value: _failed = true; push_error("FAIL: "+name)
func _ready() -> void:
    _check(OS.get_thread_caller_id() == OS.get_main_thread_id(),"actual_Main_thread")
    var shell: Node2D = Shell.new()
    _check(shell is Node2D and not shell is CollisionObject2D,"actual_pure_Node2D_class")
    _check(shell.get_child_count() == 0,"empty_prebind_shell_has_no_resource_or_body")
    _check(not shell.has_method("take_damage") and not shell.has_method("_physics_process"),"no_gameplay_writer_or_tick")
    _check(not shell.has_method("_input") and not shell.has_method("_unhandled_input"),"no_input_authority")
    var assets: RefCounted = Assets.new()
    _check(not assets.is_actual_loading_bound(),"absent_vault_cannot_claim_Loading_ready")
    _check(not assets.configure_main(null,null,{},{}),"null_real_providers_rejected")
    var registry: RefCounted = Registry.new()
    _check(not registry.configure_main(null,{},null,null),"absent_Main_receiver_admission_rejected")
    _check(not registry.bind_original_enemy_header_channel(null,null),"absent_actual_Native_prefix_and_physical_vault_rejected")
    _check(not registry.apply_original_enemy_structural_header({"kind":"original_world_presentation","operation":&"ACTOR_HEADER","arguments":[{}]}),"unclaimed_unconfigured_header_cannot_create_actor")
    _check(not registry.apply_original_actor_stealth_event({"kind":"original_world_presentation","operation":&"set_actor_stealth_alpha","arguments":[1,true,false]}),"unclaimed_stealth_cannot_write_Main_actor")
    _check(not registry.apply_original_actor_stealth_event({"kind":"original_world_presentation","operation":&"set_actor_stealth_alpha","arguments":[1,true,true]}),"unclaimed_summon_flag_cannot_write_Main_actor")
    _check(not preload("res://scripts/gameplay/presentation/enemy_birth_structural_header.gd").validate({},"ACTOR_HEADER"),"empty_structural_header_cannot_claim_Source_identity")
    _check(not shell.prepare_original_enemy_visual_header(1,null,null) and shell.visual == null and shell.get_child_count() == 0,"missing_real_visual_dependencies_cannot_partially_create_child")
    _check(not Contract.validate({}),"empty_publication_rejected")
    _check(not Contract.valid_identity({"runtime_id":-1,"life_generation":1,"world":{}}),"negative_actor_ID_rejected")
    var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"presentation_contract_only"}
    var identity := {"world":world,"runtime_id":get_instance_id(),"life_generation":0}
    var presentation := {"contract_id":Contract.PREMAP_PLAYER_CONTRACT,"identity":identity,"kind":"player","publication_sequence":1,"source_process_frame":0,"source_physics_frame":0,"clock_epoch":0,"scaled_delta":0.0,"advance_visual":false,"combat_time_s":0.0,"actor":{"source_present":true,"source_inside_world":true,"source_retiring":false,"position_screen_px":Vector2.ZERO,"velocity":Vector2.ZERO,"facing":Vector2.DOWN,"movement_facing":Vector2.DOWN,"actual_motion_facing":Vector2.DOWN,"movement_input_active":false,"locomotion_state":"idle","current_hp":1,"max_hp":1,"control_time":0.0,"poison_remaining":0.0},"profile":{"profession_id":"hc.profession.warrior","gender":"男","level":1,"equipment":{}},"enemy_visual":{},"enemy_root":{}}
    _check(Contract.validate_presentation(presentation) and not Contract.validate(presentation) and not Contract.valid_identity(identity),"complete premap display payload does not satisfy the formal combat/actor projection contract")
    var foreign: Dictionary = presentation.duplicate(true)
    foreign.kind = "enemy"
    _check(not Contract.validate_presentation(foreign),"enemy cannot borrow the Player constructor display boundary")
    foreign = presentation.duplicate(true); foreign.identity.world.world_epoch = 1
    _check(not Contract.validate_presentation(foreign),"negative map with a later generation is rejected in the display domain too")
    foreign = presentation.duplicate(true); foreign.identity.life_generation = -1
    _check(not Contract.validate_presentation(foreign),"negative actual life cannot be rendered as a premap Player")
    foreign = presentation.duplicate(true); foreign.actor.erase("current_hp")
    _check(not Contract.validate_presentation(foreign),"separate premap identity keeps all original required display payload fields")
    _check(Contract.capture({"bad":shell}).is_empty(),"live_Node_cannot_cross_Source_value_wire")
    var immutable: Dictionary = Contract.capture({"vector":Vector2(1.25,-3.5),"nested":{"array":[1,2,3]}})
    _check(not immutable.is_empty() and immutable.is_read_only() and immutable.nested.is_read_only() and immutable.nested.array.is_read_only(),"actual_native_immutable_graph")
    shell.free()
    var written: bool=_proof.write_receipt("actor_visual_projection_contract_20261015",_checks,1 if _failed else 0)
    print("ACTOR_VISUAL_PROJECTION_CONTRACT_"+("PASS" if written and not _failed else "FAIL")+" checks="+str(_checks)+" scope=structural_negative_component_only")
    get_tree().quit(0 if written and not _failed else 1)
