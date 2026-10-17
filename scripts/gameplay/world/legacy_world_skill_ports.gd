extends RefCounted

## This adapter alone observes the existing M GameRoot/Node state. It is never
## part of the value publication or passed to S. Every read is live.
var _root_ref: WeakRef
var _owner := OS.get_thread_caller_id()

func _init(root: Node) -> void:
	if _owner != OS.get_main_thread_id() or root == null: return
	_root_ref = weakref(root)

func _root() -> Node:
	if OS.get_thread_caller_id() != _owner: return null
	return _root_ref.get_ref() if _root_ref != null else null

func read_field(name: String) -> Variant:
	var root := _root()
	return root.get(name) if root != null else null

func write_field(name: String, value: Variant) -> void:
	var root := _root()
	if root != null: root.set(name, value)

func player() -> Object:
	return read_field("player")

func locked_target() -> Object:
	return read_field("locked_target")

func runtime_actor_id(actor: Object) -> int:
	return actor.get_instance_id() if _root() != null and is_instance_valid(actor) else 0

func magic_shield_auto_refresh_ratio() -> float:
	return PlayerCharacter.MAGIC_SHIELD_AUTO_REFRESH_RATIO if _root() != null else 0.0

func gameplay_input_is_enabled() -> bool:
	var root := _root()
	return root != null and root.gameplay_input_is_enabled()

func is_action_pressed(action: StringName) -> bool:
	return _root() != null and Input.is_action_pressed(action)

func is_action_just_pressed(action: StringName) -> bool:
	return _root() != null and Input.is_action_just_pressed(action)

func now_msec() -> int:
	return Time.get_ticks_msec() if _root() != null else 0

func _button() -> Object:
	var hud: Variant = read_field("hud")
	return hud.attack_button if is_instance_valid(hud) and is_instance_valid(hud.attack_button) else null

func has_button_lifecycle_snapshot() -> bool:
	var button := _button()
	return button != null and button.has_method("input_lifecycle_snapshot")

func button_lifecycle_snapshot() -> Dictionary:
	var button := _button()
	return button.call("input_lifecycle_snapshot") if button != null else {}

func has_button_lifecycle_owner() -> bool:
	var button := _button()
	return button != null and button.has_method("owns_lifecycle_input")

func button_owns_lifecycle_input(token: int, touch_id: int, source: StringName) -> bool:
	var button := _button()
	return button != null and button.call("owns_lifecycle_input", token, touch_id, source)

func activate_magic_skill_domain() -> void:
	var root := _root()
	if root != null: root._activate_magic_skill_domain()

func try_release_skill(skill_name: String, show_feedback: bool) -> StringName:
	var root := _root()
	return root._try_release_skill(skill_name, show_feedback) if root != null else &""

func request_mobile_attack() -> bool:
	var root := _root()
	return root != null and root._request_mobile_attack()

func show_error_message(message: String, duration: Variant = null) -> void:
	if _root() == null: return
	var hud: Variant = read_field("hud")
	if duration == null: hud.show_error_message(message)
	else: hud.show_error_message(message, float(duration))

func show_message(message: String, duration: Variant = null) -> void:
	if _root() == null: return
	var hud: Variant = read_field("hud")
	if duration == null: hud.show_message(message)
	else: hud.show_message(message, float(duration))
