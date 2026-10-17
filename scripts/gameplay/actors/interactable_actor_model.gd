extends RefCounted

## Former Node2D data owner. Scope/Handle remain the only lifetime authority.
var _owner := OS.get_thread_caller_id()
var _ports: RefCounted
var _scope: RefCounted
var _runtime_id := 0
var _position := Vector2.ZERO
var _ready_complete := false
var _visual_bound := false
var global_position: Vector2:
	get: return _position
	set(value): set_position_screen_px(value)
var position: Vector2:
	get: return _position
	set(value): set_position_screen_px(value)

func owner_thread_id() -> int: return _owner
func configure_owner(ports: RefCounted, scope: RefCounted) -> bool:
	if _ports != null or _owner == OS.get_main_thread_id() or ports == null or scope == null or ports.owner_thread_id() != _owner or scope.owner_thread_id() != _owner: return false
	_ports = ports; _scope = scope
	return true
func bind_runtime_actor_id(id: int) -> bool:
	if OS.get_thread_caller_id() != _owner or _runtime_id != 0 or id <= 0: return false
	_runtime_id = id; return true
func current_life() -> int: return _scope.life_generation if _scope != null else 0
func can_receive_damage() -> bool: return false # The original Node2D has no combat/HP interface.
func position_screen_px() -> Vector2: return _position
func set_position_screen_px(value: Vector2) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if not value.is_finite(): _ports.fail("interactable_nonfinite_pose"); return
	_position = value
	if _ports != null and _runtime_id != 0 and _scope.is_inside_world() and not _ports.publish_pose(self): _ports.fail("interactable_pose_commit_failed")
func add_to_group(group: StringName) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if not _ports.add_to_group(self,group): _ports.fail("interactable_original_group_failed")
func queue_free() -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if not _ports.queue_retirement(self): _ports.fail("interactable_original_retirement_failed")
func is_inside_tree() -> bool: return _scope != null and _scope.is_inside_world()
func is_queued_for_retirement() -> bool: return _scope == null or _scope.is_queued_for_retirement()
