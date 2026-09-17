extends SceneTree

## WALL-P1R C10 pixel-diff gate (headless, pure Image math).
## Compares two same-spot screenshots (legacy vs optimized consumer captures)
## and emits a per-pixel delta heatmap plus machine-checkable stats.
## Usage:
##   godot --headless --path . -s res://tools/wall_pixel_diff.gd -- \
##       a=<png> b=<png> out=<heatmap.png> json=<stats.json> tolerance=8

func _init() -> void:
	var a_path := ""
	var b_path := ""
	var out_path := ""
	var json_path := ""
	var tolerance := 8
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"a": a_path = pair[1]
			"b": b_path = pair[1]
			"out": out_path = pair[1]
			"json": json_path = pair[1]
			"tolerance": tolerance = int(pair[1])
	if a_path.is_empty() or b_path.is_empty() or out_path.is_empty():
		printerr("WALL_PIXEL_DIFF missing a/b/out args")
		quit(1)
		return
	var image_a := Image.load_from_file(ProjectSettings.globalize_path(a_path))
	var image_b := Image.load_from_file(ProjectSettings.globalize_path(b_path))
	if image_a == null or image_b == null:
		printerr("WALL_PIXEL_DIFF load failed")
		quit(1)
		return
	if image_a.get_size() != image_b.get_size():
		printerr("WALL_PIXEL_DIFF size mismatch %s vs %s" % [
			str(image_a.get_size()), str(image_b.get_size()),
		])
		quit(1)
		return
	var width := image_a.get_width()
	var height := image_a.get_height()
	var diff := Image.create(width, height, false, Image.FORMAT_RGB8)
	var differing := 0
	var max_delta := 0
	var delta_sum := 0
	var delta_pixels := 0
	for y: int in height:
		for x: int in width:
			var ca := image_a.get_pixel(x, y)
			var cb := image_b.get_pixel(x, y)
			var dr := int(absf(ca.r8 - cb.r8))
			var dg := int(absf(ca.g8 - cb.g8))
			var db := int(absf(ca.b8 - cb.b8))
			var channel_max: int = max(dr, max(dg, db))
			delta_sum += dr + dg + db
			delta_pixels += 1
			if channel_max > max_delta:
				max_delta = channel_max
			if channel_max > tolerance:
				differing += 1
				diff.set_pixel(x, y, Color(1.0, 0.0, 0.0))
			elif channel_max > 0:
				var level := float(channel_max) / float(tolerance)
				diff.set_pixel(x, y, Color(0.0, level, 0.0))
			else:
				diff.set_pixel(x, y, Color(0.0, 0.0, 0.25))
	diff.save_png(ProjectSettings.globalize_path(out_path))
	var stats := {
		"contract_id": "hardcore.wall_render_c10_pixel_diff.v1",
		"a": a_path,
		"b": b_path,
		"tolerance": tolerance,
		"width": width,
		"height": height,
		"differing_pixels": differing,
		"differing_ratio": float(differing) / float(width * height),
		"max_channel_delta": max_delta,
		"mean_abs_delta": float(delta_sum) / float(delta_pixels * 3),
		"heatmap": out_path,
	}
	print("WALL_PIXEL_DIFF_RESULT %s" % JSON.stringify(stats))
	if not json_path.is_empty():
		var file := FileAccess.open(json_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(stats, "\t"))
		file.close()
	quit(0)
