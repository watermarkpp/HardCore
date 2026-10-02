extends RefCounted

## The registered node owns this token. Its release is observable even when
## the node was detached earlier, without polling or retaining the node.
const META := &"_ui_registration_lifetime"

class Lifetime extends RefCounted:
	var target_id := 0
	var registrations: Dictionary = {}

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			# RefCounted self is already null at this notification in Godot.
			# Invoke the surviving observer directly, never a method/signal on self.
			for registration: Dictionary in registrations.values():
				var callback: Callable = registration.retired
				if callback.is_valid():
					callback.call()

static func claim(target: Node, observer: Node, role: StringName, on_retired: Callable) -> bool:
	var token: Lifetime = target.get_meta(META) as Lifetime if target.has_meta(META) else null
	# Node.duplicate can copy metadata references; a copied node owns a new
	# registration lifetime even when its metadata points at the original token.
	if token == null or token.target_id != target.get_instance_id():
		token = Lifetime.new()
		token.target_id = target.get_instance_id()
		target.set_meta(META,token)
	# A live detached control can outlive an observer. Do not retain retired
	# observer identities or confuse a replacement observer with its predecessor.
	for key: Variant in token.registrations.keys():
		if (token.registrations[key].owner as WeakRef).get_ref() == null:
			token.registrations.erase(key)
	var owner_id := observer.get_instance_id()
	if not token.registrations.has(owner_id):
		token.registrations[owner_id] = {"owner":weakref(observer),"roles":{},"retired":on_retired}
	var roles: Dictionary = token.registrations[owner_id].roles
	if roles.has(role):
		return false
	roles[role] = true
	return true
