extends RefCounted

const FeatureResources := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const ChildActions := preload("res://scripts/features/contracts/child_action_lease.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Entities := preload("res://scripts/identity/entity_registry.gd")
const Categories := preload("res://scripts/identity/item_category_identity.gd")
const Skills := preload("res://scripts/skills/skill_data_loader.gd")
const Rank := preload("res://scripts/skills/skill_rank_extension_policy.gd")
const Combat := preload("res://scripts/combat_resolution_rules.gd")
const Taoist := preload("res://scripts/taoist_combat_math.gd")
const Runes := preload("res://scripts/items/rune_item_rules.gd")
const Gems := preload("res://scripts/items/socket_gem_rules.gd")
const Granted := preload("res://scripts/equipment_granted_skill_rules.gd")
## Compile the complete rules DAG on M; S only constructs its own instances.
const ProfileRulesScript := preload("res://scripts/gameplay/profile/profile_rule_set.gd")
const LegacyProfileRulesScript := preload("res://scripts/gameplay/profile/legacy_profile_rules.gd")

## These are existing validated catalogs, never dynamic instance caches.
const CATALOGS := [
	[FeatureResources, ["_loaded", "_result"]],
	[ChildActions, ["_definitions", "_catalog_attempted"]],
	[Entities, ["_document", "_by_id", "_by_legacy", "_service_for_item", "_attempted", "last_errors"]],
	[Categories, ["_by_id", "_legacy", "last_error"]],
	[Skills, ["_document", "_skills_by_id", "_ids_by_alias", "_configuration_revision"]],
	[Rank, ["_policy", "_validation"]],
	[Taoist, ["_rules_cache", "_summon_baseline_cache"]],
	[Combat, ["_contract_cache"]],
	[Runes, ["_records"]], [Gems, ["_record"]],
	[Granted, ["_records_by_skill", "_records_by_item", "_records_by_display_name", "_loaded", "last_errors"]],
]
static var _main_fields: Array = []
static var _lease: Dictionary = {}

static func acquire() -> Dictionary:
	if not Gate.write_allowed(): return {}
	if not FeatureResources.declarations().success or ChildActions._definition_for("hc.child.death_burst.v1").is_empty(): return {}
	if not Entities.ensure_loaded() or not Categories.ensure_loaded() or not Granted.ensure_loaded(): return {}
	if Skills.document().is_empty() or not Rank.validation().get("valid", false): return {}
	if Combat.contract().is_empty(): return {}
	if Taoist._rules().is_empty() or Taoist._summon_baseline().is_empty(): return {}
	if not Runes.ensure_loaded() or not Gems.ensure_loaded(): return {}
	var fields: Array = []
	for catalog: Array in CATALOGS:
		var values: Dictionary = {}
		for name: String in catalog[1]: values[name] = catalog[0].get(name)
		fields.append(values)
	var captured := Graph.capture(fields)
	if not captured.success: return {}
	# Replace together on M before starting any registered S/W reader. Retained
	# M references cannot mutate the new publication, which owns its own graph.
	_main_fields = fields
	for index in CATALOGS.size():
		for name: String in CATALOGS[index][1]:
			CATALOGS[index][0].set(name, captured.value[index][name])
	_lease = Gate.publish(Graph.fingerprint(captured.value))
	return _lease

static func enter_reader(token: Dictionary) -> bool:
	return Gate.enter_reader(token)

static func leave_reader(token: Dictionary) -> bool:
	return Gate.leave_reader(token)

## Low level release for the native host's proven world/producer/worker
## quiescence point. This class additionally refuses any registered reader.
static func release_after_host_quiescence(token: Dictionary) -> bool:
	if token != _lease or not Gate.release_after_host_quiescence(token): return false
	for index in CATALOGS.size():
		for name: String in CATALOGS[index][1]:
			CATALOGS[index][0].set(name, _main_fields[index][name])
	_main_fields = []
	_lease = {}
	return true
