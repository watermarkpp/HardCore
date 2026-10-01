extends Node
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Identity := preload("res://scripts/monster_identity.gd")
var errors: Array[String] = []
var checks := 0
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
func run() -> void:
	PlayerState.test_mode = true
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Identity.CATALOG_PATH))
	var entries: Dictionary = catalog.entries_by_id
	var profiles: Dictionary = catalog.appearance_profiles
	var rows: Array = []
	var appearance_rows: Array = []
	var emitted: Dictionary = {}
	for key: String in entries:
		var id := int(key)
		var entry: Dictionary = entries[key]
		var data := GameData.get_monster_by_id(id)
		var appearance := Identity.appearance_profile(id)
		var actor := EnemyActor.new()
		actor.setup(data,null,false)
		var profile_id := str(entry.appearance_profile_id)
		var frames := int(appearance.get("actions",{}).get("attack",{}).get("framesPerDirection",0))
		check(not emitted.has(key) and int(entry.monster_id)==id,"exact canonical id "+key)
		check(profiles.has(profile_id) and appearance==profiles.get(profile_id,{}),"exact appearance binding "+key)
		check(actor.monster_id==id and actor.display_name==str(entry.canonical_name),"actual setup identity "+key)
		check(actor._canonical_attack_frame_count(1)==frames and frames>0,"actual frame binding "+key)
		var expected_combat := bool(entry.runtime_allowed) and bool(entry.combat.behavior_profile.get("combatEnabled",true))
		check(actor.combat_enabled==expected_combat,"runtime combat admission matches explicit canonical behavior "+key)
		emitted[key] = true
		var ordinary := actor._source176_ordinary_melee()
		rows.append({"monster_id":id,"display_name":actor.display_name,"classification":entry.classification,
			"source_class":str(actor.attack_delivery_rule.get("kind","ordinary_contact_adapter")),
			"source_revision":"project.source176.adapter.v1; inspect per-field canonical source_evidence",
			"runtime_route":"hc_melee" if actor._hc_standard_melee() else "named_delivery_or_stationary",
			"shape":"relative_box_half_1" if ordinary else "named_delivery_contract",
			"stationary":actor.stationary,"body_radius_gu":actor.combat_radius_gu,
			"frame_count":frames,"appearance_profile_id":profile_id,"runtime_allowed":entry.runtime_allowed,"combat_enabled":actor.combat_enabled,
			"exception":actor.attack_delivery_rule,"evidence_status":"PASS","evidence_scope":"runtime binding only",
			"source_verified":false,"source_evidence":entry.source_evidence})
		actor.free()
	check(emitted.size()==entries.size(),"no omitted or extra canonical identity")
	for key: String in profiles:
		var profile: Dictionary = profiles[key]
		appearance_rows.append({"profile_id":key,"body":profile.get("body",{}),"actions":profile.get("actions",{}),"status":profile.get("status","")})
	check(str(entries.get("89",{}).get("canonical_name",""))=="尸王","89 is actual corpse king")
	check(str(entries.get("239",{}).get("canonical_name",""))!="尸王","legacy239 label cannot stand in for89")
	check(F.write_evidence("MONSTER_IDENTITY_MATRIX",{"checks":checks,"errors":errors,"canonical_count":entries.size(),"rows":rows}),"write identity")
	check(F.write_evidence("APPEARANCE_MATRIX",{"checks":checks,"errors":errors,"profile_count":profiles.size(),"rows":appearance_rows}),"write appearance")
	print(("R3_IDENTITY_EXPORT_PASS" if errors.is_empty() else "R3_IDENTITY_EXPORT_FAIL")+" count="+str(rows.size())+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
