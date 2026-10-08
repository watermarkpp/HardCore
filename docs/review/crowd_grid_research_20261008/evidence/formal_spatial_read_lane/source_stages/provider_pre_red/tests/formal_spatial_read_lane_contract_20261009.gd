extends Node

## Consumer contract for the bounded formal spatial read lane.
##
## This fixture deliberately contains no guessed production binding call.  A
## future provider is discovered only through has_method/Object.call after the
## provider worker publishes its concrete API.  The stock fallback and index
## publication probes below are real Enemy/RuntimeCombatSpatialIndex paths.

const EnemyScript := preload("res://scripts/enemy.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
## This is the single Enemy-side synchronous read-segment entry.  It remains
## private to Enemy; the fixture uses has_method only so stock source produces
## a clean availability RED instead of a parser-level missing-method error.
const CONSUMER_ENTRY := &"_hc_formal_spatial_read_segment"

var _checks := 0
var _failures := 0


func _ready() -> void:
	_run_contract()
	print(
		"FORMAL_SPATIAL_READ_LANE_CONTRACT_%s checks=%d failures=%d"
		% ["PASS" if _failures == 0 else "FAIL", _checks, _failures]
	)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("FORMAL_SPATIAL_READ_LANE_PASS: " + label)
	else:
		_failures += 1
		push_error("FORMAL_SPATIAL_READ_LANE_FAIL: " + label)


func _identity_projection(value: Vector2) -> Vector2:
	return value


func _run_contract() -> void:
	var index := SpatialIndexScript.new()
	var enemy := EnemyScript.new()
	if not enemy.has_method(CONSUMER_ENTRY):
		_check(false, "Enemy exposes the formal spatial read segment consumer entry")
		print("FORMAL_SPATIAL_READ_LANE_AVAILABILITY_RED: missing %s" % CONSUMER_ENTRY)
		enemy.free()
		index.free()
		get_tree().quit(1)
		return
	enemy.configure_runtime_map_projection(
		7,
		Callable(self, "_identity_projection"),
		Callable(self, "_identity_projection"),
	)
	enemy.set_meta("zone_generation", 1)
	enemy.configure_spatial_index(index, 91)
	enemy.global_position = Vector2(4.0, 6.0)
	index.register(
		91,
		7,
		Vector2(4.0, 6.0),
		1.0,
		1,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)

	_check(
		enemy._screen_position_px_to_ground_position_gu(Vector2(4.0, 6.0)) == Vector2(4.0, 6.0),
		"formal map fallback projection retains production numeric path",
	)

	# The sanctioned writer publishes the same-frame actor position before a
	# later query can observe it.
	enemy.set_combat_position(Vector2(9.0, 11.0), &"contract_same_frame_move")
	_check(
		index._entries[91].absolute_ground_gu == Vector2(9.0, 11.0),
		"same-frame position setter publishes the spatial index",
	)

	# RuntimeCombatSpatialIndex must never overwrite a valid entry with a
	# nonfinite projection; this is a pre-existing formal contract reused here.
	index.update_actor(91, Vector2(INF, 0.0))
	_check(
		index._entries[91].absolute_ground_gu == Vector2(9.0, 11.0),
		"nonfinite position retains the last valid index entry",
	)

	# Generation/environment changes invalidate the Enemy's projection proof;
	# the existing writer must still publish the current position through the
	# live formal path rather than treating the old entry as current.
	enemy.set_meta("zone_generation", 2)
	enemy.set_combat_position(Vector2(12.0, 15.0), &"contract_generation_move")
	_check(
		index._entries[91].absolute_ground_gu == Vector2(12.0, 15.0),
		"generation change forces current-position index publication",
	)

	index.unregister(91)
	enemy.free()
