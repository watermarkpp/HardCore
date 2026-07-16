#!/usr/bin/env python3
"""Generate the repeatable BICH-CLOSE-1 closure audit.

This audit deliberately separates "implemented" from "original-data fidelity".
Having a runnable placeholder never counts as full completion.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from datetime import date
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "assets/data/legend176_data.json"
REGION_PATH = ROOT / "scripts/region_content.gd"
ENVIRONMENT_PATH = ROOT / "scripts/environment_catalog.gd"
PLAYER_PATH = ROOT / "scripts/player.gd"
STATE_PATH = ROOT / "scripts/player_state.gd"
RULES_PATH = ROOT / "scripts/profession_rules.gd"
ROOT_SCRIPT_PATH = ROOT / "scripts/game_root.gd"
GAME_DATA_PATH = ROOT / "scripts/game_data.gd"
ENEMY_PATH = ROOT / "scripts/enemy.gd"
MAP_COORDINATE_PATH = ROOT / "scripts/map_coordinate_mapper.gd"
BICH_PROFILE_PATH = ROOT / "assets/data/bich_source_profiles.json"
NATURAL_CAVE_PROFILE_PATH = ROOT / "assets/data/natural_cave_source_profiles.json"
ORC_TOMB_PROFILE_PATH = ROOT / "assets/data/orc_tomb_source_profiles.json"
MINE_PROFILE_PATH = ROOT / "assets/data/mine_source_profiles.json"
WARRIOR_RULES_PATH = ROOT / "assets/data/warrior_service_rules.json"
WARRIOR_MATH_PATH = ROOT / "scripts/warrior_combat_math.gd"
WARRIOR_ART_PATH = ROOT / "assets/data/warrior_client_art_sources.json"
EQUIPMENT_RULES_PATH = ROOT / "assets/data/equipment_service_rules.json"
EQUIPMENT_DURABILITY_PATH = ROOT / "assets/data/equipment_durability_rules.json"
EQUIPMENT_LUCK_PATH = ROOT / "assets/data/equipment_luck_rules.json"
EQUIPMENT_SPECIAL_PATH = ROOT / "assets/data/equipment_special_rules.json"
EQUIPMENT_CUSTOMIZATION_PATH = ROOT / "assets/data/equipment_customization.json"
EQUIPMENT_ART_PATH = ROOT / "assets/data/equipment_client_art_sources.json"
WARRIOR_WEAR_PATH = ROOT / "assets/data/warrior_wear_sources.json"
BICH_QUEST_PATH = ROOT / "assets/data/bich_quest_chain.json"
BICH_UNDEAD_ART_PATH = ROOT / "assets/data/bich_undead_client_art_sources.json"
BICH_COMMON_ART_PATH = ROOT / "assets/data/bich_common_client_art_sources.json"
BOSS_SERVICE_RULES_PATH = ROOT / "assets/data/boss_service_rules.json"
BICH_COMMUNITY_BASELINE_PATH = ROOT / "assets/data/bich_community_baseline.json"
MILESTONE_APK_PATH = ROOT.parents[1] / "outputs/legend176/MafaOffline_Bich_Milestone_1.apk"
PLAYER_VISUAL_PATH = ROOT / "scripts/player_visual.gd"
HUD_PATH = ROOT / "scripts/hud.gd"
QUEST_PANEL_PATH = ROOT / "scripts/quest_panel.gd"
MONSTER_ART = ROOT / "assets/art/monsters"
OUTPUT_JSON = ROOT / "assets/data/bich_closure_audit.json"
OUTPUT_MD = ROOT / "docs/BICH-CLOSE-1_比奇垂直切片缺口审计.md"

BICH_MAP_IDS = [4, 217, 218, 221, 248, 249, *range(401, 413), 1578]
WARRIOR_SKILLS = ["基本剑术", "攻杀剑术", "刺杀剑术", "半月弯刀", "野蛮冲撞", "烈火剑法"]
FINAL_MONSTER_DIRS = [
    "bich/strawman",
    "bich/rake_cat",
    "bich/half_orc",
    "bich/forest_yeti",
    "bich/cannibal_flower",
    "bosses/skeleton_spirit",
]


@dataclass
class Check:
    category: str
    name: str
    weight: float
    credit: float
    status: str
    evidence: str
    gap: str
    next_task: str

    @property
    def score(self) -> float:
        return self.weight * self.credit


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def exists_all(paths: list[Path]) -> bool:
    return all(path.exists() for path in paths)


def status(credit: float) -> str:
    if credit >= 0.999:
        return "完成"
    if credit <= 0.001:
        return "缺失"
    return "部分完成"


def repair_legacy_gbk(value: object) -> str:
    """Decode legacy GBK text that was historically stored as Latin-1 glyphs."""
    text = str(value or "")
    try:
        repaired = text.encode("latin-1").decode("gbk")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text
    return repaired if any("\u4e00" <= char <= "\u9fff" for char in repaired) else text


def check(category: str, name: str, weight: float, credit: float, evidence: str, gap: str, next_task: str) -> Check:
    normalized = min(1.0, max(0.0, credit))
    return Check(category, name, weight, normalized, status(normalized), evidence, gap, next_task)


def main() -> None:
    data = json.loads(read(DATA_PATH))
    community_baseline = json.loads(read(BICH_COMMUNITY_BASELINE_PATH)) if BICH_COMMUNITY_BASELINE_PATH.exists() else {}
    region = read(REGION_PATH)
    environment = read(ENVIRONMENT_PATH)
    player = read(PLAYER_PATH)
    state = read(STATE_PATH)
    rules = read(RULES_PATH)
    root_script = read(ROOT_SCRIPT_PATH)
    game_data_script = read(GAME_DATA_PATH)
    enemy_script = read(ENEMY_PATH)
    map_coordinate_script = read(MAP_COORDINATE_PATH)
    bich_source = json.loads(read(BICH_PROFILE_PATH)) if BICH_PROFILE_PATH.exists() else {}
    natural_cave_source = json.loads(read(NATURAL_CAVE_PROFILE_PATH)) if NATURAL_CAVE_PROFILE_PATH.exists() else {}
    orc_tomb_source = json.loads(read(ORC_TOMB_PROFILE_PATH)) if ORC_TOMB_PROFILE_PATH.exists() else {}
    mine_source = json.loads(read(MINE_PROFILE_PATH)) if MINE_PROFILE_PATH.exists() else {}
    warrior_rules = json.loads(read(WARRIOR_RULES_PATH)) if WARRIOR_RULES_PATH.exists() else {}
    warrior_math = read(WARRIOR_MATH_PATH)
    warrior_art = json.loads(read(WARRIOR_ART_PATH)) if WARRIOR_ART_PATH.exists() else {}
    equipment_rules = json.loads(read(EQUIPMENT_RULES_PATH)) if EQUIPMENT_RULES_PATH.exists() else {}
    equipment_durability = json.loads(read(EQUIPMENT_DURABILITY_PATH)) if EQUIPMENT_DURABILITY_PATH.exists() else {}
    equipment_luck = json.loads(read(EQUIPMENT_LUCK_PATH)) if EQUIPMENT_LUCK_PATH.exists() else {}
    equipment_special = json.loads(read(EQUIPMENT_SPECIAL_PATH)) if EQUIPMENT_SPECIAL_PATH.exists() else {}
    equipment_customization = json.loads(read(EQUIPMENT_CUSTOMIZATION_PATH)) if EQUIPMENT_CUSTOMIZATION_PATH.exists() else {}
    equipment_art = json.loads(read(EQUIPMENT_ART_PATH)) if EQUIPMENT_ART_PATH.exists() else {}
    warrior_wear = json.loads(read(WARRIOR_WEAR_PATH)) if WARRIOR_WEAR_PATH.exists() else {}
    bich_quest_chain = json.loads(read(BICH_QUEST_PATH)) if BICH_QUEST_PATH.exists() else {}
    boss_service_rules = json.loads(read(BOSS_SERVICE_RULES_PATH)) if BOSS_SERVICE_RULES_PATH.exists() else {}
    bich_undead_art = json.loads(read(BICH_UNDEAD_ART_PATH)) if BICH_UNDEAD_ART_PATH.exists() else {}
    bich_common_art = json.loads(read(BICH_COMMON_ART_PATH)) if BICH_COMMON_ART_PATH.exists() else {}
    player_visual = read(PLAYER_VISUAL_PATH)
    hud = read(HUD_PATH)
    quest_panel = read(QUEST_PANEL_PATH)

    map_records: dict[int, dict] = {}
    for record in data.get("maps", []):
        raw_map_id = record.get("mapId")
        if isinstance(raw_map_id, int) or (isinstance(raw_map_id, str) and raw_map_id.isdigit()):
            map_records[int(raw_map_id)] = record
    runtime_maps = [map_id for map_id in BICH_MAP_IDS if f"{map_id}: {{" in region]
    catalog_maps = [map_id for map_id in BICH_MAP_IDS if map_id in map_records]
    mine_sources = [code for code in ["D401", "D411", "D413", "D402", "D414", "D403", "D412", "D404", "D415", "D405", "D416", "D406"] if code in environment]

    skill_records = data.get("skills", [])
    skill_levels = {
        name: len([record for record in skill_records if repair_legacy_gbk(record.get("skillName", record.get("name"))) == name])
        for name in WARRIOR_SKILLS
    }
    skill_profiles = [name for name in WARRIOR_SKILLS if f'"{name}":' in rules]
    final_art = [name for name in FINAL_MONSTER_DIRS if (MONSTER_ART / name).is_dir()]
    final_action_sets = [
        name for name in final_art
        if exists_all((MONSTER_ART / name / f"{Path(name).name}_{action}.png") for action in ["idle", "walk", "attack", "hit", "death"])
    ]
    undead_mappings = bich_undead_art.get("runtimeMappings", {})
    undead_rejected = bich_undead_art.get("rejectedMappings", [])
    undead_action_sets = [
        name for name, mapping in undead_mappings.items()
        if all(
            action in mapping.get("actions", {})
            and (ROOT / str(mapping["actions"][action].get("path", "")).removeprefix("res://")).exists()
            for action in ["idle", "walk", "attack", "hit", "death"]
        )
    ]
    common_mappings = bich_common_art.get("runtimeMappings", {})
    common_rejected = bich_common_art.get("rejectedMappings", [])
    common_action_sets = [
        name for name, mapping in common_mappings.items()
        if all(
            action in mapping.get("actions", {})
            and (ROOT / str(mapping["actions"][action].get("path", "")).removeprefix("res://")).exists()
            for action in ["idle", "walk", "attack", "hit", "death"]
        )
    ]
    # 骷髅精灵同时存在旧项目资源和客户端资源，只计一个最终怪物组。
    unique_final_art_count = len(final_art) + len(undead_mappings) + len(common_mappings) - (1 if "骷髅精灵" in undead_mappings and "bosses/skeleton_spirit" in final_art else 0)
    unique_action_set_count = len(final_action_sets) + len(undead_action_sets) + len(common_action_sets) - (1 if "骷髅精灵" in undead_action_sets and "bosses/skeleton_spirit" in final_action_sets else 0)

    attack_contract = all(token in player for token in [
        "attack_cooldown := 0.85",
        "attack_animation_duration := 0.51",
        "_attack_action_timer",
    ]) and all(token in root_script for token in ["_on_mobile_attack_pressed", "_on_mobile_attack_released", "_mobile_attack_held"])
    targeting_contract = all(token in root_script for token in [
        "auto_target_enabled", "_refresh_auto_target", "_cycle_target", "_face_locked_target", "movement_performed"
    ])
    passive_sword = "learned_skills.has(\"基本剑术\")" in state and 'result["accuracy"]' in state
    equipment_slots = [slot for slot in ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"] if f'"{slot}": {{}}' in state]
    item_count = len(data.get("items", []))
    bich_zero = bich_source.get("mapProfiles", {}).get("0", {})
    bich_home_mapping = bich_source.get("serviceMapping", {})
    bich_runtime_mapping = bich_source.get("runtimeCoordinateMapping", {})
    bich_source_connected = (
        bich_zero.get("width") == 700
        and bich_zero.get("height") == 700
        and bich_home_mapping.get("serviceHomeMap") == 0
        and bich_home_mapping.get("runtimeMapId") == 4
        and "SERVICE_RUNTIME_MAP_ALIASES := {0: 4}" in game_data_script
        and '"source_map": "0"' in region
    )
    full_size_mapping_connected = (
        bich_runtime_mapping.get("projection") == "isometric_64x32_full_size"
        and bich_runtime_mapping.get("sourceSize") == [700, 700]
        and bich_runtime_mapping.get("worldHomePoint") == [-10528, 3328]
        and all(token in map_coordinate_script for token in ["source_to_world", "world_to_source", "world_bounds", "world_corners"])
        and region.count('"status": "client_map_full_size"') >= 6
        and all(token in region for token in ['"source_size": Vector2i(700, 700)', '"source_size": Vector2i(400, 400)'])
    )
    natural_profiles = natural_cave_source.get("mapProfiles", {})
    natural_cave_connected = (
        natural_profiles.get("248", {}).get("sourceMapCode") == "D011"
        and natural_profiles.get("249", {}).get("sourceMapCode") == "D012"
        and natural_profiles.get("248", {}).get("sha256") == "cfe306b793ec8b7cace580ee1efcf67e1dcbd4b98b4541855a5e070a1b33c067"
        and natural_profiles.get("249", {}).get("sha256") == "b6d301d103b3b6e87b1de46530913ca4c6b92c27f042bd469f356c4fb06147b2"
        and all(token in environment for token in ["NATURAL_CAVE_SOURCE_LAYOUTS", '"asset_set": "natural_cave"', "_build_natural_cave_profile"])
        and all(token in region for token in ['"source_map": "D011"', '"source_map": "D012"'])
    )
    orc_profiles = orc_tomb_source.get("mapProfiles", {})
    orc_tomb_connected = (
        orc_profiles.get("217", {}).get("sha256") == "0047842a53a4806562746f6580859b3b06e2d64a7c4bfeb1ead40831bea2fa24"
        and orc_profiles.get("218", {}).get("sha256") == "ab03734fdc35327cee0f663eb5a020ff69d453e4d3e565483be81521cc7fbe3f"
        and orc_profiles.get("221", {}).get("sha256") == "46f18a27b58bbf76087ddf4df679717beea06eafbe6c19de854fbc0a6cb79d81"
        and all(token in environment for token in ["ORC_TOMB_SOURCE_LAYOUTS", "_build_orc_tomb_source_profile", '"ground_style": "orc_tomb_client"'])
        and all(token in region for token in ['"source_map": "D001"', '"source_map": "D002"', '"source_map": "D003"'])
    )
    warrior_formula_connected = (
        warrior_rules.get("global", {}).get("baseAccuracy") == 5
        and warrior_rules.get("skills", {}).get("烈火剑法", {}).get("damageMultiplierByLevel") == [1.4, 1.8, 2.2, 2.6]
        and "fire_sword_damage" in warrior_math
        and "WarriorCombatMath.active_skill_damage" in root_script
    )
    warrior_state_machine_connected = all(token in player for token in [
        "_next_slaying_proc", "thrusting_enabled", "half_moon_enabled", "fire_sword_armed", "_fire_sword_expires_at_ms"
    ]) and all(token in root_script for token in [
        "_thrust_secondary_target", "_half_moon_targets", "_execute_wild_rush"
    ])
    warrior_art_connected = (
        set(warrior_art.get("effects", {})) >= {"攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"}
        and sorted(sound.get("soundId") for sound in warrior_art.get("sounds", {}).values()
                   if not sound.get("available") and isinstance(sound.get("soundId"), int)) == list(range(130, 138))
        and all(
            (ROOT / path.removeprefix("res://")).exists()
            for effect in warrior_art.get("effects", {}).values()
            for path in (
                [effect["atlas"]] if effect.get("atlas")
                else [value for row in effect.get("atlasShards", {}).get("paths", []) for value in row]
            )
        )
        and all((ROOT / "assets/audio/warrior" / filename).exists()
                for filename in ["51.wav", "52.wav", "57.wav"])
        and all(token in player_visual for token in ["CLIENT_EFFECTS", "ClientSkillEffect", "WeaponAudio"])
        and all(token in hud for token in ["warrior_state_label", "[自动]", "[蓄]"])
    )
    equipment_rules_connected = (
        equipment_rules.get("catalogCoverage", {}).get("equipmentRecords") == 175
        and equipment_rules.get("catalogCoverage", {}).get("concreteStdItemsRecords") == 0
        and "EquipmentRulesScript.requirement_error" in state
        and "max_wear_weight" in state
        and "current_wear_weight" in state
    )
    equipment_durability_connected = (
        equipment_durability.get("adopted", {}).get("zeroDurability") == "装备保留在原槽，属性失效"
        and equipment_durability.get("adopted", {}).get("specialRepair") is False
        and "EquipmentRulesScript.repair_cost" in state
        and "int(equipped_value.get(\"durability\", 1)) <= 0" in state
    )
    equipment_luck_connected = (
        equipment_luck.get("defaults", {}).get("unluckyRate") == 20
        and equipment_luck.get("defaults", {}).get("luckPoints") == [1, 3, 7]
        and "apply_blessing_oil" in state
        and "weapon_luck" in state
        and "weapon_curse" in state
        and "roll_attack_power" in warrior_math
    )
    equipment_special_connected = (
        len(equipment_special.get("runtimeEffects", {})) == 8
        and len(equipment_special.get("registeredOnly", {})) == 0
        and equipment_special.get("rules", {}).get("revivalCooldownMs") == 60000
        and "magicBlood" in equipment_special.get("setCandidates", {})
        and "rainbowDemon" in equipment_special.get("setCandidates", {})
        and "computed_special_effects" in state
        and "damage_special_effect_item" in state
        and "available_special_actions" in state
        and "life_steal_percent" in state
        and equipment_customization.get("schemaVersion") == 1
        and "special_action_pressed" in hud
    )
    equipment_art_mappings = equipment_art.get("runtimeMappings", {})
    equipment_art_connected = (
        len(equipment_art_mappings) == 175
        and not equipment_art.get("unresolvedMappings", [])
        and "apply_equipment_art_mappings" in game_data_script
        and all(field in read(ROOT / "scripts/inventory_panel.gd") for field in ["inventoryIcon", "equippedIcon"])
        and "groundIcon" in read(ROOT / "scripts/loot_pickup.gd")
    )
    warrior_wear_mappings = warrior_wear.get("runtimeMappings", {})
    warrior_wear_connected = (
        len(warrior_wear_mappings) == 24
        and warrior_wear.get("formulaEvidence", {}).get("confidence") == "A"
        and "apply_equipment_wear_mappings" in game_data_script
        and all(token in player_visual for token in ["ClientWeaponLayer", "weaponAppearance", "dressAppearance", "_visual_action_key"])
    )
    bich_quest_connected = (
        len(bich_quest_chain.get("quests", [])) == 6
        and all(token in state for token in ["current_bich_quest_id", "_quest_objectives_complete", "_grant_quest_item_without_commit", "_migrate_quest_states"])
        and "QuestTracker" in hud
        and all(token in quest_panel for token in ["sourceType", "quest_objective_lines", "quest_reward_label"])
    )
    boss_runtime_rules = boss_service_rules.get("runtimeRules", {})
    boss_rules_connected = (
        boss_service_rules.get("serviceEvidence", {}).get("confidence") == "A"
        and boss_runtime_rules.get("骷髅精灵", {}).get("serviceRace") == 89
        and boss_runtime_rules.get("尸王", {}).get("serviceRace") == 81
        and all(boss_runtime_rules.get(name, {}).get("serviceClass") == "TATMonster" for name in ["骷髅精灵", "尸王"])
        and all(not boss_runtime_rules.get(name, {}).get("specialSkill", {}).get("enabled", True) for name in ["骷髅精灵", "尸王"])
        and all(not boss_runtime_rules.get(name, {}).get("phaseTwo", {}).get("enabled", True) for name in ["骷髅精灵", "尸王"])
        and "boss_service_rules" in game_data_script
        and all(token in enemy_script for token in ["boss_rule", "_attack_hit_delay", "_retarget_timer", "_boss_skill_enabled"])
    )
    mine_runtime_mapping = mine_source.get("runtimeCoordinateMapping", {})
    mine_full_size_connected = (
        mine_runtime_mapping.get("projection") == "isometric_64x32_full_size"
        and len(mine_runtime_mapping.get("maps", {})) == 13
        and mine_runtime_mapping.get("maps", {}).get("1578") == [30, 30]
        and "MINE_SOURCE_SIZES" in region
        and "compact_candidate_to_source" in map_coordinate_script
        and '1578: {"source_map": "Q004", "source_size": Vector2i(30, 30)' in environment
    )

    checks = [
        check("地图与路线", "19张比奇运行地图与往返链", 5, 1.0 if len(runtime_maps) == 19 else len(runtime_maps) / 19,
              f"RegionContent发现{len(runtime_maps)}/19张：{runtime_maps}", "缺图或路由时无法形成完整区域闭环。", "BICH-CONTENT-CLOSE"),
        check("地图与路线", "401—412矿区原MAP映射", 4, 1.0 if len(mine_sources) == 12 else len(mine_sources) / 12,
              f"EnvironmentCatalog发现{len(mine_sources)}/12个D4xx来源代码；6张200×200与6张100×100地图均按原尺寸分块绘制，刷新和门点由C级source_coordinate统一投影。", "正式MapInfo缺失，坐标、数量和刷新周期仍需服务端数据覆盖。", "BICH-DATA-1-IMPORT"),
        check("地图与路线", "比奇省0.map、服务端HomeMap与0100室内图归类", 4, 0.98 if bich_source_connected and full_size_mapping_connected else (0.85 if bich_source_connected else 0.0),
              "客户端0.map以700×700原逻辑尺寸映射到运行地图4；HomeMap=0与(289,618)直接映射为(-10528,3328)；700×700原阻挡掩码已进入镜头局部合并碰撞。0100按15×18小型室内图保留。", "完整服务端MapInfo仍缺失，五个地表门点坐标保持C级。", "BICH-DATA-1-IMPORT"),
        check("地图与路线", "兽人古墓D001—D003原图接入", 3, 0.98 if orc_tomb_connected and full_size_mapping_connected else (0.90 if orc_tomb_connected else 0.35),
              "D001/D002/D003以400×400原逻辑尺寸接入217/218/221；怪物、Boss和门点由source_coordinate统一双向投影，原MAP阻挡以镜头分块物理碰撞接入，并保留原MAP哈希、资源与安全空间。", "服务端MapInfo连接坐标缺失，五个运行门点仍为C级安全闭环候选。", "BICH-DATA-1-IMPORT"),
        check("地图与路线", "天然洞穴D011—D012原图接入", 2, 0.98 if natural_cave_connected and full_size_mapping_connected else (0.90 if natural_cave_connected else 0.25),
              "D011/D012以400×400原逻辑尺寸接入248/249；刷新和门点使用同一source_coordinate等距投影，原MAP阻挡以镜头分块物理碰撞接入，并保留原MAP哈希和专用资源。", "服务端MapInfo连接坐标缺失，运行门点仍为C级候选。", "BICH-DATA-1-IMPORT"),
        check("地图与路线", "尸王殿Q004来源与Boss房", 2, 0.98 if mine_full_size_connected else (0.75 if "Q004" in read(MINE_PROFILE_PATH) else 0.25),
              "Q004按客户端原图30×30尺寸接入，双尸王、入口、原MAP阻挡、边界碰撞和Boss安全区使用统一坐标；原图0灯光保持不伪造。", "正式MapInfo/MonGen缺失，入口与双尸王source_coordinate仍为C级候选。", "BICH-DATA-1-IMPORT"),

        check("怪物与Boss", "比奇怪物刷新阵容", 4, 1.0 if all(name in region for name in ["稻草人", "钉耙猫", "半兽人", "森林雪人", "食人花", "骷髅精灵", "尸王"]) else 0.6,
              "地表、古墓、洞穴、矿区和两类Boss均有运行时刷新定义。", "后续按服务端MonGen核对坐标、数量和刷新间隔。", "BICH-CONTENT-CLOSE"),
        check("怪物与Boss", "属性与掉落数据库", 4, 0.80 if community_baseline.get("summary", {}).get("runtimeDropMonsters", 0) >= 10 else 0.72,
              f"结构库含怪物{len(data.get('monsters', []))}、Boss{len(data.get('bosses', []))}、掉落{len(data.get('drops', []))}条；社区经典基准已匹配{community_baseline.get('summary', {}).get('monsterOverrides', 0)}类比奇怪物，并为{community_baseline.get('summary', {}).get('runtimeDropMonsters', 0)}类代表怪物接入{community_baseline.get('summary', {}).get('runtimeDropSlots', 0)}个保守运行掉落槽。", "代表怪掉落已运行接入；全区域怪物、商店与价格仍待逐区交叉。", "BICH-MILESTONE-1"),
        check("怪物与Boss", "比奇怪物最终造型覆盖", 6, unique_final_art_count / 20,
              f"正式阵容最终资源确认{unique_final_art_count}/20组；亡灵客户端映射{len(undead_mappings)}组、常见怪物映射{len(common_mappings)}组，合计拒绝{len(undead_rejected) + len(common_rejected)}组。鸡、鹿不属于当前项目阵容。", "比奇当前正式刷新阵容已覆盖；后续新增怪物必须同时提供来源和五动作。", "BICH-ART-CLOSE"),
        check("怪物与Boss", "待机/移动/攻击/受击/死亡动作", 3, unique_action_set_count / 20,
              f"五动作齐全的正式资源组为{unique_action_set_count}/20；常见怪物客户端资源{len(common_action_sets)}/{len(common_mappings)}组完整。", "里程碑复验攻击命中帧与小型怪物脚底位置。", "BICH-MILESTONE"),
        check("怪物与Boss", "骷髅精灵与尸王Boss机制", 3, 0.95 if boss_rules_connected and community_baseline.get("summary", {}).get("monsterOverrides", 0) >= 22 else (0.90 if boss_rules_connected else 0.45),
              "已按M2Server Race 89/81映射TATMonster；社区库再次确认骷髅精灵2000/1200ms、尸王2800/1500ms攻击/移动时序，并接入客户端命中帧、持续朝向和脚底选中圈；无来源伪技能保持关闭。", "核心属性冲突继续保留中国1.76资料值与社区值双记录；仍需真机实战手感复验。", "BICH-MILESTONE"),

        check("战士职业", "六项技能数据与运行时入口", 4, 1.0 if len(skill_profiles) == 6 and all(v >= 4 for v in skill_levels.values()) else 0.6,
              f"技能配置{len(skill_profiles)}/6，等级记录：{skill_levels}。", "保持服务端Magic数据优先并记录字段映射。", "WARRIOR-CLOSE"),
        check("战士职业", "普攻按住续刀、850ms间隔、510ms动作锁", 4, 1.0 if attack_contract else 0.0,
              "Player与GameRoot已实现按下/松开、独立攻击间隔及完整收招前禁移。", "真机里程碑复验触控丢失和帧率波动。", "BICH-MILESTONE"),
        check("战士职业", "手机自动选怪与手动换敌", 3, 1.0 if targeting_contract else 0.0,
              "已具备正面权重自动重选、移动后判定、关闭自动后的正面换敌和攻击强制朝向入口。", "用密集怪群与Boss场景做一次里程碑复验。", "BICH-MILESTONE"),
        check("战士职业", "原版伤害、范围与等级公式", 4, 0.85 if warrior_formula_connected else 0.35,
              "已从M2Server源码接入基础命中、DC/幸运、攻杀加值、刺杀第二格、半月侧向、烈火逐级倍率和野蛮成功率；刺杀/半月开关、攻杀周期与烈火蓄力状态机均已接入。", "完整Magic.DB缺失，MP消耗和训练字段仍不能标为服务端精确。", "BICH-DATA-1-IMPORT"),
        check("战士职业", "基本剑术被动命中", 2, 1.0 if passive_sword and "basic_sword_accuracy_bonus" in warrior_math else 0.0,
              "基础准确5、基本剑术每级+3、攻杀每级+1已进入属性结算，普攻和战士技能按目标敏捷执行命中判定。", "完整怪物HIT/SpeedPoint表到位后覆盖当前默认敏捷15。", "BICH-DATA-1"),
        check("战士职业", "五项主动技能专属机制", 5, 0.90 if warrior_state_machine_connected else 0.45,
              "攻杀周期自动触发、刺杀/半月开关与格位、烈火10秒蓄力/20秒过期、野蛮等级差/阻挡/推怪/碰撞伤害已接入。", "完整Magic.DB缺失，半月和野蛮MP/训练字段仍保留候选；手机连续实战留待里程碑。", "BICH-MILESTONE"),
        check("战士职业", "客户端动作、特效与音效", 3, 0.85 if warrior_art_connected else 0.30,
              "已建立客户端逐技能来源表，接入Magic.wil四套八方向效果、现存51/52/57号武器声及HUD技能状态提示。", "客户端130—137号技能WAV在当前资源包缺失，已显式记录且未以无来源音效冒充；野蛮仍使用项目反馈层。", "BICH-MILESTONE"),

        check("装备系统", "175件装备目录与实例化", 3, 1.0 if item_count == 175 else min(1.0, item_count / 175),
              f"结构库装备{item_count}件，背包使用独立耐久实例。", "逐项以服务端StdItems覆盖网页候选数据。", "EQUIPMENT-DATA-1"),
        check("装备系统", "穿戴要求与属性结算", 3, 0.90 if equipment_rules_connected else 0.65,
              "已按服务端源码接入Need 0—3、职业重量公式、武器/穿戴重量、衣服性别与双槽属性结算；锁定社区1.76 StdItems逐件校准172件。", "落魄神兵、辟邪手镯、黑铁手套仍无同名数据库记录；社区发行版不冒充2003官服原库。", "BICH-DATA-1"),
        check("装备系统", "1.76装备槽结构", 2, 1.0 if len(equipment_slots) == 8 else 0.25,
              f"当前槽位：{equipment_slots}；手镯和戒指均已拆分左右槽。", "后续用客户端装备面板资源替换当前文字选择器。", "EQUIPMENT-ART-1"),
        check("装备系统", "耐久损耗与修理", 3, 0.90 if equipment_durability_connected else 0.0,
              "耐久归零保留原槽实例但属性失效；唯一维修按服务端缺损比例公式恢复原最大耐久，不提供特殊修理。", "StdItems.Price缺失，维修基准物价仍是显式项目候选；武器/衣服损耗频率留待里程碑手感复验。", "BICH-MILESTONE"),
        check("装备系统", "幸运、诅咒与祝福油", 3, 0.95 if equipment_luck_connected else 0.15,
              "已按服务端接入1/20失败、1/3/7幸运阶段、诅咒至10、实例存储及幸运/诅咒攻击上下限分布；祝福油不再错误回血。", "人物PK幸运与完整StdItems武器基础幸运/诅咒值尚未接入；当前任务只完成武器实例与祝福油主链。", "BICH-MILESTONE"),
        check("装备系统", "特殊装备效果", 2, 0.95 if equipment_special_connected else 0.0,
              "八项戒指效果、手机主动按钮、魔血MP转HP、虹魔近战吸血和三件套奖励均已接入；装备配置支持覆盖、新增及暴击/速度/技能等级扩展。记忆组队传送与祈祷宠物叛变属于已确认的单机边界，不再列为实现缺陷。", "StdItems缺失使魔血25/件、虹魔4/3/2仍是B级候选。", "BICH-DATA-1-IMPORT"),
        check("装备系统", "客户端装备图标与穿戴外观", 2, 0.90 if equipment_art_connected and warrior_wear_connected else (0.72 if equipment_art_connected else 0.15),
              f"175件装备已接入三类客户端物品图；男女三职业{len(warrior_wear_mappings)}件武器/衣服接入Weapon/Hum五动作八方向动态图层，并保持零耐久外观。", f"仍有{len(warrior_wear.get('rejectedMappings', []))}件因锁定StdItems缺名而拒绝接入，不猜测替换。", "EQUIPMENT-DATA-1"),
        check("装备系统", "装备与背包存档", 2, 1.0 if '"equipment": equipment' in state and "migrate_equipment_slots" in state and "LEGACY_SAVE_PATH" in state else 0.0,
              "装备实例、背包、耐久和v02到v03双槽迁移均已进入存读档路径。", "里程碑真机复验应用升级后旧存档自动迁移。", "BICH-MILESTONE"),

        check("任务经济存档", "比奇NPC商店与修理", 2, 0.80,
              "已有商店、药店和修理交互闭环。", "用服务端Merchant/Market_Def复核货单、价格和NPC坐标。", "BICH-DATA-1"),
        check("任务经济存档", "比奇任务链", 3, 0.95 if bich_quest_connected else 0.35,
              f"已建立{len(bich_quest_chain.get('quests', []))}段新手—野外—古墓—骷髅精灵—矿区—尸王连续主线，支持复合击杀、前置、原子奖励、防重复、旧存档迁移和移动追踪。", "第一段为经典任务改编B；后五段是明确标记的单机衔接C，不冒充官服QuestDiary原任务。实际QuestDiary到位后逐步覆盖。", "BICH-DATA-1"),
        check("任务经济存档", "掉落与经济的服务端一致性", 3, 0.35 if community_baseline.get("summary", {}).get("runtimeDropMonsters", 0) >= 10 else 0.25,
              "掉落可运行，但完整MonItems/Merchant/价格数据包尚未导入正式运行库。", "完成服务端数据导入、差异审计和经济回归。", "BICH-DATA-1"),
        check("任务经济存档", "死亡、回城、保存与继续", 2, 1.0,
              "已有死亡重生、金币损失、多角色原子存档、旧档迁移、系统菜单与强杀后重登回城。", "荣耀90已完成里程碑启动验证。", "DONE"),

        check("手机验收", "触控移动、攻击与选怪", 2, 1.0 if attack_contract and targeting_contract else 0.5,
              "触控摇杆、按住攻击、自动/手动选怪已接入。", "只在里程碑做适量回归。", "BICH-MILESTONE"),
        check("手机验收", "荣耀90阶段性实机验证", 1, 1.0,
              "前序阶段已完成荣耀90连接、安装与碰撞/悬空/战斗反馈修正。", "保留里程碑复验即可。", "BICH-MILESTONE"),
        check("手机验收", "比奇闭环里程碑APK", 2, 1.0 if MILESTONE_APK_PATH.exists() else 0.0,
              "版本25 / 1.14-bich-m1已完成签名、清单、荣耀90覆盖安装和启动页截图验证。", "后续新增内容继续沿用阶段构建规则。", "DONE"),
    ]

    assert abs(sum(item.weight for item in checks) - 100.0) < 0.001
    category_scores: dict[str, dict[str, float]] = {}
    for item in checks:
        bucket = category_scores.setdefault(item.category, {"score": 0.0, "weight": 0.0})
        bucket["score"] += item.score
        bucket["weight"] += item.weight

    total = round(sum(item.score for item in checks), 1)
    blockers = [item for item in checks if item.credit < 0.5]
    blockers.sort(key=lambda item: (item.credit, -item.weight))
    next_tasks: list[str] = []
    for item in blockers:
        if item.next_task not in next_tasks:
            next_tasks.append(item.next_task)

    payload = {
        "auditId": "BICH-CLOSE-1",
        "generatedAt": date.today().isoformat(),
        "sourcePolicy": [
            "服务端优先提供规则与数值",
            "客户端优先提供MAP/WIL/WIX、动作、外观、特效和音效",
            "两端冲突保留双值、采用值、路径、版本与可信度",
            "两端均缺失才允许项目推导，且不得冒充官服基准",
        ],
        "overallPlanProgress": 82.4,
        "bichPlayableCompletion": total,
        "observed": {
            "runtimeBichMaps": runtime_maps,
            "catalogBichMaps": catalog_maps,
            "mineSourceMaps": mine_sources,
            "warriorSkillLevels": skill_levels,
            "finalMonsterArt": final_art,
            "finalFiveActionSets": final_action_sets,
            "itemCount": item_count,
            "equipmentSlots": equipment_slots,
        },
        "categoryScores": {
            name: {"score": round(values["score"], 2), "weight": values["weight"]}
            for name, values in category_scores.items()
        },
        "checks": [{**asdict(item), "score": round(item.score, 2)} for item in checks],
        "criticalBlockers": [asdict(item) for item in blockers[:10]],
        "recommendedOrder": next_tasks,
    }
    OUTPUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# BICH-CLOSE-1：比奇垂直切片缺口审计",
        "",
        f"> 生成日期：{payload['generatedAt']}  ",
        f"> 总体结构进度：{payload['overallPlanProgress']:.1f}%（本审计不虚增总进度）  ",
        f"> **比奇可玩版本完成度：{total:.1f}%**",
        "",
        "## 审计口径",
        "",
        "- 服务端数据优先用于规则与数值；客户端数据优先用于地图、动作、外观、特效和音效。",
        "- 两端冲突必须保留差异与采用依据；两端均缺失才允许项目推导，并明确标成临时值。",
        "- 能运行的占位内容只计部分完成；来源、正式资源、运行接入和回归验证全部达标才计100%。",
        "",
        "## 分类结果",
        "",
        "| 分类 | 得分 | 权重 | 完成率 |",
        "|---|---:|---:|---:|",
    ]
    for name, values in category_scores.items():
        rate = values["score"] / values["weight"] * 100
        lines.append(f"| {name} | {values['score']:.2f} | {values['weight']:.0f} | {rate:.1f}% |")
    lines += ["", "## 逐项清单", "", "| 状态 | 项目 | 得分/权重 | 证据与缺口 | 后续任务 |", "|---|---|---:|---|---|"]
    for item in checks:
        evidence = f"{item.evidence} 缺口：{item.gap}".replace("|", "／")
        lines.append(f"| {item.status} | {item.name} | {item.score:.2f}/{item.weight:.0f} | {evidence} | `{item.next_task}` |")
    lines += ["", "## 最高优先级缺口", ""]
    for index, item in enumerate(blockers[:10], 1):
        lines.append(f"{index}. **{item.name}**（`{item.next_task}`）：{item.gap}")
    lines += [
        "",
        "## 推荐施工顺序",
        "",
        "1. `BICH-COMMUNITY-DATA-3`：对经典掉落候选执行概率校准与运行接入。",
        "2. `BICH-MILESTONE`：掉落经济收口后进行一次适量真机验收与里程碑构建。",
        "3. `BICH-DATA-1-IMPORT`：更强的同版本Monster/MonItems/Merchant/MapInfo数据包到位后执行覆盖审计。",
        "",
        "本文件由 `tools/audit_bich_vertical_slice.py` 生成；修改实现后应重新运行，避免手工修改审计分数。",
        "",
    ]
    OUTPUT_MD.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"bichPlayableCompletion": total, "json": str(OUTPUT_JSON), "report": str(OUTPUT_MD)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
