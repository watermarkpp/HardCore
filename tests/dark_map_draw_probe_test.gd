extends Node

## TEMPORARY diagnostic probe (delete after the dark-map frame analysis):
## counts the draw-command load of a map runtime exactly as the production
## renderer would issue it, plus unique textures and wall-part splits.

const RuntimeVisualGeometryService := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const PROBE_MAPS := [
	"res://assets/data/runtime/map_editor/mengzhong_between_life_and_death.runtime.json",
	"res://assets/data/runtime/map_editor/bich_province.runtime.json",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for map_path: String in PROBE_MAPS:
		var loaded: Dictionary = MapEditorRuntimeMapService.load_runtime(map_path)
		assert(loaded.ok, map_path)
		var runtime: Dictionary = loaded.runtime
		var commands := RuntimeVisualGeometryService.sorted_draw_commands(
			runtime.instances
		)
		var textures := {}
		var domains := {}
		var passes := {}
		for command: Dictionary in commands:
			textures[str(command.get("image_path", ""))] = true
			var domain := str(command.get("render_domain", ""))
			domains[domain] = int(domains.get(domain, 0)) + 1
			var image_pass := int(command.get("image_pass", -1))
			passes[image_pass] = int(passes.get(image_pass, 0)) + 1
		var missing := 0
		for image_path: String in textures:
			var res := image_path if image_path.begins_with("res://") else "res://" + image_path
			if not ResourceLoader.exists(res):
				missing += 1
		print(
			"DARK_MAP_PROBE %s instances=%d commands=%d unique_textures=%d missing_assets=%d domains=%s passes=%s blocked=%d"
			% [
				map_path.get_file(),
				runtime.instances.size(),
				commands.size(),
				textures.size(),
				missing,
				str(domains),
				str(passes),
				(runtime.collision.blocked_tiles as Array).size(),
			]
		)
	print("DARK_MAP_PROBE_PASS")
	get_tree().quit(0)
