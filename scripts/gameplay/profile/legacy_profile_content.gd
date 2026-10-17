extends RefCounted
const ContentPort := preload("res://scripts/gameplay/profile/profile_content_port.gd")
static var _legacy: ContentPort

static func resolve(content: ContentPort = null) -> ContentPort:
	if content != null: return content
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy == null:
		# Resolve the main autoload at the adapter boundary. A compile-time
		# GameData reference cycles through GameData -> Pricing -> this adapter.
		var tree := Engine.get_main_loop() as SceneTree
		assert(tree != null)
		_legacy = ContentPort.new(tree.root.get_node("GameData"))
	return _legacy
