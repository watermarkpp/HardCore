extends RefCounted
## Original unhandled pointer press, in the real Viewport canvas coordinates.
static func capture_main(root: Node2D, event: InputEvent) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_instance_valid(root) or not root.is_inside_tree(): return {}
	var kind: String
	var index := 0
	var position: Vector2
	if event is InputEventScreenTouch and event.pressed:
		kind="touch";index=event.index;position=event.position
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		kind="mouse_left";position=event.position
	else: return {}
	var viewport: Viewport=root.get_viewport()
	var transform: Transform2D=viewport.get_canvas_transform()
	if viewport.is_input_handled() or not viewport.physics_object_picking or not position.is_finite() or not transform.is_finite() or transform.determinant()==0.0: return {}
	return {"contract_id":"hardcore.input.original_pick_press.v1","actual_root_id":root.get_instance_id(),"actual_viewport_id":viewport.get_instance_id(),"kind":kind,"index":index,"position":position,"canvas_transform":transform,"canvas_position":transform.affine_inverse()*position,"canvas_instance_id":0,"sort":viewport.physics_object_picking_sort,"first_only":viewport.physics_object_picking_first_only}
static func validate(fact: Dictionary, world: Dictionary) -> bool:
	return fact.get("contract_id")=="hardcore.input.original_pick_press.v1" and fact.get("actual_root_id")==world.get("world_runtime_id") and fact.get("actual_viewport_id") is int and fact.actual_viewport_id>0 and fact.get("kind") in ["touch","mouse_left"] and fact.get("index") is int and fact.index>=0 and fact.get("position") is Vector2 and fact.position.is_finite() and fact.get("canvas_transform") is Transform2D and fact.canvas_transform.is_finite() and fact.canvas_transform.determinant()!=0.0 and fact.get("canvas_position") is Vector2 and fact.canvas_position==fact.canvas_transform.affine_inverse()*fact.position and fact.get("canvas_instance_id")==0 and fact.get("sort") is bool and fact.get("first_only") is bool
static func source_event(fact: Dictionary) -> InputEvent:
	if fact.kind=="touch":
		var touch:=InputEventScreenTouch.new();touch.position=fact.position;touch.index=fact.index;touch.pressed=true;return touch
	var mouse:=InputEventMouseButton.new();mouse.position=fact.position;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true;return mouse
