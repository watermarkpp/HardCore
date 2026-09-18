extends SceneTree

## P1-1 diagnostic: classify the spatial distribution of differing pixels
## in a heatmap PNG. Concentrated large blobs indicate structural wall
## differences; many small scattered clusters indicate animation-phase
## noise. Prints cluster stats for the R8 verdict JSON.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	for arg: String in args:
		if arg.begins_with("heat="):
			path = arg.substr(5)
	if path.is_empty():
		printerr("HEATSTATS missing heat=")
		quit(1)
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		printerr("HEATSTATS load failed")
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var clusters: Array = []
	for y: int in h:
		for x: int in w:
			var idx := y * w + x
			if visited[idx] == 1:
				continue
			var c := img.get_pixel(x, y)
			# Red pixels encode channel_max > tolerance (the differing
			# set); green sub-tolerance levels and the dark-blue
			# background are ignored.
			if c.r8 <= 128 or c.g8 > 64:
				visited[idx] = 1
				continue
			# BFS this non-black cluster.
			var queue: Array = [[x, y]]
			visited[idx] = 1
			var size := 0
			var min_x := x
			var max_x := x
			var min_y := y
			var max_y := y
			while not queue.is_empty():
				var cell: Array = queue.pop_back()
				size += 1
				min_x = mini(min_x, cell[0])
				max_x = maxi(max_x, cell[0])
				min_y = mini(min_y, cell[1])
				max_y = maxi(max_y, cell[1])
				for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = cell[0] + d[0]
					var ny: int = cell[1] + d[1]
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nidx := ny * w + nx
					if visited[nidx] == 1:
						continue
					var nc := img.get_pixel(nx, ny)
					if nc.r8 > 128 and nc.g8 <= 64:
						visited[nidx] = 1
						queue.append([nx, ny])
			clusters.append({
				"size": size,
				"bbox": [min_x, min_y, max_x, max_y],
			})
	clusters.sort_custom(func(a, b): return int(a["size"]) > int(b["size"]))
	var total := 0
	for c: Dictionary in clusters:
		total += int(c["size"])
	var report := {
		"total_differing": total,
		"cluster_count": clusters.size(),
		"largest_clusters": clusters.slice(0, 8),
	}
	print("HEATSTATS ", JSON.stringify(report))
	quit(0)
