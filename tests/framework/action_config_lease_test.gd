extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Lease := preload("res://scripts/features/contracts/action_config_lease.gd")
const Effective := preload("res://scripts/features/adapters/effective_skill_definition.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		errors.append(label)

func _ready() -> void:
	var definition := {"skill_id":"wizard.fireball", "entity_id":"hc.skill.wizard.fireball", "geometry":{"maximum_range_gu":4.0}, "mp_cost_by_rank":[2,3,4,5]}
	var effective := Effective.build(definition, [{"field":"geometry.maximum_range_gu","op":"multiply","value":2.0},
		{"field":"geometry.maximum_range_gu","op":"add","value":1.0}], ["geometry.maximum_range_gu"])
	check(bool(effective.success) and float(effective.definition.geometry.maximum_range_gu) == 10.0, "additive then multiplicative skill calculation")
	var versions := {"base_revision":"base-a", "loadout_revision":"loadout-a"}
	var actor := {"world_generation":1, "runtime_id":12, "life_generation":3}
	var stats := {"magic_min":10,"magic_max":20,"luck":2}
	var created := Lease.create(effective.definition,2,50,stats,versions,actor)
	check(bool(created.success), "plain configuration creates lease")
	if bool(created.success):
		var lease: RefCounted = created.lease
		stats.magic_min = 999
		check(int(lease.primary_stats().magic_min) == 10 and lease.primary_stats().is_read_only(), "accepted input graph owns immutable stats")
		check(lease.current_before_accept(versions,actor), "current versions match before accept")
		var stale := versions.duplicate(); stale.loadout_revision = "loadout-b"
		check(not lease.accept(stale,actor) and not lease.valid_for_release(actor), "stale preaccept has no committed lease")
		check(lease.accept(versions,actor), "exact identity accepted once")
		check(not lease.accept(versions,actor), "second accept rejected")
		check(lease.valid_for_release(actor) and lease.versions() == versions, "accepted lease retains config across later content changes")
		var next_life := actor.duplicate(); next_life.life_generation += 1
		check(not lease.valid_for_release(next_life), "new actor life rejects old release")
		check(lease.definition_for("hc.skill.wizard.fireball").is_read_only() and lease.definition_for("unknown.spell").is_empty(), "definition is exact registered identity and frozen")
	var unknown := definition.duplicate(true)
	unknown.skill_id = "fixture.spell"
	check(not bool(Lease.create(unknown, 2, 50, stats, versions, actor).success), "unregistered or mismatched definition identity cannot create lease")
	check(not bool(Effective.build(definition,[{"field":"arbitrary.script","op":"add","value":1}],[]).success), "ungranted field fails")
	check(not bool(Effective.build(definition,[{"field":"geometry.maximum_range_gu","op":"add","value":-10}], ["geometry.maximum_range_gu"]).success), "invalid effective numeric range fails")
	if not proof.write_receipt("action_config_lease_test", checks, errors.size()):
		errors.append("receipt failed")
	print(("FRAMEWORK_ACTION_CONFIG_LEASE_PASS" if errors.is_empty() else "FRAMEWORK_ACTION_CONFIG_LEASE_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
