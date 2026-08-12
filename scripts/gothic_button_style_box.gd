class_name GothicButtonStyleBox
extends StyleBox

var background: StyleBoxTexture
var ornament: Texture2D
var ornament_modulate := Color.WHITE
var ornament_size := Vector2(44, 72)

func configure(bg: Texture2D, margins: Vector4, icon: Texture2D, tint := Color.WHITE) -> GothicButtonStyleBox:
	background = StyleBoxTexture.new()
	background.texture = bg
	background.set_texture_margin(SIDE_LEFT, margins.x)
	background.set_texture_margin(SIDE_TOP, margins.y)
	background.set_texture_margin(SIDE_RIGHT, margins.z)
	background.set_texture_margin(SIDE_BOTTOM, margins.w)
	background.draw_center = true
	background.content_margin_left = margins.x
	background.content_margin_right = margins.z
	background.content_margin_top = 8
	background.content_margin_bottom = 8
	ornament = icon
	ornament_modulate = tint
	return self

func _draw(canvas_item: RID, rect: Rect2) -> void:
	if background:
		background.draw(canvas_item, rect)
	if ornament:
		var draw_size := Vector2(minf(ornament_size.x, rect.size.x), minf(ornament_size.y, rect.size.y))
		var target := Rect2(rect.get_center() - draw_size * 0.5, draw_size)
		RenderingServer.canvas_item_add_texture_rect(canvas_item, target, ornament.get_rid(), false, ornament_modulate)

func ornament_rect(rect: Rect2) -> Rect2:
	var scale := minf(minf(rect.size.x / ornament_size.x, rect.size.y / ornament_size.y), 1.0)
	var draw_size := ornament_size * maxf(scale, 0.0)
	return Rect2(rect.get_center() - draw_size * 0.5, draw_size)
