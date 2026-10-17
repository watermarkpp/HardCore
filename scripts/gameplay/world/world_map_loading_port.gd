extends RefCounted
const Background := preload("res://scripts/gameplay/world/world_map_build_owner.gd")
var _owner := OS.get_thread_caller_id()
var _root_ref: WeakRef
var _root: RefCounted:
	get: return _root_ref.get_ref() if _root_ref != null else null
	set(value): _root_ref = weakref(value) if value != null else null
var _world_ref: WeakRef
var _world: RefCounted:
	get: return _world_ref.get_ref() if _world_ref != null else null
	set(value): _world_ref = weakref(value) if value != null else null
var _session_ref: WeakRef
var _session: RefCounted:
	get: return _session_ref.get_ref() if _session_ref != null else null
	set(value): _session_ref = weakref(value) if value != null else null
var _warm_ref: WeakRef
var _transport: RefCounted
var background: RefCounted

func owner_thread_id() -> int: return _owner
func configure_owner(root: RefCounted, world: RefCounted, session: RefCounted, factory: RefCounted, transport: RefCounted, publication: Dictionary) -> bool:
	if _root != null or _owner == OS.get_main_thread_id(): return false
	for port: RefCounted in [root,world,session,factory,transport]:
		if port == null or port is Resource or port.owner_thread_id() != _owner: return false
	if publication.get("contract_id") != "source.map.loading.publication.v1" or publication.get("world_context") != world.current_world_identity(): return false
	# Exact source closure is mandatory; capability is not inferred from no World,
	# paused, epoch zero, method names on a Main Node, or a phase string.
	for method: String in ["_source_travel_to_service_home","install_original_map_loading_port"]:
		if not root.has_method(method): return false
	_root = root; _world = world; _session = session; _transport = transport
	background = Background.new()
	return background.configure_owner(world,factory,transport) and root.install_original_map_loading_port(self,background,publication)
func travel_to_service_home(force := false, staged := false, region := "") -> bool:
	return _root._source_travel_to_service_home(force,staged,region)
func begin_original_map_loading(transition: String, generation: int, map_id: int) -> bool:
	return await _transport.open_loading_scope(transition,generation,map_id)
func finish_original_map_loading() -> bool: return await _transport.close_loading_scope()
func transport() -> RefCounted: return _transport
func bind_original_warm_owner(warm: RefCounted) -> bool:
	if _warm_ref != null or warm == null or warm.owner_thread_id() != _owner: return false
	_warm_ref = weakref(warm); return true
func set_loading_window_active(value: bool) -> bool:
	return _warm_ref != null and _warm_ref.get_ref() != null and _warm_ref.get_ref().set_loading_window_active(value)
func retire_pending_warm_textures() -> bool:
	return _warm_ref != null and _warm_ref.get_ref() != null and _warm_ref.get_ref().retire_pending_warm_textures()
func retire_loading_texture_claims() -> bool:
	return _warm_ref != null and _warm_ref.get_ref() != null and _warm_ref.get_ref().retire_loading_texture_claims()
