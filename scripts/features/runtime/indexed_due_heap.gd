extends RefCounted

# One live node per effect handle. Refresh and cancellation update/remove the
# existing node; obsolete generations never accumulate in the queue.
var _heap: Array[Dictionary] = []
var _positions: Dictionary = {}
var _sequence := 0
func size() -> int: return _heap.size()
func due_usec() -> int: return int(_heap[0].due) if not _heap.is_empty() else 9223372036854775807
func contains(handle: String) -> bool: return _positions.has(handle)
func put(handle: String, due: int) -> void:
	if _positions.has(handle):
		var index: int = _positions[handle]
		_heap[index].due = due
		_up(index); _down(int(_positions[handle]))
		return
	_sequence += 1
	_positions[handle] = _heap.size()
	_heap.append({"handle":handle,"due":due,"sequence":_sequence})
	_up(_heap.size()-1)
func pop() -> String:
	if _heap.is_empty(): return ""
	var handle: String = _heap[0].handle
	remove(handle)
	return handle
func remove(handle: String) -> void:
	if not _positions.has(handle): return
	var index: int = _positions[handle]
	var last := _heap.size()-1
	_swap(index,last)
	_heap.pop_back(); _positions.erase(handle)
	if index < _heap.size():
		var moved: String = _heap[index].handle
		_up(index); _down(int(_positions[moved]))
func clear() -> void:
	_heap.clear(); _positions.clear()
func _less(a: int,b: int) -> bool:
	return _heap[a].due < _heap[b].due or (_heap[a].due == _heap[b].due and _heap[a].sequence < _heap[b].sequence)
func _swap(a: int,b: int) -> void:
	var value: Dictionary = _heap[a]; _heap[a] = _heap[b]; _heap[b] = value
	_positions[_heap[a].handle] = a; _positions[_heap[b].handle] = b
func _up(index: int) -> void:
	while index > 0:
		var parent := (index-1)/2
		if not _less(index,parent): break
		_swap(index,parent); index = parent
func _down(index: int) -> void:
	while index*2+1 < _heap.size():
		var child := index*2+1
		if child+1 < _heap.size() and _less(child+1,child): child += 1
		if not _less(child,index): break
		_swap(child,index); index = child
