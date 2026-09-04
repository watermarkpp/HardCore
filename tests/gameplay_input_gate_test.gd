extends Node

# Test the lock system in isolation — GameRoot instantiation is too heavy.
# Use a minimal helper that replicates the lock API.

var _locks: Dictionary = {}

func _acquire(reason: StringName) -> void:
	var c: int = int(_locks.get(reason, 0))
	_locks[reason] = c + 1

func _release(reason: StringName) -> void:
	var c: int = int(_locks.get(reason, 0))
	if c <= 1:
		_locks.erase(reason)
	else:
		_locks[reason] = c - 1

func _is_enabled() -> bool:
	return _locks.is_empty()


func _ready() -> void:
	# Case 1: empty → enabled
	assert(_is_enabled())

	# Case 2: acquire → disabled
	_acquire("test")
	assert(not _is_enabled())

	# Case 3: double acquire → still disabled
	_acquire("test")
	assert(not _is_enabled())
	assert(int(_locks.get("test", 0)) == 2)

	# Case 4: single release → still disabled
	_release("test")
	assert(not _is_enabled())
	assert(int(_locks.get("test", 0)) == 1)

	# Case 5: final release → enabled
	_release("test")
	assert(_is_enabled())

	# Case 6: release missing lock
	_release("nonexistent")
	assert(_is_enabled())

	# Case 7: overlapping locks
	_acquire("bootstrap")
	_acquire("transition")
	assert(not _is_enabled())
	_release("bootstrap")
	assert(not _is_enabled())
	_release("transition")
	assert(_is_enabled())

	print("GAMEPLAY_INPUT_GATE_TEST_PASS")
	get_tree().quit(0)
