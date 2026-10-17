extends RefCounted

## No physics Node or secondary HP authority. Projectile/field position is
## the original logical effect scalar, never a duplicate character body.
signal retired()
var _owner := OS.get_thread_caller_id()
var _runtime_actor_id := 0
var global_position := Vector2.ZERO
var _actors: RefCounted
var _world: RefCounted
var _clock: RefCounted
var _random: RefCounted
var _global_random: RefCounted
var _profile: RefCounted
var _rules: RefCounted
var _combat: RefCounted
var _claims: RefCounted
var _presentation: RefCounted
var _source_link: RefCounted
var _configured := false

var source_actor: Object:
	get: return _source_link.borrow_model() if _source_link != null else null
	set(value):
		if _source_link != null: _source_link.dispose()
		_source_link = _actors.capture(value) if value != null else null

func configure_effect(bindings: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _configured: return false
	for key: String in ["actors","world","clock","random","global_random","profile","rules","combat","claims","presentation"]:
		if not bindings.get(key) is RefCounted or bindings[key] is Resource: return false
	_actors = bindings.actors
	_world = bindings.world
	_clock = bindings.clock
	_random = bindings.random
	_global_random = bindings.global_random
	_profile = bindings.profile
	_rules = bindings.rules
	_combat = bindings.combat
	_claims = bindings.claims
	_presentation = bindings.presentation
	_configured = true
	return true

func bind_runtime_actor_id(value: int) -> bool:
	if not _configured or value <= 0 or (_runtime_actor_id > 0 and _runtime_actor_id != value): return false
	_runtime_actor_id = value
	return true

func runtime_actor_id() -> int:
	assert(OS.get_thread_caller_id() == _owner and _runtime_actor_id > 0)
	return _runtime_actor_id

func position_screen_px() -> Vector2:
	return global_position

func set_position_screen_px(value: Vector2) -> void:
	assert(OS.get_thread_caller_id() == _owner and value.is_finite())
	global_position = value

func close_effect() -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if _source_link != null: _source_link.dispose()
	_source_link = null
	retired.emit()
