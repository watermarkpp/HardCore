extends RefCounted

## Typed dependency boundary; simulation injects an owner-local published content view.
var _source: Object
var _owner_thread_id := OS.get_thread_caller_id()

func _init(source: Object, simulation := false) -> void:
	assert(source != null)
	assert(not simulation or not source is Node, "simulation content must not reference a main Node")
	_source = source

func _assert_owner() -> void:
	assert(OS.get_thread_caller_id() == _owner_thread_id)

var enabled_expansions: Dictionary:
	get:
		_assert_owner()
		return _source.get("enabled_expansions")

func feature_configuration() -> Dictionary:
	_assert_owner()
	return _source.callv("feature_configuration", [])

func enabled_package_ids() -> Array[String]:
	_assert_owner()
	return _source.callv("enabled_package_ids", [])

func apply_expansion_configuration(requested: Dictionary, commit_profile: Callable = Callable()) -> bool:
	_assert_owner()
	return _source.callv("apply_expansion_configuration", [requested, commit_profile])


var feature_load_errors: Array:
	get:
		_assert_owner()
		return _source.get("feature_load_errors")
var last_expansion_error: String:
	get:
		_assert_owner()
		return _source.get("last_expansion_error")
