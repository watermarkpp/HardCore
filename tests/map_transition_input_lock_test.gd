extends Node

# Overlap test with inline lock logic
var _locks: Dictionary = {}
var _player_input_enabled := true

func _acquire(reason: StringName) -> void:
	var c: int = int(_locks.get(reason, 0))
	_locks[reason] = c + 1
	_player_input_enabled = _locks.is_empty()

func _release(reason: StringName) -> void:
	var c: int = int(_locks.get(reason, 0))
	if c <= 1:
		_locks.erase(reason)
	else:
		_locks[reason] = c - 1
	_player_input_enabled = _locks.is_empty()

func is_enabled() -> bool:
	return _player_input_enabled


func _ready() -> void:
	# Overlap: acquire both
	_acquire("map_transition")
	_acquire("initial_world_bootstrap")
	assert(not is_enabled())

	# Release one → still disabled
	_release("initial_world_bootstrap")
	assert(not is_enabled())
	assert(_locks.has("map_transition"))

	# Release last → enabled
	_release("map_transition")
	assert(is_enabled())

	# Counted: double acquire → single release doesn't unlock
	_acquire("map_transition")
	_acquire("map_transition")
	assert(not is_enabled())
	assert(int(_locks.get("map_transition", 0)) == 2)
	_release("map_transition")
	assert(not is_enabled())
	_release("map_transition")
	assert(is_enabled())

	print("MAP_TRANSITION_INPUT_LOCK_TEST_PASS")
	get_tree().quit(0)
