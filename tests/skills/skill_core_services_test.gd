extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const CastRequest := preload("res://scripts/skills/skill_cast_request.gd")
const CastResult := preload("res://scripts/skills/skill_cast_result.gd")
const TargetService := preload("res://scripts/skills/skill_target_service.gd")
const ResourceService := preload("res://scripts/skills/skill_resource_service.gd")
const GeometryService := preload("res://scripts/skills/skill_geometry_service.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var request := CastRequest.create(
		"wizard.fireball", 3, 40, Vector2i(10, 10), Vector2i.RIGHT,
		{"has_target": true, "line_of_sight": true, "hostile": true},
		{"mana": 100, "materials": {}}, 77
	)
	assert(CastRequest.validate(request).valid)
	assert(request.client_claimed_damage == null and request.client_claimed_success == null)
	var fireball := Loader.skill("wizard.fireball")
	assert(TargetService.validate(fireball, request.target_context).valid)
	assert(not TargetService.validate(fireball, {"has_target": true, "line_of_sight": false}).valid)
	var fireball_quote := ResourceService.quote(fireball, 3, request.resource_context)
	assert(fireball_quote.valid and fireball_quote.mp_cost == 9)
	assert(ResourceService.committed_context(request.resource_context, fireball_quote).mana == 91)
	var talisman := Loader.skill("taoist.soul_fire_talisman")
	var no_amulet := ResourceService.quote(talisman, 3, {"mana": 100, "materials": {"amulet": 0}})
	assert(not no_amulet.valid and no_amulet.reason == "insufficient_material")
	var amulet_quote := ResourceService.quote(talisman, 3, {"mana": 100, "materials": {"amulet": 2}})
	assert(amulet_quote.valid and amulet_quote.material_amount == 1)
	var poison := Loader.skill("taoist.poison")
	assert(not ResourceService.quote(poison, 0, {"mana": 100, "materials": {}}).valid)
	assert(ResourceService.quote(poison, 0, {
		"mana": 100,
		"selected_material": "grey_powder",
		"materials": {"grey_powder": 1},
	}).valid)
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
	assert(lightning_cells.size() == 16 and not lightning_cells.has(Vector2i.ZERO))
	var failure := CastResult.failure("wizard.fireball", "invalid_target")
	assert(not failure.accepted and failure.proficiency_event.is_empty())
	var success := CastResult.success("wizard.fireball", {
		"runtime_family": "single_projectile_damage",
		"proficiency_event": "valid_projectile_cast_created",
		"effects": [{"type": "damage"}],
	})
	assert(success.accepted and success.effects.size() == 1)
	print("SKILL_CORE_SERVICES_PASS: request/result, target, resources and tile geometry")
	get_tree().quit()
