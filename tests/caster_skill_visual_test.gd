extends Node

const ASSET_PATHS := [
	"res://assets/art/characters/wizard/effects/arcane_projectile.png",
	"res://assets/art/characters/wizard/effects/area_burst.png",
	"res://assets/art/characters/taoist/effects/soul_fire_talisman.png",
	"res://assets/art/characters/taoist/effects/binding_circle.png",
	"res://assets/art/characters/taoist/effects/summon_skeleton.png",
	"res://assets/art/characters/taoist/effects/summon_divine_beast.png",
]


func _ready() -> void:
	var manifest_file := FileAccess.open("res://assets/data/caster_skill_visuals.json", FileAccess.READ)
	var manifest: Variant = JSON.parse_string(manifest_file.get_as_text()) if manifest_file != null else null
	assert(manifest is Dictionary and str(manifest.get("target_gender", "")) == "male_only", "职业视觉没有锁定男性角色")
	for path: String in ASSET_PATHS:
		assert(ResourceLoader.exists(path), "%s没有导入" % path)
		var texture := load(path) as Texture2D
		assert(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "%s纹理无效" % path)
		var image := texture.get_image()
		assert(image.detect_alpha() != Image.ALPHA_NONE, "%s缺少透明通道" % path)
		for point: Vector2i in [Vector2i.ZERO, Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1), Vector2i(image.get_width() - 1, image.get_height() - 1)]:
			assert(image.get_pixelv(point).a == 0.0, "%s角落没有透明" % path)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	var projectile := SkillProjectile.new()
	projectile.setup(Vector2.ZERO, Vector2.RIGHT, 10, 100.0, Color.CYAN, "damage", 0, 0.0, "wizard.fireball")
	add_child(projectile)
	assert(projectile.skill_id == "wizard.fireball" and projectile._sprite != null, "法师投射物没有装载视觉资源")
	projectile.queue_free()
	var area := GroundSkillEffect.new()
	area.setup(Vector2.ZERO, 1, 72.0, 1.0, Color.CYAN, "wizard.fire_wall")
	add_child(area)
	assert(area.skill_id == "wizard.fire_wall" and area._sprite != null, "法师范围效果没有装载视觉资源")
	area.queue_free()
	print("CASTER_SKILL_VISUAL_PASS：法师/道士6张透明资源与投射物/范围效果装载正常")
	get_tree().quit(0)
