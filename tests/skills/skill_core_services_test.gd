extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const CastRequest := preload("res://scripts/skills/skill_cast_request.gd")
const TargetService := preload("res://scripts/skills/skill_target_service.gd")
const ResourceService := preload("res://scripts/skills/skill_resource_service.gd")
const GeometryService := preload("res://scripts/skills/skill_geometry_service.gd")
const QueryPlan := preload("res://scripts/skills/skill_footprint_query_plan.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var request := CastRequest.create(
		"wizard.fireball", 3, 40, Vector2i(10, 10), Vector2i.RIGHT,
		{"has_target": true, "line_of_sight": true, "hostile": true},
		{"mana": 100, "materials": {}}, 77
	)
	assert(CastRequest.validate(request).valid)
	assert(request.client_claimed_damage == null and request.client_claimed_success == null)
	var immutable_snapshot: Dictionary = {
		"skill_id": "wizard.lightning",
		"release_id": "core_services:immutable_snapshot",
		"shape_type": "target_footprint",
	}
	immutable_snapshot.make_read_only()
	var mutable_nested_target: Dictionary = {"values": [1]}
	var mutable_nested_resource: Dictionary = {"values": [2]}
	var target_context_with_snapshot: Dictionary = {
		"has_target": true,
		"line_of_sight": true,
		"hostile": true,
		"skill_footprint_snapshot": immutable_snapshot,
		"nested": mutable_nested_target,
	}
	var resource_context_with_nested: Dictionary = {
		"mana": 100,
		"nested": mutable_nested_resource,
	}
	var preserved_request: Dictionary = CastRequest.create(
		"wizard.lightning",
		3,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		target_context_with_snapshot,
		resource_context_with_nested,
		78,
	)
	var preserved_target_context: Dictionary = preserved_request.get("target_context", {})
	var preserved_resource_context: Dictionary = preserved_request.get("resource_context", {})
	var preserved_snapshot: Dictionary = preserved_target_context.get("skill_footprint_snapshot", {})
	assert(is_same(preserved_snapshot, immutable_snapshot), "immutable release snapshot identity must survive request creation")
	assert(preserved_snapshot.is_read_only(), "immutable release snapshot must remain read-only")
	assert(
		not is_same(preserved_target_context.get("nested", {}), mutable_nested_target)
			and not is_same(preserved_resource_context.get("nested", {}), mutable_nested_resource),
		"ordinary target/resource nested containers must remain deep-copy isolated"
	)
	(mutable_nested_target["values"] as Array).append(3)
	(mutable_nested_resource["values"] as Array).append(4)
	assert((preserved_target_context.get("nested", {}) as Dictionary).get("values", []) == [1])
	assert((preserved_resource_context.get("nested", {}) as Dictionary).get("values", []) == [2])
	var mutable_snapshot: Dictionary = immutable_snapshot.duplicate(true)
	assert(not mutable_snapshot.is_read_only())
	var mutable_snapshot_request: Dictionary = CastRequest.create(
		"wizard.lightning",
		3,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		{"skill_footprint_snapshot": mutable_snapshot},
		{"mana": 100},
		79,
	)
	var copied_mutable_snapshot: Dictionary = (
		mutable_snapshot_request.get("target_context", {})
	).get("skill_footprint_snapshot", {})
	assert(
		not is_same(copied_mutable_snapshot, mutable_snapshot)
			and not copied_mutable_snapshot.is_read_only(),
		"mutable pseudo-snapshot must remain an isolated mutable request copy"
	)
	var mutable_snapshot_plan: Dictionary = QueryPlan.build(
		"core_services:mutable_snapshot",
		"wizard.lightning",
		910001,
		copied_mutable_snapshot,
		{},
		{"maximum_targets": -1},
	)
	assert(
		not bool(mutable_snapshot_plan.get("valid", false))
			and str(mutable_snapshot_plan.get("failure_reason", "")) == "snapshot_not_immutable",
		"mutable pseudo-snapshot must remain rejected by strict QueryPlan validation"
	)
	var fireball := Loader.skill("wizard.fireball")
	assert(TargetService.validate(fireball, request.target_context).valid)
	assert(not TargetService.validate(fireball, {"has_target": true, "line_of_sight": false}).valid)
	var fireball_quote := ResourceService.quote(fireball, 3, request.resource_context)
	assert(fireball_quote.valid and fireball_quote.mp_cost == 9)
	assert(ResourceService.committed_context(request.resource_context, fireball_quote).mana == 91)
	var talisman := Loader.skill("taoist.soul_fire_talisman")
	var no_amulet := ResourceService.quote(talisman, 3, {"mana": 100, "materials": {"amulet": 0}})
	assert(no_amulet.valid and no_amulet.material_amount == 0 and no_amulet.material_id == "")
	var amulet_quote := ResourceService.quote(talisman, 3, {"mana": 100, "materials": {"amulet": 2}})
	assert(amulet_quote.valid and amulet_quote.material_amount == 0 and amulet_quote.material_id == "")
	var poison := Loader.skill("taoist.poison")
	var poison_quote := ResourceService.quote(poison, 0, {"mana": 100, "materials": {}})
	assert(poison_quote.valid)
	assert(poison_quote.mp_cost == int(poison.get("mp_cost_by_rank", [])[0]) * 2)
	assert(poison_quote.material_amount == 0 and poison_quote.material_id == "")
	assert(poison_quote.material_free)
	assert(
		poison_quote.material_policy_contract_id
		== ResourceService.TAOIST_MATERIAL_FREE_CONTRACT_ID
	)
	for skill_id: String in Loader.skill_ids():
		var definition := Loader.skill(skill_id)
		if str(definition.get("class", "")) != "taoist":
			continue
		var quote := ResourceService.quote(definition, 3, {"mana": 999, "materials": {}})
		assert(quote.valid, "%s should not require cast materials" % skill_id)
		assert(quote.material_amount == 0 and quote.material_id == "")
		assert(quote.material_free)
		assert(
			quote.material_policy_contract_id
			== ResourceService.TAOIST_MATERIAL_FREE_CONTRACT_ID
		)
	var synthetic_wizard_material := {
		"class": "wizard",
		"skill_id": "wizard.material_policy_probe",
		"mp_cost_by_rank": [0, 0, 0, 0],
		"resource": {"item": "amulet", "amount_by_rank": [1, 1, 1, 1]},
	}
	var wizard_material_quote := ResourceService.quote(
		synthetic_wizard_material, 0, {"mana": 100, "materials": {}}
	)
	assert(not wizard_material_quote.valid and wizard_material_quote.reason == "insufficient_material")
	var hellfire_cells := GeometryService.cells(
		Loader.skill("wizard.hellfire"), Vector2i.ZERO, Vector2i.RIGHT
	)
	assert(hellfire_cells == [
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(4, 0), Vector2i(5, 0),
	])
	var exploding_cells := GeometryService.cells(
		Loader.skill("wizard.exploding_flame"),
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i(5, 5)
	)
	assert(exploding_cells.size() == 9 and exploding_cells.has(Vector2i(5, 5)))
	var lightning_cells := GeometryService.cells(
		Loader.skill("wizard.hell_lightning"), Vector2i.ZERO, Vector2i.DOWN
	)
	assert(lightning_cells.size() == 24 and not lightning_cells.has(Vector2i.ZERO))
	# Q3-C: the legacy cast-result helper was removed with the legacy planner.
	# The production result truth is skill_execution_result.v1; these
	# assertions pin the service-level contract only.
	var failure := {
		"contract_id": "skills.cast_result.v1",
		"accepted": false,
		"effect_success": false,
		"skill_id": "wizard.fireball",
		"reason": "invalid_target",
		"resource_commit": false,
		"proficiency_event": "",
		"effects": [],
	}
	assert(not failure.accepted and failure.proficiency_event.is_empty())
	var success := {
		"contract_id": "skills.cast_result.v1",
		"accepted": true,
		"effect_success": true,
		"skill_id": "wizard.fireball",
		"reason": "",
		"resource_commit": true,
		"proficiency_event": "",
		"effects": [{"type": "damage"}],
	}
	assert(success.accepted and success.effects.size() == 1 and success.proficiency_event.is_empty())
	print("SKILL_CORE_SERVICES_PASS: request/result, target, resources and tile geometry")
	get_tree().quit()
