extends Node

const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")


func _ready() -> void:
	for skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		for wire_contract_id: String in [
			SpellGeometry.CONTRACT_ID,
			SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID,
		]:
			var plan := CasterSkillRuntime.resolve(skill_id, {
				"skill_level": 3,
				"caster_level": 40,
				"owner_level": 40,
				"target_level": 20,
				"target_max_hp": 500,
				"magic_stat_roll": 30,
				"random_0_to_10": 0,
			})
			plan["canonical_geometry_contract"] = wire_contract_id
			plan["geometry_origin_screen_px"] = Vector2(100.0, 100.0)
			plan["geometry_grid_cells"] = []
			plan["geometry_screen_points_px"] = []
			assert(
				CasterSkillRuntime.create_visual(
					plan, Vector2(100.0, 100.0), Vector2.DOWN
				) == null,
				"%s/%s rendered a full fallback line for a terrain-truncated zero-GU strip"
				% [skill_id, wire_contract_id]
			)
			plan["geometry_screen_points_px"] = [Vector2(100.0, 132.0)]
			var normalized_context := SpellGeometry.visual_context_from_plan(
				skill_id,
				plan,
				Vector2(100.0, 100.0)
			)
			assert(normalized_context.canonical_geometry_contract == SpellGeometry.CONTRACT_ID)
			assert(normalized_context.canonical_geometry_source_wire_contract == wire_contract_id)
			var one_gu_visual := CasterSkillRuntime.create_visual(
				plan, Vector2(100.0, 100.0), Vector2.DOWN
			)
			assert(one_gu_visual != null)
			assert(one_gu_visual._geometry_screen_offsets_px == [Vector2(0.0, 32.0)])
			one_gu_visual.free()
	print(
		"CASTER_LINE_ZERO_GEOMETRY_VISUAL_PASS: explicit zero-GU line geometry cannot fall back to full 5/8-GU visuals"
	)
	get_tree().quit(0)
