class_name AdaptiveButtonStyleBox
extends StyleBox

var compact: StyleBoxTexture
var standard: StyleBoxTexture
var wide: StyleBoxTexture

func configure(c: Texture2D, s: Texture2D, w: Texture2D, margins := Vector4(36, 0, 36, 0)) -> AdaptiveButtonStyleBox:
	compact = _make(c, margins)
	standard = _make(s, margins)
	wide = _make(w, margins)
	return self

func _make(texture: Texture2D, margins: Vector4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture
	sb.set_texture_margin(SIDE_LEFT, margins.x); sb.set_texture_margin(SIDE_TOP, margins.y)
	sb.set_texture_margin(SIDE_RIGHT, margins.z); sb.set_texture_margin(SIDE_BOTTOM, margins.w)
	sb.content_margin_left = margins.x; sb.content_margin_right = margins.z
	sb.draw_center = true
	return sb

func choose(rect: Rect2) -> StyleBoxTexture:
	var ratio := rect.size.x / maxf(rect.size.y, 1.0)
	return compact if ratio <= (10.0 / 3.0) else (standard if ratio <= 4.67 else wide)

func _draw(canvas_item: RID, rect: Rect2) -> void:
	choose(rect).draw(canvas_item, rect)
