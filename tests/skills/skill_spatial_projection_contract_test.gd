extends Node

const Contract := preload(
	"res://scripts/skills/skill_spatial_projection_contract.gd"
)
const Loader := preload("res://scripts/skills/skill_data_loader.gd")

const EXPECTED_RELATIONSHIPS := {
	"warrior.basic_swordsmanship": "inherits_release",
	"warrior.slaying_swordsmanship": "inherits_release",
	"warrior.thrusting": "directed_core",
	"warrior.half_moon": "directed_core",
	"warrior.wild_rush": "movement_sweep",
	"warrior.fire_sword": "inherits_release",
	"wizard.fireball": "projectile_sweep",
	"wizard.repulsion_ring": "ground_exact",
	"wizard.temptation_light": "target_footprint",
	"wizard.hellfire": "directed_core",
	"wizard.lightning": "target_footprint",
	"wizard.teleport": "movement_sweep",
	"wizard.great_fireball": "projectile_sweep",
	"wizard.exploding_flame": "ground_exact",
	"wizard.fire_wall": "ground_exact",
	"wizard.laser": "directed_core",
	"wizard.hell_lightning": "ground_exact",
	"wizard.magic_shield": "attached_state",
	"wizard.holy_word": "target_footprint",
	"wizard.ice_storm": "ground_exact",
	"taoist.healing": "target_footprint",
	"taoist.spiritual_warfare": "non_spatial",
	"taoist.poison": "target_footprint",
	"taoist.soul_fire_talisman": "projectile_sweep",
	"taoist.summon_skeleton": "movement_sweep",
	"taoist.invisibility": "attached_state",
	"taoist.mass_invisibility": "ground_exact",
	"taoist.magic_defense": "ground_exact",
	"taoist.defense": "ground_exact",
	"taoist.revelation": "target_footprint",
	"taoist.entrapment": "ground_exact",
	"taoist.mass_healing": "ground_exact",
	"taoist.summon_divine_beast": "movement_sweep",
}


func _ready() -> void:
	var canonical_ids := Array(Loader.skill_ids())
	var entries := Contract.entries()
	assert(canonical_ids.size() == 33)
	assert(entries.size() == 33)
	assert(EXPECTED_RELATIONSHIPS.size() == 33)
	var seen: Dictionary = {}
	for entry_data: Dictionary in entries:
		var skill_id := str(entry_data.get("skill_id", ""))
		assert(not skill_id.is_empty())
		assert(not seen.has(skill_id), "duplicate spatial contract: %s" % skill_id)
		seen[skill_id] = true
		assert(canonical_ids.has(skill_id), "non-SOT spatial contract: %s" % skill_id)
		assert(EXPECTED_RELATIONSHIPS.has(skill_id))
		assert(
			str(entry_data.relationship_type) == EXPECTED_RELATIONSHIPS[skill_id],
			"wrong relationship for %s" % skill_id
		)
		assert(Contract.ALLOWED_RELATIONSHIP_TYPES.has(
			str(entry_data.relationship_type)
		))
		for required_field: String in [
			"formal_footprint", "release_anchor", "facing_policy",
			"snapshot_policy", "visual_damage_relation", "damage_space",
			"screen_px_policy", "source_ruleset_id", "source_matrix_id",
		]:
			assert(
				not str(entry_data.get(required_field, "")).is_empty(),
				"%s lacks %s" % [skill_id, required_field]
			)
		assert(entry_data.screen_px_policy == (
			"derived_projection_only_never_damage_input"
		))
		match str(entry_data.relationship_type):
			Contract.NON_SPATIAL:
				assert(entry_data.snapshot_policy == Contract.SNAPSHOT_NONE)
				assert(entry_data.damage_space == "none")
			Contract.INHERITS_RELEASE:
				assert(entry_data.snapshot_policy == Contract.SNAPSHOT_INHERIT)
			Contract.ATTACHED_STATE:
				assert(entry_data.snapshot_policy == Contract.SNAPSHOT_ATTACHED)
				assert(entry_data.damage_space == "none")
			_:
				assert(entry_data.snapshot_policy == Contract.SNAPSHOT_CREATE)
	for skill_id: String in canonical_ids:
		assert(seen.has(skill_id), "missing spatial contract: %s" % skill_id)
		assert(not Contract.entry(skill_id).is_empty())
	assert(
		Contract.entry("wizard.repulsion_ring").secondary_relationships
		== [Contract.MOVEMENT_SWEEP]
	)
	assert(
		Contract.entry("taoist.summon_skeleton").secondary_relationships
		== [Contract.RELEASE_CONTACT]
	)
	assert(
		Contract.entry("taoist.summon_divine_beast").secondary_relationships
		== [Contract.DIRECTED_CORE]
	)
	print(
		"SKILL_SPATIAL_PROJECTION_CONTRACT_PASS: 33/33 canonical skills, "
		+ "zero missing, zero duplicate, exact matrix relationship mapping"
	)
	get_tree().quit(0)
