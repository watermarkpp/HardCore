extends RefCounted
## One original Profile resource/transaction next_service continuation. The
## registration watermark is an actual Native Main-SIGNAL observation.
signal released
var signal_highwater: int
var _completed := false
func _init(actual_signal_highwater: int) -> void:
	signal_highwater = actual_signal_highwater
func complete_at_original_service() -> void:
	assert(not _completed)
	_completed = true
	released.emit()
