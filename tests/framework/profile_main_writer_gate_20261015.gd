extends Node
## Real PlayerState adapter and production gate, with a refusal-only observer.
## This is a writer-isolation component, NOT a successful S/save adoption.
const Facade := preload("res://scripts/player_state.gd")
const Gate := preload("res://scripts/gameplay/source/main_profile_source_gate.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Queries := preload("res://scripts/gameplay/profile/profile_original_ui_queries.gd")
class RefusalObserver extends RefCounted:
	var denied: Array[Dictionary] = []
	var notifications: Array[int] = []
	func reject_original_main_profile_writer(fact: Dictionary) -> void: denied.append(fact.duplicate(true))
	func submit_original_profile_command(_method: StringName, _arguments: Array) -> Dictionary:
		return {"success":false,"errors":["component_has_no_Source_command_owner"]}
	func request_original_profile_notification(what: int) -> bool:
		notifications.append(what)
		return false
	func verify_original_profile_ui_receiver_closure(_nodes: Array, _checkpoint: Dictionary) -> Dictionary:
		return {"success":false,"errors":["component_has_no_admission_receipt"]}
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var actual_main_model: RefCounted = PlayerState.get("_model")
	var actual_profile: String = actual_main_model.get("active_profile_id")
	var facade: Node = Facade.new() # detached: original _ready/IO never runs.
	var model: RefCounted = facade.profile_core_for_owner()
	check(facade.get_script() == Facade and not facade.is_inside_tree(),"real original adapter constructor without activating another gameplay owner")
	check(facade.has_method("install_original_profile_source_gate"),"actual PlayerState exposes the required source writer-gate installer")
	if not facade.has_method("install_original_profile_source_gate"):
		facade.free(); model = null
		_finish()
		return
	var observer := RefusalObserver.new()
	var gate := Gate.new()
	check(gate.configure_main(facade,observer),"real gate binds its exact original facade")
	check(not facade.install_original_profile_source_gate(RefCounted.new()),"unconfigured arbitrary RefCounted cannot become writer authority")
	check(facade.install_original_profile_source_gate(gate),"configured same-facade gate installed once")
	check(not facade.install_original_profile_source_gate(gate),"second installation rejected without replacing owner")
	var original_level: int = model.level
	facade.level = original_level+1
	check(model.level == original_level+1 and facade.level == model.level,"MAIN mode delegates original setter and getter unchanged")
	check(facade.profile_core_for_owner() == model,"MAIN mode still exposes only its original model")
	facade.level = original_level
	check(gate.prepare(),"actual gate enters PREPARED")
	var denied_before: int = observer.denied.size()
	facade.level = original_level+10
	check(model.level == original_level and observer.denied.size() == denied_before+1,"PREPARED rejects real old setter before any model mutation")
	check(facade.level == original_level,"PREPARED capture can read the genuine frozen Main model")
	check(facade.profile_core_for_owner() == null,"PREPARED does not leak model through old facade method")
	facade._process(10.0)
	check(model.level == original_level,"blocked Main process cannot resume original Profile processing")
	check(gate.abort() and gate.state() == "MAIN","uncommitted preparation restores original writer permission")
	check(facade.profile_core_for_owner() == model,"abort restores the same existing model rather than constructing one")
	check(gate.prepare(),"second lawful preparation begins")
	# Controlled immutable display fixture: not a Native/source adoption proof.
	var published: Dictionary = {"level":original_level+2,"inventory":model.inventory.duplicate(true)}
	var actual_queries: Dictionary = Queries.capture(actual_main_model)
	published[Queries.FIELD] = actual_queries.duplicate(true)
	check(gate.commit(published),"real gate stores immutable view in component commit state")
	published.level = original_level+20
	check(facade.level == original_level+2 and model.level == original_level,"display view does not alias external dictionary or modify model")
	var read_denied_before: int = observer.denied.size()
	check(facade.inventory_weight() == actual_queries.inventory_weight and facade.max_inventory_weight() == actual_queries.max_inventory_weight and facade.experience_to_next_level() == actual_queries.experience_to_next_level,"three facade read queries return captured real owner results without invoking the retired Model")
	check(observer.denied.size() == read_denied_before,"lawful published read results do not masquerade as forbidden Main writers")
	check(gate.read_original_profile_view(Queries.FIELD).is_read_only(),"nested original query results are detached immutable display values")
	check(facade.inventory_occupied_count() == actual_queries.inventory_occupied_count and facade.available_skill_ids() == actual_queries.available_skill_ids,"Source read facade retains exact original occupied-slot count and available-skill order")
	check(facade.current_bich_quest_id() == actual_queries.current_bich_quest_id,"Source read facade returns owner-computed current quest")
	for quest_id: String in actual_queries.quest_facts:
		check(facade.quest_objective_lines(quest_id) == actual_queries.quest_facts[quest_id].lines and facade.quest_reward_label(quest_id) == actual_queries.quest_facts[quest_id].reward,"quest text is copied from exact owner-computed facts:"+quest_id)
	for skill_id: String in actual_queries.skill_facts:
		var fact: Dictionary = actual_queries.skill_facts[skill_id]
		check(facade.is_skill_learned(skill_id) == fact.learned and facade.effective_skill_level(skill_id) == fact.level and facade.is_skill_available(skill_id) == fact.available,"skill read facts retain actual canonical owner results:"+skill_id)
	facade.level = original_level+30
	check(model.level == original_level,"S state rejects old setter while keeping readonly display")
	check(facade.profile_core_for_owner() == null,"S state cannot recover old model from public facade")
	var before_array: Array = model.inventory
	check(facade.inventory.is_read_only() and facade.inventory == before_array,"display inventory retains complete values with no mutable alias")
	check(not gate.abort(),"committed owner cannot restore old Main writer by abort")
	check(gate.update_original_profile_view({"level":original_level+3,"inventory":before_array}),"actual immutable view can be replaced without old writer")
	check(facade.level == original_level+3 and model.level == original_level,"only committed display view changes")
	check(not observer.denied.is_empty(),"invalid writes retain explicit refusal evidence")
	facade.free(); facade = null; gate = null; model = null
	check(PlayerState.get("_model") == actual_main_model and actual_main_model.get("active_profile_id") == actual_profile,"real autoload/profile/save authority remains untouched")
	_finish()
func _finish() -> void:
	var written: bool = _proof.write_receipt("profile_main_writer_gate_20261015",_proof.records.size(),_failed)
	print("PROFILE_MAIN_WRITER_GATE_20261015_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
