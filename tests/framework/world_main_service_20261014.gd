extends Node
## Direct Godot fixture: real pinned helper, strict missing-boundary rejection,
## and a real loaded Main profile capture when the isolated runner supplies one.
## It does not claim a mock Session/Main renderer is a production factory run.
const AudioOwner := preload("res://scripts/gameplay/world/world_audio_owner_primitives.gd")
const ProfileView := preload("res://scripts/gameplay/world/world_profile_ui_view.gd")
const HeaderAttachment := preload("res://scripts/gameplay/world/world_main_root_attachment.gd")
const Handoff := preload("res://scripts/gameplay/profile/profile_state_handoff.gd")
var failures: Array[String]=[]
var checks := 0
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func _ready() -> void:
	var original:=preload("res://scripts/player_visual.gd").new()
	var target:=AudioOwner.new()
	for record: Dictionary in [{},{"item_id":0},{"item_id":23},{"item_id":23.9},{"item_id":"23"},{"item_id":-1},{"item_id":"unknown"},{"item_id":-1,"itemId":18},{"itemId":" 18 "},{"item_id":null,"itemId":"0"}]:
		check(target._audio_stable_equipped_item_id(record)==original._audio_stable_equipped_item_id(record),"actual_original_stable_item_id:"+str(record))
	original.free()
	var before: int=get_tree().root.get_child_count()
	var refused: Dictionary=HeaderAttachment.instantiate_original_source_root(load("res://scenes/main.tscn"),load("res://scripts/game_root.gd"),null,{})
	check(refused.get("success")==false and refused.get("status")=="MISSING","missing_actual_Main_transport_refused")
	check(get_tree().root.get_child_count()==before,"no_root_or_combat_Node_born_on_refused_constructor")
	var view:=ProfileView.new()
	check(not view.accept_original_journal_snapshot({}),"empty_profile_view_is_not_ready")
	check(ProfileView.original_handoff_identity({}).is_empty(),"missing_loaded_handoff_is_not_identity")
	var actual_profile_scope: Dictionary={"status":"MISSING","reason":"actual isolated Main loaded/admission receipt required"}
	var source: RefCounted=PlayerState.get("_model")
	if source!=null and not source.active_profile_id.is_empty() and source.last_load_result.get("success")==true:
		var handoff: Dictionary=Handoff.capture_main(source,PlayerState)
		if handoff.get("ok")==true:
			# This identity is the actual prepared profile; no load/reset/hydrate is
			# performed here. Full Host adoption still belongs to Root integration.
			actual_profile_scope={"status":"PASS","profile_id":source.active_profile_id,"source_model_id":source.get_instance_id(),"handoff_identity":ProfileView.original_handoff_identity(handoff.publication)}
			check(not actual_profile_scope.handoff_identity.is_empty(),"actual_loaded_handoff_identity")
	var receipt: Dictionary={"contract_id":"world.main.service.direct_fixture.v1","checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL","source_script_sha256":FileAccess.get_sha256(get_script().resource_path),"profile_capture":actual_profile_scope,"factory_loading_renderer_checkpoint":"MISSING","actual_world":"NOT_RUN","APK":"NOT_RUN","device":"NOT_RUN"}
	print(JSON.stringify(receipt))
	get_tree().quit(0 if failures.is_empty() else 1)
