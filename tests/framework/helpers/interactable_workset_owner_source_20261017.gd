extends RefCounted
## Actual Native Source with the same owner-local production rule class;
## no Profile/World admission or game startup is claimed by this component.
const Rules := preload("res://scripts/gameplay/profile/rules/professions_core.gd")
const Workset := preload("res://scripts/gameplay/world/world_interactable_workset.gd")
var _host: Object
var _rules: RefCounted
var _checks: Array[Dictionary] = []
func _check(ok: bool, label: String) -> void: _checks.append({"passed":ok,"label":label})
func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_rules = Rules.new(boot.growth_path)
	_check(OS.get_thread_caller_id() == host.owner_thread_id() and OS.get_thread_caller_id() != OS.get_main_thread_id(),"actual Source executes the production workset with its own rule owner")
	_check(_rules.get_instance_id() != boot.main_owner_id and _rules.get("_owner_thread_id") == host.owner_thread_id(),"Source has its own production rule cache and never borrows the Main owner")
	for row: Dictionary in boot.cases:
		var actual: Array[String] = Workset.workset_skill_order(row.values,_rules,int(row.limit))
		_check(actual == row.expected,"Source order, deduplication and limit match the actual original Main oracle:"+row.id)
func on_inputs(_domain: String, _packets: Array) -> bool: return true
func on_phase(phase: String, _frame: Dictionary) -> bool:
	return _host.publish_snapshot({"done":true,"checks":_checks},[]) if phase == "PUBLISH" else true
func close_session() -> bool:
	_rules = null
	return true
