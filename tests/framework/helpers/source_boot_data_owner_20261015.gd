extends RefCounted
const Shared := preload("res://scripts/gameplay/world/world_owner_enemy_shared.gd")
const Fields := preload("res://scripts/gameplay/world/world_source_field_port.gd")
const SkillFields := preload("res://scripts/gameplay/world/world_skill_full_fields.gd")
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
var _host: Object
var _settings: Dictionary
var _checks: Array[Dictionary]=[]
var _owner:=OS.get_thread_caller_id()
func owner_thread_id() -> int:return _owner
func get_setting(key: String,fallback: Variant=null) -> Variant:return _settings.get(key,fallback)
func fault(code: String,details: Dictionary) -> void:_check(false,code+str(details))
func _check(value: bool,label: String) -> void:_checks.append({"pass":value,"label":label})
func _init(host: Object,boot: Dictionary) -> void:
	_host=host;_settings=boot.settings
	var shared:=Shared.new()
	var initialized: bool=shared.configure_original_handoff(boot.shared)
	_check(initialized,"actual Source accepts first construction separately from an existing-state handoff")
	if initialized:
		_check(not shared.original_handoff_applied(),"receipt alone does not claim configured original owner")
		var links:=Registry.new()
		_check(shared.bind_current_world({"ProjectSettings":self},links),"same original Shared.configure executes on S")
		_check(shared.original_handoff_applied() and shared._configured,"original construction applied once")
		_check(shared.get("_owner_decision_interval_ms")==_settings["hardcore/performance/owner_decision_interval_ms"],"original configured pursuit interval not overwritten by uninitialized default")
		_check(shared.get("_ordinary_contact_instant_settle_enabled")==_settings["hardcore/performance/ordinary_contact_instant_settle"],"original immediate contact policy is retained")
		_check(shared.get("_target_grid").is_empty() and shared.get("_attack_ab_queue").is_empty(),"fresh original shared caches contain no fabricated actor identities")
		_check(not shared.configure_original_handoff(boot.shared),"initial construction cannot reset an initialized owner")
		var bad: Dictionary=boot.shared.duplicate(true);bad.source_sha256="wrong"
		var refused:=Shared.new()
		_check(not refused.configure_original_handoff(bad),"different shared algorithm cannot claim original initialization")
	var skills:=SkillFields.new()
	var fields:=Fields.new()
	_check(fields.configure_owner(self,skills,boot.fields),"actual sole Root field port adopts complete runtime constructor graph")
	var expected: Dictionary=preload("res://scripts/gameplay/source/source_constructor_value_codec.gd").decode(boot.fields)
	_check(expected.get("ok")==true,"actual Source constructor representation decodes")
	for key: String in boot.fields.fields:
		if key in ["locked_target","magic_locked_target","_skill_cast_target"] or key in boot.fields.unbound_owner_fields:continue
		_check(fields.has_source_field(key) and fields.read_source_field(key)==expected.value[key],"actual Source initial value:"+key)
	var rng:=RandomNumberGenerator.new()
	_check(fields.bind_owner_field(&"_rng",rng),"one actual Source RNG binds at original late owner point")
	_check(is_same(fields.read_source_field(&"_rng"),rng),"RNG slot holds exactly the bound authority")
func on_inputs(_domain: String,_packets: Array) -> bool:return true
func on_phase(phase: String,_frame: Dictionary) -> bool:return _host.publish_snapshot({"done":true,"checks":_checks},[]) if phase=="PUBLISH" else true
func close_session() -> bool:return true
