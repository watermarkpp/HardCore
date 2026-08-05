extends Node

# Minimal lock test using inline lock logic (no GameRoot required)
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
	# Default: enabled
	assert(is_enabled())
	assert(_locks.is_empty())

	# Bootstrap starts
	_acquire("initial_world_bootstrap")
	assert(not is_enabled())
	assert(_locks.has("initial_world_bootstrap"))

	# Bootstrap completes
	_release("initial_world_bootstrap")
	assert(is_enabled())
	assert(not _locks.has("initial_world_bootstrap"))

	# Verify legacy field
	assert(_player_input_enabled)

	print("INITIAL_WORLD_INPUT_LOCK_TEST_PASS")
	get_tree().quit(0)
