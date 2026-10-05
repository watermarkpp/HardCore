extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0
func check(value: bool, label: String) -> void:
 proof.record(value, label)
 checks += 1
 if not value: errors.append(label)
func _ready() -> void:
 _run.call_deferred()
func _run() -> void:
 var path := "res://scripts/identity/entity_registry.gd"
 check(FileAccess.file_exists(path), "formal unified identity registry exists")
 if not FileAccess.file_exists(path):
  _finish()
  return
 var registry: Variant = load(path)
 check(registry.ensure_loaded(), "generated registry loads through strict runtime validator")
 if registry.document().is_empty():
  print("IDENTITY_ERRORS=" + str(registry.last_errors))
  _finish()
  return
 check(registry.from_legacy("skill", "wizard.lightning") == "hc.skill.wizard.lightning", "skill has registered typed identity")
 check(registry.from_legacy("item", 85) == "hc.item.000085", "item exact numeric authority maps to formal ID")
 check(registry.from_legacy("monster", 19) == "hc.monster.000019", "monster exact numeric identity maps")
 check(registry.from_legacy("map", 910001) == "hc.map.910001", "formal map exact numeric identity maps")
 check(registry.from_legacy("skill", "雷电术").is_empty(), "canonical identity query refuses display name")
 check(registry.from_legacy("item", 85.5).is_empty() and registry.from_legacy("item", true).is_empty(), "numeric identities cannot truncate or coerce")
 check(registry.legacy("hc.monster.000085", "item") == null, "typed domains reject cross-kind identity")
 check(registry.legacy("hc.item.999999", "item") == null, "syntactically valid but unregistered identity rejects")
 check(registry.resolve("hc.item.000085").is_read_only(), "identity record cannot mutate authority")
 var document: Dictionary = registry.document().duplicate(true)
 var before: Dictionary = registry.document()
 document.records.append(document.records[0].duplicate(true))
 check(not registry.publish(document) and registry.document() == before, "duplicate registration rejects atomic publication")
 document = before.duplicate(true)
 document.records[0].id = "hc.未知.000001"
 check(not registry.publish(document) and registry.document() == before, "malformed identity cannot replace registry")
 check(GameData.get_entity_record("hc.item.000085").get("itemId", -1) == 85, "real item consumer resolves formal identity")
 check(GameData.get_entity_record("hc.monster.000019").get("monster_id", -1) == 19, "real monster consumer resolves formal identity")
 check(GameData.get_entity_record("hc.map.910001").get("mapId", -1) == 910001, "real map consumer resolves formal identity")
 var loader: Variant = load("res://scripts/skills/skill_data_loader.gd")
 check(loader.skill("hc.skill.wizard.lightning").get("entity_id") == "hc.skill.wizard.lightning", "real skill definition carries formal identity")
 PlayerState.test_mode = true
 PlayerState.reset_progress(false)
 PlayerState.learned_skills = {"雷电术":2}
 check(PlayerState.learned_skills == {"hc.skill.wizard.lightning":2}, "legacy profile migrates once into unified skill identity")
 check(PlayerState.is_skill_learned("hc.skill.wizard.lightning"), "real progression queries formal identity")
 var slots: Variant = load("res://scripts/skill_loadout_rules.gd")
 var migrated: Dictionary = slots.normalize_assignments({"contract_id":"gameplay.skill.button_assignments.v3", "attack":["雷电术"], "attack_ring":["雷电术", "", "", "", "", ""]})
 check(migrated.contract_id == "gameplay.skill.button_assignments.v4" and migrated.attack[0] == "hc.skill.wizard.lightning", "legacy slot binding migrates to formal ID contract")
 var invalid: Dictionary = slots.normalize_assignments({"contract_id":"gameplay.skill.button_assignments.v4", "attack":["雷电术"], "attack_ring":["", "", "", "", "", ""]})
 check(not bool(invalid.get("valid", true)), "formal slot contract rejects name as an identity")
 var mismatch: Dictionary = slots.assign_button_slot(migrated, PlayerState.learned_skills, {"contract_id":"ui.skill.button_assignment.v3", "slot_group":"attack", "slot_index":0,"skill_id":"wizard.lightning","skill_name":"火球术"})
 check(not mismatch.ok and mismatch.reason == "skill_identity_mismatch", "UI display and identity disagreement is explicit rejection")
 var unknown_legacy := {"contract_id":"gameplay.skill.button_assignments.v3", "attack":["雷电术"], "attack_ring":["未知技能", "", "", "", "", ""]}
 var refused: Dictionary = slots.normalize_assignments(unknown_legacy)
 check(not bool(refused.get("valid", true)), "unknown legacy identity rejects whole binding migration instead of clearing one slot")
 var clear_invalid: Dictionary = slots.clear_button_slot(invalid, {"contract_id":"ui.skill.button_assignment.v3", "slot_group":"attack", "slot_index":0})
 check(not clear_invalid.ok and clear_invalid.reason == "invalid_assignment_identity", "clear operation cannot normalize invalid identity into a valid empty profile")
 var future: Dictionary = slots.normalize_assignments({"contract_id":"gameplay.skill.button_assignments.v999", "attack":["hc.skill.wizard.lightning"]})
 check(not bool(future.get("valid", true)), "future binding schema is explicit rejection")
 _finish()
func _finish() -> void:
 if not proof.write_receipt("entity_registry_test", checks, errors.size()): errors.append("receipt")
 print(("FRAMEWORK_ENTITY_REGISTRY_PASS" if errors.is_empty() else "FRAMEWORK_ENTITY_REGISTRY_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
 get_tree().quit(0 if errors.is_empty() else 1)
