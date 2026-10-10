extends Node

const Geometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures += 1
		print("HC_TEST_FAIL ", label)

func _ready() -> void:
	for skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		check(CasterSkillVisualRegistry.is_runtime_ready(skill_id), skill_id + " formal registry READY")
		for contract: String in [Geometry.CONTRACT_ID, Geometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID]:
			var origin := Vector2(100.0, 100.0)
			var plan := {
				"skill_id": skill_id,
				"visual": CasterSkillVisualRegistry.profile(skill_id),
				"visual_radius_px": 72.0,
				"visual_duration": 0.8,
				"canonical_geometry_contract": contract,
				"geometry_origin_screen_px": origin,
				"geometry_grid_cells": [],
				"geometry_screen_points_px": [],
			}
			var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
			var all_rejected := true
			for attempt in range(3):
				var effect := CasterSkillRuntime.create_visual(plan, origin)
				all_rejected = all_rejected and effect == null
				if effect != null:
					effect.free()
			var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
			check(all_rejected, "%s/%s explicit zero geometry rejected" % [skill_id, contract])
			check(after == before, "%s/%s rejected calls keep orphan count %d -> %d" % [skill_id, contract, before, after])
			plan.geometry_screen_points_px = [origin + Vector2(0.0, 32.0)]
			var normal := CasterSkillRuntime.create_visual(plan, origin)
			check(normal != null, "%s/%s nonempty geometry creates effect" % [skill_id, contract])
			if normal != null:
				check(normal._geometry_screen_offsets_px == [Vector2(0.0, 32.0)], skill_id + " canonical offsets preserved")
				normal.free()
			check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == after, skill_id + " normal effect frees completely")
	if not proof.write_receipt("v109_caster_zero_geometry_ownership_test", proof.records.size(), failures):
		failures += 1
	print("V109_CASTER_ZERO_GEOMETRY_OWNERSHIP_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
