extends RefCounted

const Professions := preload("res://scripts/gameplay/profile/rules/professions_core.gd")
const Equipment := preload("res://scripts/gameplay/profile/rules/equipment_core.gd")
const AffixV3 := preload("res://scripts/gameplay/profile/rules/affix_v3_core.gd")
const AffixV4 := preload("res://scripts/gameplay/profile/rules/affix_v4_core.gd")
const Mystery := preload("res://scripts/gameplay/profile/rules/mystery_core.gd")
const RandomSpecial := preload("res://scripts/gameplay/profile/rules/random_special_core.gd")
const Enhancement := preload("res://scripts/gameplay/profile/rules/enhancement_core.gd")
const Relic := preload("res://scripts/gameplay/profile/rules/relic_core.gd")
const ItemInstances := preload("res://scripts/gameplay/profile/rules/item_instances_core.gd")
const EnhancementGrade := preload("res://scripts/gameplay/profile/rules/enhancement_grade_core.gd")
const BlackIron := preload("res://scripts/gameplay/profile/rules/black_iron_core.gd")
const TestCharacterProfiles := preload("res://scripts/gameplay/profile/rules/test_character_profiles_core.gd")

var _content_ref: WeakRef
var _owner_thread_id := OS.get_thread_caller_id()
var professions: Professions
var equipment: Equipment
var affix_v3: AffixV3
var affix_v4: AffixV4
var mystery: Mystery
var random_special: RandomSpecial
var enhancement: Enhancement
var relic: Relic
var item_instances: ItemInstances
var enhancement_grade: EnhancementGrade
var black_iron: BlackIron
var test_character_profiles: TestCharacterProfiles

func _init(content: Object) -> void:
	_content_ref = weakref(content)
	professions = Professions.new(str(content.profession_growth_source_path)) if content.simulation_owner else Professions.new("", content)
	affix_v3 = AffixV3.new()
	affix_v4 = AffixV4.new(affix_v3)
	mystery = Mystery.new()
	random_special = RandomSpecial.new()
	enhancement = Enhancement.new()
	relic = Relic.new(professions)
	item_instances = ItemInstances.new(affix_v3, affix_v4, enhancement, random_special, mystery)
	equipment = Equipment.new(professions, mystery, content)
	enhancement_grade = EnhancementGrade.new()
	black_iron = BlackIron.new()
	test_character_profiles = TestCharacterProfiles.new(professions)
