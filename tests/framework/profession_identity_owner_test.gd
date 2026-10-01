extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/identity/entity_registry.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	check(PlayerState.has_method("set_profession_identity"),"character has one typed profession identity owner")
	if not PlayerState.has_method("set_profession_identity"): _finish(); return
	for id: String in ["hc.profession.warrior","hc.profession.wizard","hc.profession.taoist"]:
		check(PlayerState.call("set_profession_identity",id),"registered profession is admitted "+id)
		check(PlayerState.get("profession_id") == id and PlayerState.profession == Registry.resolve(id,"profession").display_name,"display name projects the same identity "+id)
		check(ProfessionRules.stats_for_level(id,50) == ProfessionRules.stats_for_level(PlayerState.profession,50),"formal profession preserves primary generated growth "+id)
	var previous: Variant = PlayerState.get("profession_id")
	check(not PlayerState.call("set_profession_identity","法师") and PlayerState.get("profession_id") == previous,"typed setter rejects display name without partial mutation")
	check(not PlayerState.call("set_profession_identity","hc.skill.wizard.lightning") and PlayerState.get("profession_id") == previous,"typed setter rejects cross-kind registered identity")
	check(not PlayerState.call("set_profession_identity","hc.profession.unknown") and PlayerState.get("profession_id") == previous,"unknown formal identity preserves old owner")
	PlayerState.profession = "法师"
	check(PlayerState.get("profession_id") == "hc.profession.wizard","explicit legacy property import converts exact old name once")
	PlayerState.profession = "未知职业"
	check(PlayerState.get("profession_id") == "hc.profession.wizard","unknown legacy identity cannot overwrite the character")
	check(ProfessionRules.stats_for_level("hc.profession.unknown",50).is_empty(),"unknown identity cannot fall back to warrior growth")
	check(GameData.get_profession_skills("hc.profession.wizard") == GameData.get_profession_skills("法师"),"registered profession reaches the real skill catalog")
	check(GameData.player_base_appearance("hc.profession.wizard","男") == GameData.player_base_appearance("法师","男"),"formal profession reaches exact existing appearance authority")
	var skill := ProfessionRules.skill_profile("hc.skill.wizard.lightning")
	check(not skill.is_empty() and skill.get("profession_entity_id") == "hc.profession.wizard","formal skill profile carries registered profession identity")
	check(ProfessionRules.skill_display_name("hc.skill.wizard.lightning") == "雷电术","formal identity displays the registered skill name")
	var before_inventory := PlayerState.inventory.duplicate(true)
	var before_equipment := PlayerState.equipment.duplicate(true)
	PlayerState.select_profession("hc.profession.wizard")
	check(PlayerState.profession_id == "hc.profession.wizard" and PlayerState.inventory == before_inventory \
		and PlayerState.equipment == before_equipment,"selecting the current formal profession changes no equipment ownership")
	PlayerState.select_profession("hc.profession.warrior")
	check(PlayerState.profession_id == "hc.profession.warrior" and PlayerState.profession == "战士","actual profession switch accepts formal identity and preserves display")
	check(not PlayerState.select_profession("hc.profession.unknown").is_empty() and PlayerState.profession_id == "hc.profession.warrior","unknown transactional switch preserves the current profession")
	PlayerState.reset_progress(false)
	_finish()
func _finish() -> void:
	if not proof.write_receipt("profession_identity_owner_test",checks,errors.size()): errors.append("receipt")
	print("PROFESSION_IDENTITY_OWNER_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL",checks,str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
