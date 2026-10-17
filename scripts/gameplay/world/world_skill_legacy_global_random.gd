extends RefCounted

## M-only bridge to the original GlobalScope RNG, avoiding accidental calls
## to the GameRoot instance RNG through a method with the same name.
static func draw(low: int, high: int) -> int:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return randi_range(low, high)
