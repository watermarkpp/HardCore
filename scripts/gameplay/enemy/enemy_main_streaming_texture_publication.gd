extends "res://scripts/gameplay/enemy/enemy_main_visual_publication.gd"

## Uses the one Main primitive owner, whose reference slots mirror S roots.
## Other catalog/viewport publication methods remain inherited unchanged.
var _primitive_owner: RefCounted

func configure_primitive_owner(provider: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _primitive_owner != null or provider == null or not provider.has_method("texture_for_renderer"):
		return false
	_primitive_owner = provider
	return true

func texture_from_token(token: int) -> Texture2D:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _primitive_owner == null:
		push_error("Main renderer has no canonical primitive resource owner")
		return null
	return _primitive_owner.texture_for_renderer(token)
