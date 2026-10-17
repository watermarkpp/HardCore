extends RefCounted

## Color.r is a float32 on the original Image. Preserve every component exactly;
## thresholding remains at the original query site after Image-compatible bounds.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _size := Vector2i.ZERO
var _red := PackedFloat32Array()

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(values: Dictionary) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread or not values.get("size") is Vector2i or not values.get("red") is PackedFloat32Array:
		return false
	var size: Vector2i = values.size
	var red: PackedFloat32Array = values.red
	if size.x <= 0 or size.y <= 0 or red.size() != size.x * size.y:
		return false
	for component: float in red:
		if not is_finite(component):
			return false
	_size = size
	_red = red.duplicate()
	_configured = true
	return true

func get_size() -> Vector2i:
	return _size

func get_width() -> int:
	return _size.x

func get_height() -> int:
	return _size.y

func get_pixel(x: int, y: int) -> Color:
	assert(_configured and OS.get_thread_caller_id() == _owner_thread and x >= 0 and y >= 0 and x < _size.x and y < _size.y)
	return Color(_red[y * _size.x + x], 0.0, 0.0, 1.0)
