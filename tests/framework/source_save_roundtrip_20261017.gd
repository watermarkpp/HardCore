extends Node
## Six independently user-approved 180s functional stages: three real old profiles x deposit/withdraw.
## Only original CharacterSelect, Source command receipts, menu signals and terminal owners act.
const Proof:=preload("res://tests/framework/helpers/check_receipt.gd")
const Audit:=preload("res://tests/framework/helpers/source_save_roundtrip_assertions_20261017.gd")
const SPEC: String="res://tests/framework/source_save_scenario_20261017.json"
var proof:=Proof.new()
var failed:=0
var spec: Dictionary
var expected: Dictionary
var report: Dictionary={"contract_id":"hardcore.test.actual_Source_save_roundtrip.v1","commands":[],"sessions":[],"terminals":[],"snapshots":[]}
var facade: Node
var hall: Control
var application: RefCounted
var transport: RefCounted
var host: Object
var gate: RefCounted
var resident: PackedScene
var deadline:=0
var stage: String="NEW"
var operation_busy:=false
var command_id:=0
var source_session:=0
var source_model:=0
var old_hall_id:=0
var root_id:=0
var initial: Dictionary
var conserved: Dictionary
var deposited: Dictionary
var expected_final: Dictionary
var prior: Dictionary
var old_session:=0
var old_source_model:=0
var old_host_id:=0
var clicked:=false
var finishing:=false
func check(ok: bool,label: String) -> bool:
	proof.record(ok,label)
	if not ok:failed+=1;print("SOURCE_SAVE_ROUNDTRIP_FAIL ",label)
	return ok
func _ready() -> void:_run.call_deferred()
func _run() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	if not check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"only protected private runner userdata"): _finish();return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	if not check(parsed is Dictionary and parsed.get("contract_id")=="hardcore.test.Source_save_scenario.v1" and parsed.get("phase") in ["deposit","withdraw"],"exact immutable scenario"): _finish();return
	spec=parsed;expected=spec.expected
	if not check(spec.get("timeout_seconds")==180 and not spec.get("input_directory","").is_empty() and str(spec.input_directory).begins_with("res://outputs/"),"exact user-approved stage180s and read-only isolated input corpus"): _finish();return
	deadline=Time.get_ticks_usec()+180000000
	facade=get_tree().root.get_node("PlayerState")
	if not check(facade.get("_source_domain_gate")==null,"initial Main original writer exists before any Source"): _finish();return
	var base: String="user://Source_roundtrip_case"
	if not _copy_tree(spec.input_directory,base):_finish();return
	# These are original Main configuration/load APIs, before the real S handoff.
	# No reset/create, no direct _model access, no experimental document apply.
	facade.profile_directory=base.path_join("characters")
	facade.profile_index_path=base.path_join("character_profiles.json")
	facade.shared_warehouse_path=base.path_join("shared_warehouse.json")
	facade.shared_warehouse_transaction_log_path=base.path_join("shared_warehouse.transaction.json")
	facade._shared_warehouse_initialized=false;facade.test_mode=false
	facade.begin_startup_save_upgrade()
	if not check(facade.finish_startup_save_upgrade(),"original complete startup migration on private archived/latest copied files"): _finish();return
	if not check(facade.select_character(expected.profile_id),"original Main selects existing archived profile without creation"): _finish();return
	initial=_main_snapshot()
	if spec.phase=="deposit":
		check(Audit.equal(initial,expected.initial_expected),"old-load exact migration result reuses frozen original golden")
	else:
		var witness_bytes: PackedByteArray=FileAccess.get_file_as_bytes(spec.prior_witness)
		check(Audit.sha256(witness_bytes)==spec.prior_witness_sha256,"previous real phase witness bytes are hash bound")
		var decoded: Variant=bytes_to_var(witness_bytes)
		if not check(decoded is Dictionary and decoded.get("status")=="PASS" and decoded.get("profile_id")==expected.profile_id and decoded.get("phase")=="deposit","cold phase consumes successful same-profile real prior witness"): _finish();return
		prior=decoded;check(Audit.equal(initial,prior.deposited),"new process disk reload preserves actual nonempty equipment warehouse")
		check(Audit.find(initial.warehouse_inventory,str(expected.item.instance_id))>=0,"prior Source deposit real equipment present before withdrawal")
	conserved=Audit.ownership(initial)
	check(conserved.valid and not conserved.has_duplicate_instances,"initial whole-account stable IDs and full item/count ownership are unique")
	if failed>0:_finish();return
	resident=load("res://scenes/main.tscn")
	hall=load("res://scenes/character_select.tscn").instantiate();hall.force_launch_preload_for_test=true;hall.suppress_quit_for_test=true
	get_tree().root.add_child(hall);get_tree().current_scene=hall
	stage="FIRST_LAUNCH"
func _main_snapshot() -> Dictionary:
	var fields: Dictionary={}
	for name: String in ["active_profile_id","profession_id","level","experience","gold","learned_skills","inventory","equipment","warehouse_inventory"]:fields[name]=facade.get(name)
	return Audit.snapshot(fields,{"skill_progression":facade.skill_progression_snapshot()})
func _copy_tree(source: String,target: String) -> bool:
	var dir:=DirAccess.open(source)
	if not check(dir!=null,"isolated input directory exists "+source):return false
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))==OK,"private input copy directory"):return false
	for name: String in dir.get_files():
		if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source.path_join(name)),ProjectSettings.globalize_path(target.path_join(name)))==OK,"exact input bytes copied "+name):return false
	for name: String in dir.get_directories():
		if not _copy_tree(source.path_join(name),target.path_join(name)):return false
	return true
func _process(_delta: float) -> void:
	if finishing or stage=="NEW":return
	if Time.get_ticks_usec()>deadline:
		check(false,"actual stage completes within user-approved180s functional bound");_preserve_failure()
		if host!=null and host.status().get("started")==true:host.request_close();finishing=true
		else:_finish()
		return
	if stage in ["FIRST_LAUNCH","SECOND_LAUNCH"]:
		if not is_instance_valid(hall):return
		if not clicked:
			clicked=true;old_hall_id=hall.get_instance_id();hall.enter_button.pressed.emit()
		var producer: RefCounted=hall.get("_source_startup_producer")
		if producer==null:return
		host=producer.actual_host();application=producer.actual_application()
		if application==null or host==null:return
		if not str(host.status().get("fault","")).is_empty():check(false,"actual Source fault "+str(host.status().fault));_preserve_failure();finishing=true;host.request_close();return
		transport=application.get("_transport")
		var root: Node2D=application.get("_root_transport").retained_root()
		if transport==null or transport.get("_state")!="S" or transport.get("_world").get("runtime_map_id",-1)<0 or not is_instance_valid(root) or get_tree().current_scene!=root or hall.launch_loading_overlay.visible:return
		gate=facade.get("_source_domain_gate");source_session=transport.get("_session_id");source_model=transport.get("_model_id");root_id=root.get_instance_id();command_id=0
		check(gate!=null and gate.state()=="S" and source_session>0 and source_model!=0,"unique committed actual Source Profile after true first Map handoff")
		var caps: Dictionary=host.capabilities()
		check(caps.get("native_source_identity_injected")==true and caps.get("native_source_sha256")==spec.get("native_source_sha256") and FileAccess.get_sha256(OS.get_executable_path())==spec.get("main_sha256"),"actual prepared production Host aggregate and executing PE match this stage freeze")
		check(application.get("_main_composition").get("_registry").actual_original_player_view(transport.get("_world"))!=null,"actual original player renderer and Source World are live")
		report.sessions.append({"owner_session_id":source_session,"source_profile_model_id":source_model,"host_id":host.get_instance_id(),"world":transport.get("_world").duplicate(true)})
		if stage=="SECOND_LAUNCH":
			check(source_session!=old_session and source_model!=old_source_model and host.get_instance_id()!=old_host_id,"return/reentry creates unique new real Host Session and Profile owner")
			stage="VERIFY_SECOND";_verify_second.call_deferred()
		else:stage="TRANSACTIONS";_transactions.call_deferred()
	elif stage=="WAIT_RETURN":
		var terminal: Dictionary=application.actual_original_terminal_exit()
		if terminal.get("success")!=true:return
		stage="OBSERVE_RETURN";_observe_return(terminal)
	elif stage=="WAIT_HALL":
		var scene: Node=get_tree().current_scene
		if scene==null or scene.get_script()==null or scene.get_script().resource_path!="res://scripts/character_select.gd":return
		hall=scene;hall.suppress_quit_for_test=true;hall.force_launch_preload_for_test=true
		check(hall.get_instance_id()!=old_hall_id and facade.get("_source_domain_gate")==null,"original startup path reaches fresh CharacterSelect with detached retired S gate")
		check(facade.select_character(expected.profile_id),"actual returned Main reloads selected current persistent profile")
		clicked=false;stage="SECOND_LAUNCH"
	elif stage=="WAIT_QUIT":
		var terminal: Dictionary=application.actual_original_terminal_exit()
		if terminal.get("success")==true:
			check(terminal.get("contract_id")=="hardcore.main.application_QUIT_terminal.v1" and host.status().get("join_complete")==true and host.status().get("main_channels_unbound_after_close")==true and not is_instance_id_valid(root_id),"real normal QUIT closes second Source and physically retires Root")
			report.terminals.append({"kind":"QUIT","terminal":terminal,"native_status":host.status()})
			_finish()
func _command(method: String,args: Array) -> Dictionary:
	var reply: Dictionary=await facade.submit_original_profile_command(StringName(method),args)
	if not check(Audit.command_matches(reply,method,expected.profile_id,source_session,source_model,command_id),"formal same-session command receipt "+method):return {}
	command_id=reply.receipt.command_id
	check(transport.get("_results").get(command_id)==reply.receipt,"actual transport retained same reliable Source receipt before real ACK retirement")
	report.commands.append(reply.duplicate(true))
	return reply
func _capture() -> Dictionary:
	# This existing admitted method performs its original save before reading.
	var reply: Dictionary=await _command("device_lab_active_save_document",[])
	if reply.is_empty():return {}
	if not check(reply.result is Dictionary and not reply.result.is_empty(),"original Source save/export returns a complete real document"):return {}
	var snapshot: Dictionary=Audit.snapshot(reply.receipt.profile_view.fields,reply.result)
	check(not snapshot.is_empty(),"actual Source save/read receipt includes complete progression and all item containers")
	report.snapshots.append({"snapshot":snapshot,"saved_document":reply.result,"command_id":command_id,"owner_session_id":source_session})
	return snapshot
func _check_conserved(value: Dictionary,label: String) -> void:
	check(Audit.equal(Audit.ownership(value),conserved),label+" preserves every item UID/full attribute/count without duplication or loss")
	check(Audit.equal(Audit.progression(value),Audit.progression(initial)),label+" preserves exact level/XP/gold/canonical learned skills and proficiency")
func _transactions() -> void:
	var current: Dictionary=await _capture()
	if current.is_empty():_fail_live();return
	check(Audit.equal(current,initial),"real Source adopts latest original loaded state without second load/reset")
	var uid: String=str(expected.item.instance_id)
	if spec.phase=="deposit":
		var free: int=current.inventory.size()
		var result: Dictionary=await _command("unequip_to_inventory_slot",[expected.equipment_slot,free,uid])
		if result.get("result",{}).get("success")!=true:
			var weight: Dictionary=await _command("inventory_weight",[])
			var capacity: Dictionary=await _command("max_inventory_weight",[])
			# Original unequip_slot retains its generic equipment reason=rejected;
			# its message is the exact official weight-preview rejection constant.
			var original_model: Script=load("res://scripts/gameplay/profile/profile_model.gd")
			check(expected.medicine_preparation_required and result.get("result",{}).get("reason")=="rejected" and result.result.message==original_model.INVENTORY_WEIGHT_REJECTION and weight.get("result",0)>capacity.get("result",0),"original real Source overweight unequip remains rejected, with exact original reason/message and weight authority")
			var unchanged: Dictionary=await _capture();check(Audit.equal(unchanged,current),"rejected original unequip has no state mutation")
			var indices: Array=[];var slots: Array=[]
			for i: int in current.inventory.size():
				if current.inventory[i] is Dictionary and not current.inventory[i].is_empty():indices.append(i);slots.append(20+i)
			var prep: Dictionary=await _command("transfer_warehouse_prepared",["deposit",indices,slots])
			check(prep.get("result",{}).get("success")==true and prep.result.complete==true,"original prepared medicine deposit resolves real weight while conserving items")
			current=await _capture()
			if current.is_empty():_fail_live();return
			_check_conserved(current,"medicine preparation")
			free=current.inventory.size();result=await _command("unequip_to_inventory_slot",[expected.equipment_slot,free,uid])
		check(result.get("result",{}).get("success")==true,"real Source unequips archived equipment to bag")
		current=await _capture()
		if current.is_empty():_fail_live();return
		check(Audit.equal(current.inventory[free],expected.item),"unequip preserves complete original equipment record")
		var deposit: Dictionary=await _command("transfer_warehouse_prepared",["deposit",[free],[0]])
		check(deposit.get("result",{}).get("success")==true and deposit.result.complete==true and deposit.result.transferred==1,"real Source two-file prepared deposit receipt completes")
		deposited=await _capture()
		if deposited.is_empty():_fail_live();return
		_check_conserved(deposited,"equipment deposit")
		check(Audit.find(deposited.inventory,uid)<0 and Audit.equal(deposited.warehouse_inventory[0],expected.item),"nonempty warehouse uniquely owns original equipment after real save")
		expected_final=deposited
	else:
		var index: int=Audit.find(current.warehouse_inventory,uid)
		var withdraw: Dictionary=await _command("transfer_warehouse_prepared",["withdraw",[index]])
		check(withdraw.get("result",{}).get("success")==true and withdraw.result.complete==true and withdraw.result.transferred==1,"real Source prepared withdrawal completes from prior saved warehouse")
		current=await _capture()
		if current.is_empty():_fail_live();return
		var index_bag: int=Audit.find(current.inventory,uid)
		check(index_bag>=0 and Audit.equal(current.inventory[index_bag],expected.item) and Audit.find(current.warehouse_inventory,uid)<0,"withdraw preserves every attribute and exclusive bag ownership")
		var equip: Dictionary=await _command("equip_inventory_index_result",[index_bag,expected.equipment_slot,uid])
		check(equip.get("result",{}).get("success")==true,"real Source equips original item into original slot")
		expected_final=await _capture()
		if expected_final.is_empty():_fail_live();return
		_check_conserved(expected_final,"withdraw/equip/save")
		check(Audit.equal(expected_final.equipment,expected.initial_expected.equipment),"all original equipped slots and full records restored")
	if failed>0:_fail_live();return
	# Original Main SystemMenu signal -> existing input queue -> S _safe_logout.
	var root: Node2D=application.get("_root_transport").retained_root()
	var menu: Node=root.get("_system_menu_panel")
	if not check(is_instance_valid(menu) and menu.has_signal("return_to_character_select_requested"),"actual original retained SystemMenu signal producer"): _fail_live();return
	old_session=source_session;old_source_model=source_model;old_host_id=host.get_instance_id()
	stage="WAIT_RETURN";menu.return_to_character_select_requested.emit()
func _observe_return(terminal: Dictionary) -> void:
	var publication: Dictionary=transport.actual_profile_terminal_export()
	var event: Dictionary=transport.get("_profile_terminal_event_identity")
	var status: Dictionary=host.status()
	if not check(Audit.terminal_matches(publication,terminal,status,host.get_instance_id(),source_session,expected.profile_id,event),"actual final Source export same Host/event/ACK/zero-debt terminal grants fresh Main authority"):
		_fail_live();return
	for key: String in ["source_profile_model_id","source_session_object_id","source_runtime_id"]:check(not is_instance_id_valid(int(publication.get(key,0))),"actual Source object gone before Main authority return "+key)
	check(not is_instance_id_valid(old_hall_id) and not is_instance_id_valid(root_id) and gate.state()=="RETURNED" and facade.get("_source_domain_gate")==null,"old hall/Root physically absent and retired gate never reenabled")
	check(Audit.equal(_main_snapshot(),expected_final),"fresh original Main Model adopts complete latest Source progression/warehouse/equipment")
	# Read the actual fresh Main model retained by the now-RETURNED gate, never
	# invoke an old Main gameplay model or use it instead of a Source command.
	var fresh: RefCounted=gate.get("_pending_model")
	var local_random: Dictionary={}
	check(fresh!=null and fresh.get_instance_id()==terminal.actual_Profile_authority_return.actual_new_Main_model_id and fresh.get_instance_id()!=source_model,"actual fresh Main model identity matches original authority-return receipt")
	for field: String in ["_durability_rng","_blessing_oil_rng","_relic_instance_rng","_relic_proc_rng"]:
		var binding: int=publication.state.rng_bindings[field]
		var rng: RandomNumberGenerator=fresh.get(field)
		if binding<0:check(rng==null,"original null Profile RNG binding "+field)
		else:
			var saved: Dictionary=publication.state.rng_states[binding]
			check(rng!=null and rng.seed==saved.seed and rng.state==saved.state,"exact latest Source Profile RNG seed/state restored "+field)
			local_random[field]={"seed":rng.seed,"state":rng.state,"binding":binding}
	for left: String in local_random:
		for right: String in local_random:
			check(is_same(fresh.get(left),fresh.get(right))==(local_random[left].binding==local_random[right].binding),"original Profile RNG alias relation "+left+"/"+right)
	fresh=null
	var handoff: Dictionary=publication.global_random_terminal
	var repeat: Dictionary=host.restore_original_terminal_gameplay_random(handoff)
	check(repeat.get("success")==true and repeat.get("status")=="RESTORED" and repeat.get("terminal_handoff")==handoff,"same actual Native terminal RNG restore receipt is idempotent")
	# Native read-only capture of actual default Main stream; no GDS seed replay.
	var probe: Object=ClassDB.instantiate("HardCoreSimulationHost")
	var actual_main: Dictionary=probe.capture_main_gameplay_random();probe=null
	check(actual_main==handoff.handoff,"first observed Main default PCG retains exact Source terminal seed/state/DEFAULT_INC")
	var oracle:=RandomNumberGenerator.new();oracle.seed=actual_main.seed;oracle.state=actual_main.state
	var expected_draw: int=oracle.randi();var actual_draw: int=randi()
	check(actual_draw==expected_draw,"actual resumed Main first randi exactly follows original terminal PCG stream")
	var after_probe: Object=ClassDB.instantiate("HardCoreSimulationHost")
	var after: Dictionary=after_probe.capture_main_gameplay_random();after_probe=null
	check(after.seed==actual_main.seed and after.increment==actual_main.increment and after.state==oracle.state,"actual default Main state advances exactly one accepted draw")
	report.terminals.append({"kind":"CHARACTER_SELECT","publication":publication,"event_identity":event,"terminal":terminal,"native_status":status,"actual_repeat_restore":repeat,"actual_Main_random_before":actual_main,"actual_Main_draw":actual_draw,"actual_Main_random_after":after,"actual_fresh_Main_Profile_random":local_random})
	application=null;transport=null;host=null;gate=null
	stage="WAIT_HALL"
func _verify_second() -> void:
	var snapshot: Dictionary=await _capture()
	if snapshot.is_empty():_fail_live();return
	check(Audit.equal(snapshot,expected_final),"second unique SourceSession loads same latest actually persisted profile+warehouse")
	_check_conserved(snapshot,"new Source reload")
	if failed>0:_fail_live();return
	stage="WAIT_QUIT"
	var root: Node2D=application.get("_root_transport").retained_root()
	root.notification(NOTIFICATION_WM_CLOSE_REQUEST)
func _fail_live() -> void:
	_preserve_failure();finishing=true
	if host!=null:host.request_close()
func _preserve_failure() -> void:
	report.status="FAIL";report.actual_native_status=host.status() if host!=null else {};_write_witness();proof.write_receipt("source_save_roundtrip_20261017",proof.records.size(),failed)
func _write_witness() -> void:
	report.profile_id=expected.get("profile_id","");report.phase=spec.get("phase","");report.deposited=deposited;report.final_snapshot=expected_final
	report.source_content_sha256=OS.get_environment("HARDCORE_R3_CONTENT_SHA256");report.invocation_id=OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID");report.checks=proof.records.duplicate(true)
	var path: String="user://source_save_roundtrip_witness_20261017.bin"
	var bytes: PackedByteArray=var_to_bytes(report)
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
	var export: Dictionary={"status":report.status,"profile_id":report.profile_id,"phase":report.phase,"source_content_sha256":report.source_content_sha256,"invocation_id":report.invocation_id,"witness_path":ProjectSettings.globalize_path(path),"witness_sha256":Audit.sha256(bytes),"checkpoint_directory":ProjectSettings.globalize_path("user://Source_roundtrip_case"),"deposited":deposited,"final_snapshot":expected_final}
	var metadata:=FileAccess.open("user://source_save_stage_export_20261017.json",FileAccess.WRITE);metadata.store_string(JSON.stringify(export,"  "));metadata.close()
func _finish() -> void:
	finishing=true;set_process(false);report.status="PASS" if failed==0 else "FAIL";_write_witness()
	var ok: bool=proof.write_receipt("source_save_roundtrip_20261017",proof.records.size(),failed)
	print("SOURCE_SAVE_ROUNDTRIP_20261017_","PASS" if ok else "FAIL"," checks=",proof.records.size()," failures=",failed)
	get_tree().quit(0 if ok else 1)
