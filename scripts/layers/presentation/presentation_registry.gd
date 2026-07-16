extends Node

var skin_manifest: Dictionary = {}
var _cache: Dictionary = {}


func _ready() -> void:
	reload_skin()


func reload_skin() -> bool:
	_cache.clear()
	var path := str(ContentLayers.active_skin().get("manifest", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	skin_manifest = parsed if parsed is Dictionary else {}
	return not skin_manifest.is_empty()


func player_texture(action: String) -> Texture2D:
	return _resource("player/%s" % action) as Texture2D


func effect_texture(effect_id: String) -> Texture2D:
	return _resource("effects/%s" % effect_id) as Texture2D


func audio(audio_id: String) -> AudioStream:
	return _resource("audio/%s" % audio_id) as AudioStream


func monster_resources(monster_name: String) -> Dictionary:
	var config: Dictionary = skin_manifest.get("runtimeAssets", {}).get("fallbackMonsters", {}).get(monster_name, {})
	if config.is_empty():
		return {}
	var result := {
		"frame_size": Vector2i(int(config.get("frameSize", [64, 64])[0]), int(config.get("frameSize", [64, 64])[1])),
		"foot_anchor": Vector2i(int(config.get("footAnchor", [32, 52])[0]), int(config.get("footAnchor", [32, 52])[1])),
		"direction_mode": str(config.get("directionMode", "logical_south_first")),
		"animation_source": str(config.get("animationSource", "authored_turnaround")),
		"frame_counts": {"idle":4, "walk":8, "attack":6, "hit":3, "death":6},
	}
	for action: String in ["idle", "walk", "attack", "hit", "death"]:
		var path := "%s/%s_%s.png" % [config.get("folder", ""), config.get("prefix", ""), action]
		if not ResourceLoader.exists(path):
			return {}
		result[action] = load(path) as Texture2D
	return result if MonsterAnimationPolicy.validate(result).is_empty() else {}


func _resource(logical_path: String) -> Resource:
	if _cache.has(logical_path):
		return _cache[logical_path]
	var parts := logical_path.split("/")
	var path := str(skin_manifest.get("runtimeAssets", {}).get(parts[0], {}).get(parts[1], ""))
	var resource := load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	_cache[logical_path] = resource
	return resource
