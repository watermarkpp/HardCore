extends RefCounted

## The legacy Main facade's sole shared state. S never calls owner_context().
const Shared := preload("res://scripts/gameplay/actors/enemy_shared_state.gd")
const Access := preload("res://scripts/gameplay/actors/enemy_legacy_access.gd")
static var _main_context: RefCounted
var services: Dictionary
var shared: RefCounted

class SourceText:
	extends RefCounted
	func open_published(path: String) -> FileAccess:
		assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
		return FileAccess.open(path, FileAccess.READ)

static func owner_context() -> RefCounted:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "Main legacy Enemy context used from S")
	if _main_context == null:
		_main_context = new()
		_main_context.initialize()
	return _main_context

func initialize() -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	services = {
		"RuntimeDiagnostics":RuntimeDiagnostics, "Time":Time, "Engine":Engine,
		"GameData":GameData, "PlayerState":PlayerState, "ArtSpec":ArtSpec,
		"WarriorCombatMath":WarriorCombatMath, "ProjectSettings":ProjectSettings,
		"MonsterIdentityScript":preload("res://scripts/monster_identity.gd"),
		"ActorBodyPolicyScript":preload("res://scripts/actor_body_policy.gd"),
		"WorldSpatialRulesScript":preload("res://scripts/world_spatial_rules.gd"),
		"DamageLedgerObserverScript":preload("res://scripts/damage_ledger_observer.gd"),
		"HCDecisionBudget":preload("res://scripts/monster_ai_package/decision_budget.gd"),
		"FrameBudget":preload("res://scripts/layers/runtime/execution/frame_budget.gd"),
		"HCM30ContextTokenScript":preload("res://scripts/monster_ai_package/m30/context_token.gd"),
		"SkillFootprintSnapshotScript":preload("res://scripts/skills/skill_footprint_snapshot.gd"),
		"MonsterTerrainNavigationPolicyScript":preload("res://scripts/monster_terrain_navigation_policy.gd"),
		"CrowdAttackPosition":preload("res://scripts/monster_crowd_attack_position_policy.gd"),
		"HCPPolyRuntime":preload("res://scripts/map_editor/polygon/poly_runtime.gd"),
		"source_text":SourceText.new(),
	}
	shared = Shared.new()
	var configured: bool = shared.configure(services, Access.new())
	assert(configured, "Enemy Main shared state initialization failed")
