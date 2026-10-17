extends RefCounted

## Execute the unchanged original M cue/audio/Resource code from ordered S
## VALUE facts. This object never runs a handler, query or damage command.
const Presentation := preload("res://scripts/features/presentation/presentation_port.gd")
const ActorView := preload("res://scripts/features/presentation/domain_actor_view.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
var _provider: WeakRef
var _port: RefCounted
var _through: Dictionary = {}
func configure(provider: Object, world: RefCounted, supported: bool) -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if provider == null or world == null or _port != null: return false
	for method: String in ["resolve_feature_cue_actor", "lookup_feature_resource_lease"]:
		if not provider.has_method(method): return false
	_provider = weakref(provider)
	_port = Presentation.new()
	_port.configure(world,supported)
	return true
func consume(packet: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if _port == null or not Graph.capture(packet).success: return {"success":false,"reason":"feature_presentation_packet"}
	for key: String in ["stream_id", "ordinal", "kind", "handle", "value"]:
		if not packet.has(key): return {"success":false,"reason":"feature_presentation_packet"}
	if not packet.stream_id is String or packet.stream_id.is_empty() or not packet.ordinal is int or packet.ordinal <= 0 or not packet.handle is String or not packet.value is Dictionary:
		return {"success":false,"reason":"feature_presentation_packet"}
	var through := int(_through.get(packet.stream_id,0))
	if packet.ordinal <= through: return {"success":true,"reason":"already_applied"}
	if packet.ordinal != through + 1: return {"success":false,"reason":"feature_presentation_order"}
	var applied := false
	match packet.kind:
		"start", "replace":
			var value: Dictionary = packet.value
			for key: String in ["target", "command", "resource_publication", "resource_retention_id"]:
				if not value.has(key): return {"success":false,"reason":"feature_presentation_descriptor"}
			var resources: RefCounted
			if not value.resource_publication.is_empty():
				resources = _provider.get_ref().call("lookup_feature_resource_lease", value.resource_publication, value.resource_retention_id)
				if resources == null or resources.get_script() != Lease or resources.is_domain(): return {"success":false,"reason":"feature_main_resource_pin_missing"}
			var target := ActorView.new(_provider.get_ref(),value.target)
			applied = _port.start(packet.handle,target,value.command,resources) if packet.kind == "start" else _port.replace(packet.handle,target,value.command,resources)
			if not applied and value.command.get("cue_policy") == "required_procedural": return {"success":false,"reason":"feature_required_main_cue_failed"}
			# Original optional cue absence is a terminal accepted presentation
			# outcome, never a missing required resource or gameplay success.
		"refresh":
			if not packet.value.get("strength") is int: return {"success":false,"reason":"feature_presentation_descriptor"}
			_port.refresh(packet.handle,packet.value.strength)
			applied = true
		"stop":
			_port.stop(packet.handle)
			applied = true
		_:
			return {"success":false,"reason":"feature_presentation_kind"}
	_through[packet.stream_id] = packet.ordinal
	return {"success":true,"reason":"" if applied else "optional_cue_missing"}
func clear_after_quiescence() -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if _port != null: _port.clear()
	_through.clear()
func presentation() -> RefCounted: return _port
