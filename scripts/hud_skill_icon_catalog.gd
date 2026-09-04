class_name HUDSkillIconCatalog
extends RefCounted

const SKILL_TEXTURES := {
	"基本剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/warrior_basic_swordsmanship.png"),
	"攻杀剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/warrior_slaying_swordsmanship.png"),
	"刺杀剑术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/warrior_thrusting.png"),
	"半月弯刀": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/warrior_half_moon.png"),
	"野蛮冲撞": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/warrior_wild_rush.png"),
	"烈火剑法": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/warrior_fire_sword.png"),
	"火球术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_fireball.png"),
	"抗拒火环": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_repulsion_ring.png"),
	"诱惑之光": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_temptation_light.png"),
	"地狱火": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_hellfire.png"),
	"雷电术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_lightning.png"),
	"瞬息移动": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_teleport.png"),
	"大火球": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_great_fireball.png"),
	"爆裂火焰": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_exploding_flame.png"),
	"火墙": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_fire_wall.png"),
	"疾光电影": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_laser.png"),
	"地狱雷光": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_hell_lightning.png"),
	"魔法盾": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_magic_shield.png"),
	"圣言术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_holy_word.png"),
	"冰咆哮": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/wizard_ice_storm.png"),
	"治愈术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_healing.png"),
	"精神力战法": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_spiritual_warfare.png"),
	"施毒术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_poison.png"),
	"灵魂火符": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_soul_fire_talisman.png"),
	"召唤骷髅": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_summon_skeleton.png"),
	"隐身术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_invisibility.png"),
	"集体隐身术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_mass_invisibility.png"),
	"幽灵盾": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_magic_defense.png"),
	"神圣战甲术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_defense.png"),
	"心灵启示": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_revelation.png"),
	"困魔咒": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_entrapment.png"),
	"群体治疗术": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_mass_healing.png"),
	"召唤神兽": preload("res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/taoist_summon_divine_beast.png"),
}

const LEGACY_WARRIOR_SOURCE_IDS := {
	"攻杀剑术": "ui.hud.skill_icon.warrior.power_hit",
	"刺杀剑术": "ui.hud.skill_icon.warrior.long_hit",
	"半月弯刀": "ui.hud.skill_icon.warrior.wide_hit",
	"烈火剑法": "ui.hud.skill_icon.warrior.fire_hit",
}


static func texture_for(skill_name: String) -> Texture2D:
	# Every formal skill has a dedicated generated HUD icon. Do not fall back to
	# combat animation frames or inventory skill-book thumbnails.
	return SKILL_TEXTURES.get(skill_name) as Texture2D


static func source_id_for(skill_name: String) -> String:
	if not SKILL_TEXTURES.has(skill_name):
		return ""
	if LEGACY_WARRIOR_SOURCE_IDS.has(skill_name):
		return str(LEGACY_WARRIOR_SOURCE_IDS[skill_name])
	var skill_id := ProfessionRules.skill_id(skill_name)
	if skill_id.is_empty():
		return ""
	if skill_id.begins_with("wizard.") or skill_id.begins_with("taoist."):
		return "ui.hud.skill_icon.caster.%s" % skill_id
	return "ui.hud.skill_icon.%s" % skill_id


static func source_path_for(skill_name: String) -> String:
	var texture := texture_for(skill_name)
	return texture.resource_path if texture != null else ""
