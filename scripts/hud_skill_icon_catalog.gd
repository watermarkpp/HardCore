class_name HUDSkillIconCatalog
extends RefCounted

const SKILL_TEXTURES := {
	"攻杀剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_power_hit.png"),
	"刺杀剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_long_hit.png"),
	"半月弯刀": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_wide_hit.png"),
	"烈火剑法": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/skill_fire_hit.png"),
}


static func texture_for(skill_name: String) -> Texture2D:
	return SKILL_TEXTURES.get(skill_name) as Texture2D


static func source_id_for(skill_name: String) -> String:
	match skill_name:
		"攻杀剑术": return "ui.hud.skill_icon.warrior.power_hit"
		"刺杀剑术": return "ui.hud.skill_icon.warrior.long_hit"
		"半月弯刀": return "ui.hud.skill_icon.warrior.wide_hit"
		"烈火剑法": return "ui.hud.skill_icon.warrior.fire_hit"
	return ""
