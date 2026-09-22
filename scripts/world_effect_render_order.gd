class_name WorldEffectRenderOrder
extends RefCounted

## Use the same world plane as actors and walls. Only the presentation proxy
## moves: gameplay origins and drawable global positions remain unchanged.
const CONTRACT_ID := "skills.effect.world_footpoint_y_sort.v2"
const SORT_EPSILON_PX := 0.01

static func create_proxy(owner: Node2D) -> Node2D:
	owner.z_index = 0
	owner.z_as_relative = true
	owner.y_sort_enabled = true
	owner.set_meta("world_effect_render_contract", CONTRACT_ID)
	var proxy := Node2D.new()
	proxy.name = "WorldFootpointVisual"
	proxy.position = Vector2(0.0, -SORT_EPSILON_PX)
	proxy.z_index = 0
	proxy.y_sort_enabled = false
	owner.add_child(proxy)
	return proxy

static func add_visual(proxy: Node2D, visual: Node2D) -> void:
	visual.position.y += SORT_EPSILON_PX
	proxy.add_child(visual)
