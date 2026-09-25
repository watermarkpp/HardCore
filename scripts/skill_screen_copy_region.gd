class_name SkillScreenCopyRegion
extends RefCounted


## BackBufferCopy.rect is local to its parent. The copy and sprite are siblings,
## so transform the sprite's full drawing rect into that shared coordinate space.
static func parent_rect(sprite: Sprite2D) -> Rect2:
	if sprite == null or sprite.texture == null:
		return Rect2()
	var local_rect := sprite.get_rect()
	if not local_rect.has_area():
		return Rect2()
	var bounds := sprite.transform * local_rect
	var from := bounds.position.floor() - Vector2.ONE * 2.0
	var to := bounds.end.ceil() + Vector2.ONE * 2.0
	return Rect2(from, to - from)


static func sync(copy: BackBufferCopy, sprite: Sprite2D) -> void:
	if copy == null:
		return
	var bounds := parent_rect(sprite)
	copy.rect = bounds
	copy.visible = sprite != null and sprite.visible and bounds.has_area()
