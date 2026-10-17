extends RefCounted

## No catalog preload here: catalogs depend on this guard. Only the publisher
## creates/releases leases on M; every S/W reader registers its real thread.
static var _mutex := Mutex.new()
static var _generation := 0
static var _active: Dictionary = {}
static var _readers: Dictionary = {}

static func write_allowed() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	_mutex.lock()
	var allowed := _active.is_empty()
	_mutex.unlock()
	return allowed

static func publish(revision: String) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {}
	_mutex.lock()
	if not _active.is_empty():
		_mutex.unlock()
		return {}
	_generation += 1
	_active = {"contract_id": "content.catalog.publication.v1", "generation": _generation,
		"revision": revision, "publisher_thread_id": OS.get_main_thread_id()}
	_active.make_read_only()
	var result := _active
	_mutex.unlock()
	return result

static func is_active(token: Dictionary) -> bool:
	_mutex.lock()
	var valid := not _active.is_empty() and token == _active
	_mutex.unlock()
	return valid

static func enter_reader(token: Dictionary) -> bool:
	var owner := OS.get_thread_caller_id()
	if owner == OS.get_main_thread_id(): return false
	_mutex.lock()
	var valid := not _active.is_empty() and token == _active
	if valid: _readers[owner] = int(_readers.get(owner, 0)) + 1
	_mutex.unlock()
	return valid

static func owns_reader(token: Dictionary) -> bool:
	_mutex.lock()
	var valid := not _active.is_empty() and token == _active and _readers.has(OS.get_thread_caller_id())
	_mutex.unlock()
	return valid

static func leave_reader(token: Dictionary) -> bool:
	var owner := OS.get_thread_caller_id()
	_mutex.lock()
	var valid := not _active.is_empty() and token == _active and _readers.has(owner)
	if valid:
		var remaining := int(_readers[owner]) - 1
		if remaining == 0: _readers.erase(owner)
		else: _readers[owner] = remaining
	_mutex.unlock()
	return valid

static func reader_count() -> int:
	_mutex.lock()
	var count := 0
	for value: int in _readers.values(): count += value
	_mutex.unlock()
	return count

## The native host calls only after its owned world, accepted producers and
## worker window have quiesced. Reader drainage is checked here additionally;
## zero readers alone is not a production lifecycle proof.
static func release_after_host_quiescence(token: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	_mutex.lock()
	var valid := not _active.is_empty() and token == _active and _readers.is_empty()
	if valid: _active = {}
	_mutex.unlock()
	return valid


static func has_active_reader() -> bool:
	_mutex.lock()
	var valid := not _active.is_empty() and _readers.has(OS.get_thread_caller_id())
	_mutex.unlock()
	return valid
