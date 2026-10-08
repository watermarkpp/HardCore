extends RefCounted

## A short lived borrow of the formal map projection.  The owner resolves the
## profile once at the start of a synchronous read segment; this object never
## resolves a profile, reads a map, or caches a frame snapshot.
const INVALID_VECTOR := Vector2.INF
const SCRIPT_PATH := "res://scripts/layers/runtime/spatial/formal_spatial_read_binding.gd"

var _map_id := -1
var _lifecycle_revision := -1
var _runtime_identity: Dictionary = {}
var _profile_source := ""
var _profile_policy := StringName()
var _screen_to_ground := Callable()
var _ground_to_screen := Callable()
var _valid := false


static func from_formal_profile(
	map_id: int,
	profile: Dictionary,
	runtime_identity: Dictionary,
	lifecycle_revision: int,
	expected_screen_callable: Callable = Callable(),
	expected_ground_callable: Callable = Callable()
) -> RefCounted:
	var binding = load(SCRIPT_PATH).new()
	binding._map_id = map_id
	binding._lifecycle_revision = lifecycle_revision
	binding._runtime_identity = runtime_identity
	binding._profile_source = str(profile.get("source", ""))
	binding._profile_policy = str(profile.get("policy", "")) as StringName
	var screen_to_ground: Variant = profile.get("screen_to_ground", Callable())
	var ground_to_screen: Variant = profile.get("ground_to_screen", Callable())
	if (
		not bool(profile.get("success", false))
		or not screen_to_ground is Callable
		or not ground_to_screen is Callable
	):
		return binding
	binding._screen_to_ground = screen_to_ground
	binding._ground_to_screen = ground_to_screen
	if (
		not binding._screen_to_ground.is_valid()
		or not binding._ground_to_screen.is_valid()
	):
		binding._screen_to_ground = Callable()
		binding._ground_to_screen = Callable()
		return binding
	# A supplied consumer identity is an assertion, never an override.  A
	# mismatch forces the original owner path to remain authoritative.
	if (
		not expected_screen_callable.is_null()
		and (
			not expected_screen_callable.is_valid()
			or expected_screen_callable != binding._screen_to_ground
		)
	):
		binding._screen_to_ground = Callable()
		binding._ground_to_screen = Callable()
		return binding
	if (
		not expected_ground_callable.is_null()
		and (
			not expected_ground_callable.is_valid()
			or expected_ground_callable != binding._ground_to_screen
		)
	):
		binding._screen_to_ground = Callable()
		binding._ground_to_screen = Callable()
		return binding
	binding._valid = true
	return binding


func is_valid() -> bool:
	return _valid


func map_id() -> int:
	return _map_id


func lifecycle_revision() -> int:
	return _lifecycle_revision


func provider_source() -> String:
	return _profile_source


func provider_policy() -> StringName:
	return _profile_policy


func screen_callable() -> Callable:
	return _screen_to_ground


func ground_callable() -> Callable:
	return _ground_to_screen


func runtime_identity() -> Dictionary:
	return _runtime_identity


func is_current(
	current_map_id: int,
	current_runtime_identity: Dictionary,
	current_lifecycle_revision: int
) -> bool:
	return (
		_valid
		and current_map_id == _map_id
		and current_lifecycle_revision == _lifecycle_revision
		and is_same(current_runtime_identity, _runtime_identity)
	)


func screen_to_ground_position_px(screen_position_px: Vector2) -> Vector2:
	if not _valid:
		return INVALID_VECTOR
	var value: Variant = _screen_to_ground.call(screen_position_px)
	return value if value is Vector2 else INVALID_VECTOR


func ground_to_screen_position_px(ground_position_gu: Vector2) -> Vector2:
	if not _valid:
		return INVALID_VECTOR
	var value: Variant = _ground_to_screen.call(ground_position_gu)
	return value if value is Vector2 else INVALID_VECTOR
