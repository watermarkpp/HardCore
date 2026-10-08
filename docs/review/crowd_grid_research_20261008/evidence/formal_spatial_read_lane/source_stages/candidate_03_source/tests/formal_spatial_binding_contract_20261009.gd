extends Node

const RootScript := preload("res://scripts/game_root.gd")
const BridgeScript := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")

const KNOWN_MAP := 913203

var _failures := 0


func _check(condition: bool, detail: String) -> void:
	if not condition:
		_failures += 1
		push_error("FORMAL_SPATIAL_BINDING_FAIL: " + detail)


func _vector_bytes(value: Vector2) -> PackedByteArray:
	return PackedFloat32Array([value.x, value.y]).to_byte_array()


func _override_projection(_value: Vector2) -> Vector2:
	return Vector2(999.0, -999.0)


func _ready() -> void:
	var game: Object = RootScript.new()
	if (
		not game.has_method("acquire_formal_spatial_read_binding")
		or not game.has_method("formal_spatial_read_binding_revision")
	):
		print("HC_TEST_FAIL: formal spatial binding API unavailable")
		game.free()
		get_tree().quit(1)
		return
	var profile: Dictionary = game.call(
		"_resolve_projection_profile_for_map", KNOWN_MAP
	)
	var expected_screen: Callable = profile.get("screen_to_ground", Callable())
	var expected_ground: Callable = profile.get("ground_to_screen", Callable())
	_check(bool(profile.get("success", false)), "known formal map resolves")
	_check(expected_screen.is_valid(), "formal screen provider is callable")
	_check(expected_ground.is_valid(), "formal ground provider is callable")
	var binding: Object = game.call(
		"acquire_formal_spatial_read_binding",
		KNOWN_MAP,
		expected_screen,
		expected_ground
	)
	_check(binding.is_valid(), "matching provider identities bind")
	_check(binding.provider_source() == str(profile.get("source", "")), "source is borrowed")
	_check(binding.provider_policy() == str(profile.get("policy", "")), "policy is borrowed")
	var repeated_binding: Object = game.call(
		"acquire_formal_spatial_read_binding",
		KNOWN_MAP,
		expected_screen,
		expected_ground
	)
	_check(is_same(binding, repeated_binding), "same profile/runtime reuses binding")
	var omitted_binding: Object = game.call(
		"acquire_formal_spatial_read_binding", KNOWN_MAP
	)
	_check(is_same(binding, omitted_binding), "omitted provider assertions reuse binding")
	game.set("current_map_id", KNOWN_MAP)
	var canonical_binding: Object = game.call(
		"acquire_formal_spatial_read_binding",
		KNOWN_MAP,
		Callable(game, "_canonical_screen_px_to_ground_gu"),
		Callable(game, "_canonical_ground_gu_to_screen_px")
	)
	_check(canonical_binding.is_valid(), "canonical GameRoot wrappers bind")
	game.set("reference_audit_mode", true)
	var reference_binding: Object = game.call(
		"acquire_formal_spatial_read_binding",
		KNOWN_MAP,
		expected_screen,
		expected_ground
	)
	_check(not reference_binding.is_valid(), "reference mode rejects formal fast lane")
	game.set("reference_audit_mode", false)
	var inputs := [
		Vector2(10.5, 20.5),
		Vector2(-3.125, 4.75),
		Vector2(NAN, INF),
		Vector2(-INF, NAN),
	]
	for point: Vector2 in inputs:
		var expected_forward: Vector2 = expected_ground.call(point)
		var actual_forward: Vector2 = binding.ground_to_screen_position_px(point)
		_check(
			_vector_bytes(actual_forward) == _vector_bytes(expected_forward),
			"borrowed ground conversion preserves exact output bytes"
		)
		var expected_reverse: Vector2 = expected_screen.call(expected_forward)
		var actual_reverse: Vector2 = binding.screen_to_ground_position_px(actual_forward)
		_check(
			_vector_bytes(actual_reverse) == _vector_bytes(expected_reverse),
			"borrowed screen conversion preserves exact output bytes"
		)

	# A Callable override is an identity assertion, never a replacement path.
	var overridden: Object = game.call(
		"acquire_formal_spatial_read_binding",
		KNOWN_MAP,
		Callable(self, "_override_projection"),
		expected_ground
	)
	_check(not overridden.is_valid(), "mutated provider override fails closed")
	_check(
		_vector_bytes(overridden.ground_to_screen_position_px(Vector2.ONE))
			== _vector_bytes(Vector2.INF),
		"invalid override cannot produce a fast lane value"
	)
	var nonempty_invalid_override: Object = game.call(
		"acquire_formal_spatial_read_binding",
		KNOWN_MAP,
		Callable(self, "_missing_formal_projection_provider"),
		expected_ground
	)
	_check(
		not nonempty_invalid_override.is_valid(),
		"nonempty invalid provider assertion fails closed"
	)

	# Unknown and unpublished maps preserve the original invalid formal result.
	var unknown: Object = game.call(
		"acquire_formal_spatial_read_binding", 2147483000
	)
	_check(not unknown.is_valid(), "unknown formal map has no binding")
	game.set("current_map_id", 2147483000)
	var unknown_original: Dictionary = game.call(
		"_try_canonical_screen_px_to_ground_gu", Vector2.ZERO
	)
	_check(not bool(unknown_original.get("success", false)), "unknown original path rejects")
	var unpublished_map := 4 # primary map catalog id; runtime publication is 910001+
	var unpublished_state := BridgeScript.implementation_state(unpublished_map)
	_check(
		str(unpublished_state.get("state", "")) == "planned_unbuilt",
		"primary map catalog id remains planned before runtime publication"
	)
	var unpublished: Object = game.call(
		"acquire_formal_spatial_read_binding", unpublished_map
	)
	_check(not unpublished.is_valid(), "unpublished map has no fast binding")
	var unmapped: Object = game.call(
		"acquire_formal_spatial_read_binding", -1
	)
	_check(unmapped.is_valid(), "explicit unmapped identity remains formal")
	var unmapped_point := Vector2(2.0, -3.0)
	_check(
		_vector_bytes(unmapped.ground_to_screen_position_px(unmapped_point))
			== _vector_bytes(
				GroundUnitSpace.ground_delta_gu_to_screen_delta_px(unmapped_point)
			),
		"explicit unmapped identity retains original conversion"
	)

	# Replacing the authoritative runtime invalidates the old borrow and makes a
	# new borrow observe the new formal profile in the same frame.
	var original_runtime := BridgeScript.load_map(KNOWN_MAP)
	var replacement := original_runtime.duplicate(true)
	var replacement_size: Array = replacement.design.design_size.duplicate()
	replacement_size[0] = int(replacement_size[0]) + 20
	replacement.design.design_size = replacement_size
	var old_revision: int = binding.lifecycle_revision()
	var old_value: Vector2 = binding.ground_to_screen_position_px(Vector2(10, 10))
	BridgeScript._runtime_cache[KNOWN_MAP] = replacement
	var changed_binding: Object = game.call(
		"acquire_formal_spatial_read_binding", KNOWN_MAP
	)
	var changed_value: Vector2 = changed_binding.ground_to_screen_position_px(Vector2(10, 10))
	_check(changed_binding.is_valid(), "replacement runtime still resolves formally")
	_check(
		_vector_bytes(changed_value) != _vector_bytes(old_value),
		"replacement runtime changes the borrowed formal output"
	)
	_check(
		not binding.is_current(
			KNOWN_MAP,
			replacement,
			changed_binding.lifecycle_revision()
		),
		"old borrow rejects changed runtime identity/revision"
	)
	_check(changed_binding.lifecycle_revision() != old_revision, "revision advances")
	_check(
		not changed_binding.is_current(
			KNOWN_MAP + 1,
			replacement,
			changed_binding.lifecycle_revision()
		),
		"map change invalidates the segment borrow"
	)
	BridgeScript._runtime_cache[KNOWN_MAP] = original_runtime
	var restored_binding: Object = game.call(
		"acquire_formal_spatial_read_binding", KNOWN_MAP
	)
	_check(restored_binding.is_valid(), "restored runtime rebinds formally")
	_check(
		_vector_bytes(restored_binding.ground_to_screen_position_px(Vector2(10, 10)))
			== _vector_bytes(old_value),
		"restored runtime recovers original formal output"
	)

	game.free()
	if _failures == 0:
		print("FORMAL_SPATIAL_BINDING_CONTRACT_PASS")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
