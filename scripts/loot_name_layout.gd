extends RefCounted

## 2026-09-26: each label belongs to its own icon. Position a new item once;
## crowded text does not trigger searches or move already visible names.
static func place_at_home(pickup: Node2D) -> void:
	if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
		return
	var label: Label = pickup.get("name_label")
	if not is_instance_valid(label):
		return
	var home: Vector2 = pickup.name_label_home_position()
	if pickup.name_label_display_offset != Vector2.ZERO or label.position != home:
		pickup.set_name_label_display_offset(Vector2.ZERO)


## Explicit bulk callers (e.g. local diagnostics) may initialize a batch.
## Production registration calls place_at_home on only the incoming item.
static func arrange(pickups: Array) -> void:
	for pickup: Node2D in pickups:
		place_at_home(pickup)
