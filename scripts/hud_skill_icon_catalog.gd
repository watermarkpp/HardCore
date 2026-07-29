class_name HUDSkillIconCatalog
extends RefCounted

const SKILL_TEXTURES := {
	"攻杀剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_power_hit.png"),
	"刺杀剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_long_hit.png"),
	"半月弯刀": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_wide_hit.png"),
	"烈火剑法": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_fire_hit.png"),
}


static func texture_for(skill_name: String) -> Texture2D:
	# Warrior icons are a locked HUD contract and keep their original art and
	# priority.  Caster skills use their primary-client animation frame icon via
	# the stable registry, never an inventory/book item thumbnail.
	var warrior_texture := SKILL_TEXTURES.get(skill_name) as Texture2D
	if warrior_texture != null:
		return warrior_texture
	return CasterSkillVisualRegistry.icon_texture(skill_name)


static func source_id_for(skill_name: String) -> String:
	match skill_name:
		"攻杀剑术": return "ui.hud.skill_icon.warrior.power_hit"
		"刺杀剑术": return "ui.hud.skill_icon.warrior.long_hit"
		"半月弯刀": return "ui.hud.skill_icon.warrior.wide_hit"
		"烈火剑法": return "ui.hud.skill_icon.warrior.fire_hit"
	var caster_profile := CasterSkillVisualRegistry.profile(skill_name)
	if (
		caster_profile.get("status", "") == "formal_primary_client_animation"
		and CasterSkillVisualRegistry.icon_texture(skill_name) != null
	):
		return "ui.hud.skill_icon.caster.%s" % str(caster_profile.get("skill_id", ""))
	return ""


static func source_path_for(skill_name: String) -> String:
	var warrior_texture := SKILL_TEXTURES.get(skill_name) as Texture2D
	if warrior_texture != null:
		return warrior_texture.resource_path
	var caster_profile := CasterSkillVisualRegistry.profile(skill_name)
	if caster_profile.get("status", "") != "formal_primary_client_animation":
		return ""
	var icon_path := str(caster_profile.get("icon_path", ""))
	return "res://%s" % icon_path if not icon_path.is_empty() else ""
