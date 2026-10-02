extends RefCounted

## The registered node owns an internal child. Its destruction is observable
## even outside the tree; copied metadata cannot prolong that ownership.
const META := &"_ui_registration_lifetime"

class Lifetime extends Node:
	var target_id := 0
	var registrations: Dictionary = {}

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			# The parent destroys this child regardless of outside references.
			# Notify only surviving observers; they coalesce deferred weak cleanup.
			for registration: Dictionary in registrations.values():
				var callback: Callable = registration.retired
				if callback.is_valid():
					callback.call()

static func claim(target: Node, observer: Node, role: StringName, on_retired: Callable) -> bool:
	var reference: WeakRef = target.get_meta(META) as WeakRef if target.has_meta(META) else null
	var token: Lifetime = reference.get_ref() as Lifetime if reference != null else null
	# Internal children are not duplicated. Metadata holds only a weak handle,
	# so an unclaimed copy cannot retain the original target's lifetime.
	if token == null or token.target_id != target.get_instance_id():
		token = Lifetime.new()
		token.target_id = target.get_instance_id()
		target.set_meta(META,weakref(token))
		target.add_child(token,false,Node.INTERNAL_MODE_BACK)
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
