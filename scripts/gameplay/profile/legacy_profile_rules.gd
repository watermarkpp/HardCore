extends RefCounted
const RuleSet := preload("res://scripts/gameplay/profile/profile_rule_set.gd")
static var _rules: RuleSet
static func for_content(content: Object) -> RuleSet:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _rules == null: _rules = RuleSet.new(content)
	return _rules
static func rules() -> RuleSet:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _rules == null:
		load("res://scripts/gameplay/profile/legacy_profile_content.gd").resolve()
	assert(_rules != null)
	return _rules
