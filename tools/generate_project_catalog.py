#!/usr/bin/env python3
"""Generate the project structure/file-purpose catalog beside the master plan."""

from __future__ import annotations

from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/项目总目录.md"

SCRIPT_PURPOSES = {
    "art_spec.gd": "统一角色、怪物、图集帧尺寸、方向与脚底锚点规范",
    "enemy.gd": "怪物属性、AI、朝向、攻击、受击、死亡、碰撞与Boss状态",
    "environment_catalog.gd": "各区域地形主题、客户端地图来源与环境资源注册表",
    "environment_validator.gd": "环境资源路径、图块、碰撞和灯光配置校验",
    "equipment_rules.gd": "装备槽位、穿戴需求、耐久、维修、特殊效果和套装通用规则",
    "game_data.gd": "载入结构化数据、装备美术/穿戴覆盖、任务链及运行索引",
    "game_root.gd": "主场景编排、地图切换、战斗、选怪、掉落、NPC与移动端输入",
    "ground_effect.gd": "地面范围效果和短时视觉反馈",
    "hud.gd": "移动端HUD、摇杆/攻击/技能/任务追踪及各面板入口",
    "inventory_panel.gd": "背包、八槽装备、物品图标、属性详情、使用与穿卸",
    "loot_pickup.gd": "地图掉落外观、拾取距离和入包事件",
    "map_panel.gd": "地图列表、后期内容开关与快速旅行界面",
    "map_coordinate_mapper.gd": "原MAP逻辑坐标、64×32等距世界坐标、边界与双向转换",
    "mobile_layout.gd": "安全区、荣耀90分辨率和移动端控件布局规则",
    "monster_visual.gd": "怪物五动作图集、方向、阴影、选中圈与脚底锚点",
    "npc_actor.gd": "NPC显示、交互类型及商店/训练/任务入口",
    "player.gd": "人物移动、850ms攻击、技能状态、动作锁和战斗请求",
    "player_state.gd": "角色等级、背包、装备、技能、任务、奖励、多角色档案与原子自动存档",
    "player_visual.gd": "战士五动作、Weapon/Hum动态穿戴、技能特效与音效",
    "profession_panel.gd": "职业选择与切换界面",
    "profession_rules.gd": "三职业基础成长和技能战斗配置",
    "quest_panel.gd": "比奇老兵动态任务面板、目标、奖励和来源显示",
    "region_content.gd": "地图门点、怪物/Boss刷新、NPC与候选掉落运行定义",
    "route_beacon.gd": "地图出口方向提示",
    "shop_panel.gd": "商店购买、维修和价格界面",
    "skill_panel.gd": "技能学习、快捷栏和训练界面",
    "skill_projectile.gd": "远程技能弹道、命中与生命周期",
    "summon_actor.gd": "召唤物基础行为",
    "targeting_system.gd": "移动端自动选怪正面权重与手动换敌排序",
    "technical_art_sample.gd": "技术美术样例场景驱动",
    "virtual_joystick.gd": "触屏虚拟摇杆输入",
    "warrior_combat_math.gd": "战士命中、幸运和六项技能服务端公式",
    "world_background.gd": "世界背景、地形图块、碰撞、门点和区域视觉装配",
    "zone_portal.gd": "地图门点触发与交互提示",
    "content_layer_registry.gd": "五层清单、扩展开关及Merged Game Database合并入口",
    "runtime_service_facade.gd": "存档、安全退出、扩展开关与运行时内容状态门面",
}

DATA_PURPOSES = {
    "legend176_data.json": "地图、怪物、Boss、175件装备、技能、掉落和原始任务总数据库",
    "bich_quest_chain.json": "六段比奇单机主线、目标、前置、奖励、来源与可信度",
    "bich_closure_audit.json": "比奇垂直切片机器可读完成度审计",
    "bich_community_baseline.json": "社区经典怪物时序、字段差异、D001—D003刷新画像及10类怪物保守运行掉落",
    "bich_source_profiles.json": "比奇客户端地图来源、尺寸、门点与运行映射",
    "bich_undead_client_art_sources.json": "骷髅、僵尸、骷髅精灵和尸王客户端五动作源帧、锚点与运行映射",
    "bich_common_client_art_sources.json": "多钩猫、洞蛆、山洞蝙蝠和蝎子客户端五动作源帧与运行映射",
    "boss_service_rules.json": "骷髅精灵与尸王服务端AI类别、数值候选、攻击时序及禁用伪技能规则",
    "bich_public_database_crosscheck.json": "公开后期数据库的比奇同名怪物/刷新交叉验证缓存，明确拒绝覆盖2003基准",
    "service_reference.json": "服务端Setup、经验表、字段语义和来源索引",
    "service_item_catalog.json": "主服务端1349条物品、非装备运行目录及Items/StateItem/DnItems来源映射",
    "server_import_candidate.json": "待导入服务端数据候选",
    "server_import_report.json": "服务端导入覆盖与缺失项报告",
    "equipment_customization.json": "用户最高优先级装备新增、覆盖、词条、效果与美术入口",
    "equipment_client_art_sources.json": "175件Items/StateItem/DnItems客户端图像映射",
    "equipment_web_looks_candidates.json": "逐件Looks网页候选缓存",
    "equipment_service_rules.json": "StdItems字段、Need、重量和属性结算来源",
    "equipment_durability_rules.json": "零耐久与唯一维修规则",
    "equipment_luck_rules.json": "幸运、诅咒、祝福油和攻击分布规则",
    "equipment_special_rules.json": "特殊戒指、套装及单机边界",
    "warrior_service_rules.json": "战士技能服务端公式与候选字段",
    "warrior_client_art_sources.json": "战士技能特效和音效客户端来源",
    "warrior_wear_sources.json": "男性战士Weapon/Hum Shape、五动作图集和拒绝映射",
    "mine_source_profiles.json": "比奇矿区客户端地图来源",
    "natural_cave_source_profiles.json": "天然洞穴D011/D012哈希、结构、阻挡、资源与运行投影证据",
    "orc_tomb_source_profiles.json": "兽人古墓D001/D002/D003哈希、结构、阻挡、资源与运行投影证据",
    "snake_valley_source_profiles.json": "毒蛇山谷来源",
    "wooma_region_source_profiles.json": "沃玛区域来源",
    "wooma_temple_source_profiles.json": "沃玛寺庙来源",
    "vanilla_core.json": "原版基准层数据集清单与不可变策略",
    "expansion_layer.json": "扩展包、开关与合并策略清单",
    "rule_systems.json": "规则模块和通用Schema清单",
    "presentation_layer.json": "表现皮肤包与逻辑资源映射清单",
    "runtime_services.json": "运行时服务职责与合并数据库策略",
    "policy_overrides.json": "保留原值、调整值、理由和范围的基准层运行政策覆盖",
    "modifier_schema.json": "通用基础、战斗、技能和触发型词条Schema",
    "set_bonus_schema.json": "独立套装分段奖励Schema",
    "merged_game_database.json": "Vanilla、Expansion、User Override合并快照",
}

TOOL_PURPOSES = {
    "run_godot_tests.ps1": "隔离进程、短超时、PASS标记驱动的轻量测试执行器",
    "verify_android_build.ps1": "Android导出环境和APK结构验证",
    "android_stress_monitor.ps1": "真机阶段资源与进程监控",
    "audit_bich_vertical_slice.py": "重新计算比奇可玩完成度与最高优先级缺口",
    "audit_bich_data_coverage.py": "审计比奇正式数据缺口、后期交叉验证差异与版本隔离",
    "audit_service_data.py": "审计服务端数据库文件覆盖",
    "import_mir2_server_data.py": "将服务端Monster/StdItems/Magic/MonItems转换为候选结构数据",
    "build_bich_public_database_crosscheck.py": "缓存公开后期数据库的比奇同名条目并执行基准隔离",
    "build_bich_community_baseline.py": "从固定社区数据库生成比奇运行覆盖、掉落拒绝清单与保守掉落表",
    "build_equipment_client_art.py": "从Items/StateItem/DnItems提取装备三类图像",
    "build_complete_item_system.py": "解析主服务端物品表并按主端、辅1、分类补图顺序构建背包与地面外观",
    "fetch_equipment_looks_candidates.py": "一次性缓存逐件Looks候选",
    "build_warrior_client_effects.py": "提取战士四技能Magic图集和可用WAV",
    "build_warrior_wear_assets.py": "按Shape×2+性别提取男性战士Weapon/Hum五动作",
    "extract_warrior_service_rules.py": "从服务端源码生成战士规则表",
    "extract_equipment_service_rules.py": "生成装备服务端字段规则表",
    "extract_equipment_durability_rules.py": "生成耐久与维修规则表",
    "extract_equipment_luck_rules.py": "生成幸运/祝福油规则表",
    "extract_equipment_special_rules.py": "生成特殊装备规则表",
    "build_bich_environment_assets.py": "构建比奇地形和道具资源",
    "build_bich_monster_atlases.py": "构建比奇怪物方向动作图集",
    "build_bich_client_undead.py": "从Mon客户端库确定性提取11类亡灵怪物五动作八方向图集",
    "build_bich_client_common_monsters.py": "从Mon客户端库提取4类比奇常见怪物五动作八方向图集",
    "build_orc_tomb_environment_assets.py": "兼容旧入口并转发到客户端原MAP构建器",
    "build_orc_tomb_client_assets.py": "解析D001/D002/D003并构建兽人古墓客户端资源、掩码和来源清单",
    "build_mine_environment_assets.py": "构建矿区环境资源",
    "build_natural_cave_assets.py": "解析D011/D012并构建天然洞穴专用资源、阻挡掩码和来源清单",
    "build_snake_valley_assets.py": "构建毒蛇山谷资源",
    "build_wooma_region_assets.py": "构建沃玛森林区域资源",
    "build_wooma_temple_assets.py": "构建沃玛寺庙资源",
    "build_directional_anchor_atlas.py": "按方向与脚底锚点规范重组动作图集",
    "generate_project_catalog.py": "生成本项目总目录",
    "build_five_layer_database.py": "拆分只读Vanilla表并生成运行时合并快照",
    "audit_five_layer_architecture.py": "审计五层清单、不可变策略、扩展开关与合并顺序",
    "build_world_helmet_asset.py": "按确切图标、已验收方向参考和客户端头部锚点生成黑铁头五动作图集",
    "prepare_black_iron_chatgpt_inputs.py": "准备黑铁头造型参考和五套人物动作输入图",
    "build_black_iron_helmet_acceptance_sheet.py": "合成黑铁头八方向与五动作Godot运行时验收图",
    "verify_black_iron_helmet_asset.py": "校验黑铁头184逻辑帧、八方向差异、逐帧运动和人物头部重合",
    "verify_black_iron_runtime_import.py": "校验Godot CTEX缓存新鲜度及运行截图是否实际包含当前黑铁头像素",
    "verify_black_iron_runtime_directions.py": "逐方向校验全新命名的Godot截图确实包含当前黑铁头图集像素",
    "prepare_black_iron_direction_reference.py": "从用户确认图中提取完整八方向黑铁头唯一母版并忽略错误标签/重复格",
    "analyze_client_helmet_parameters.py": "统计客户端六套真实头盔的方向宽高、动作尺寸和死亡姿态基准",
    "scan_complete_client_headwear.py": "完整扫描客户端全部资源容器并建立逐帧头部候选知识库",
    "source_priority_guard.py": "强制主资料优先，并只对证据完整的逐级降级请求签发授权",
    "verify_source_priority_policy.py": "验证客户端/服务端主辅分级、权重、来源存在性与越级保护",
    "build_brand_assets.py": "从用户确认的品牌母版确定性生成游戏图标和启动画面并登记哈希",
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def test_purpose(name: str) -> str:
    labels = [
        ("brand_intro", "游戏品牌图标、启动画面与开场动画"),
        ("quest", "任务链、奖励、迁移与追踪"), ("equipment", "装备规则与扩展"),
        ("warrior", "战士技能、时序与视觉"), ("bich", "比奇地图与垂直切片"),
        ("monster", "怪物动作、碰撞或数据"), ("boss", "Boss行为与掉落"),
        ("android", "Android/移动端布局"), ("mobile", "移动端操作与选怪"),
        ("service", "服务端来源与运行校准"), ("environment", "环境资源与碰撞"),
        ("progression", "等级与成长"), ("save", "存档与迁移"),
        ("item", "物品目录与掉落"), ("smoke", "主场景冒烟"),
    ]
    return next((purpose for token, purpose in labels if token in name.lower()), "专项确定性回归")


def table_rows(files: list[Path], purposes: dict[str, str]) -> list[str]:
    return [f"| `{path.name}` | {purposes.get(path.name, '项目支持文件')} | `{rel(path)}` |" for path in files]


def main() -> None:
    scripts = sorted((ROOT / "scripts").rglob("*.gd"))
    data_files = sorted((ROOT / "assets/data").rglob("*.json"))
    tools = sorted([*list((ROOT / "tools").glob("*.py")), *list((ROOT / "tools").glob("*.ps1"))], key=lambda p: p.name)
    docs = sorted((ROOT / "docs").glob("*.md"), key=lambda p: p.name)
    test_scripts = sorted((ROOT / "tests").glob("*_test.gd"), key=lambda p: p.name)
    art_files = [p for p in (ROOT / "assets/art").rglob("*") if p.is_file() and not p.name.endswith(".import")]
    art_groups = Counter(rel(path).split("/")[2] if len(rel(path).split("/")) > 2 else "其他" for path in art_files)

    lines = [
        "# 项目总目录",
        "",
        "本文件与[总规划进度续表](总规划_进度续表.md)放在同一目录，用于说明项目结构、核心文件用途和路径。结构变化后运行 `python tools/generate_project_catalog.py` 刷新。",
        "",
        "## 项目根目录",
        "",
        "```text",
        "legend176_game/",
        "├─ assets/                 运行数据、美术与音频",
        "│  ├─ data/                五层清单、Vanilla只读表、扩展包、规则与合并数据库",
        "│  │  ├─ vanilla_176/      原版基准层独立只读表",
        "│  │  ├─ expansions/       可开关私人扩展包",
        "│  │  ├─ layers/           五层正式清单",
        "│  │  ├─ rules/            通用词条与套装Schema",
        "│  │  └─ runtime/          Merged Game Database快照",
        "│  ├─ presentation/        可替换美术皮肤包清单",
        "│  ├─ art/                 地图、人物、怪物、装备和技术样例",
        "│  └─ audio/               客户端可核实音效",
        "├─ scripts/                Godot运行逻辑与UI",
        "│  └─ layers/runtime/      内容合并器与运行时服务门面",
        "├─ scenes/                 主场景与技术样例场景",
        "├─ tests/                  确定性测试场景和脚本",
        "├─ tools/                  数据提取、资源构建、审计和测试工具",
        "├─ docs/                   总纲、总目录、规范与验收报告",
        "├─ dev_art_sources/        被Godot忽略的美术工作源文件",
        "├─ import_server_data/      用户放置正式服务端数据的导入入口",
        "├─ project.godot           Godot项目与Autoload配置",
        "└─ export_presets.cfg      Android等平台导出配置",
        "```",
        "",
        "## 根文件与场景",
        "",
        "| 文件 | 用途 | 路径 |",
        "|---|---|---|",
        "| `project.godot` | Godot项目、ContentLayers/GameData/PlayerState/RuntimeServices自动加载和窗口设置 | `project.godot` |",
        "| `export_presets.cfg` | Android导出预设 | `export_presets.cfg` |",
        "| `README.md` | 项目启动与基础说明 | `README.md` |",
        "| `总规划_任务结构图.md` | 初始任务结构图入口 | `总规划_任务结构图.md` |",
        "| `main.tscn` | 游戏主场景 | `scenes/main.tscn` |",
        "| `technical_art_sample.tscn` | 技术美术规范样例 | `scenes/technical_art_sample.tscn` |",
        "",
        "## 运行脚本",
        "",
        "| 文件 | 用途 | 路径 |",
        "|---|---|---|",
        *table_rows(scripts, SCRIPT_PURPOSES),
        "",
        "## 结构化数据",
        "",
        "| 文件 | 用途 | 路径 |",
        "|---|---|---|",
        *table_rows(data_files, DATA_PURPOSES),
        "",
        "## 资源构建与验证工具",
        "",
        "| 文件 | 用途 | 路径 |",
        "|---|---|---|",
        *table_rows(tools, TOOL_PURPOSES),
        "",
        "## 美术与音频目录",
        "",
        "| 目录 | 当前运行资源数（不含.import） | 用途 |",
        "|---|---:|---|",
    ]
    art_purposes = {"characters": "人物五动作、Weapon/Hum穿戴和技能特效", "items": "装备背包/装备栏/地面外观", "maps": "各区域地形、对象、灯光与来源遮罩", "monsters": "怪物与Boss五动作图集", "samples": "技术美术示例"}
    for group, count in sorted(art_groups.items()):
        lines.append(f"| `assets/art/{group}/` | {count} | {art_purposes.get(group, '运行美术资源')} |")
    audio_count = len([p for p in (ROOT / "assets/audio").rglob("*") if p.is_file() and not p.name.endswith(".import")]) if (ROOT / "assets/audio").exists() else 0
    lines.append(f"| `assets/audio/` | {audio_count} | 客户端可核实的战士挥击等音效 |")

    lines += [
        "",
        "## 研究输出目录",
        "",
        "| 目录 | 用途 |",
        "|---|---|",
        "| `outputs/chatgpt_inputs/black_iron_helmet/` | 黑铁头唯一造型参考、五套人物动作和生成参考输入包 |",
        "| `outputs/visual_acceptance/player_states/` | Godot真实运行时人物方向与动作截图 |",
        "| `outputs/validation/` | 美术图集、来源和运行结构机器校验报告 |",
        "| `outputs/resource_catalog/complete_client_frame_catalog/` | 完整客户端逐帧SQLite知识库、清单和候选图表 |",
        "",
        "## 测试目录",
        "",
        f"当前共有 `{len(test_scripts)}` 个测试脚本；每个脚本对应同名 `.tscn` 入口，由 `tools/run_godot_tests.ps1` 隔离执行。",
        "",
        "| 测试 | 用途 | 脚本路径 | 场景路径 |",
        "|---|---|---|---|",
    ]
    for path in test_scripts:
        base = path.stem
        scene = ROOT / "tests" / f"{base}.tscn"
        lines.append(f"| `{base}` | {test_purpose(base)} | `{rel(path)}` | `{rel(scene)}` |")

    lines += [
        "",
        "## 项目文档",
        "",
        "| 文件 | 用途 | 路径 |",
        "|---|---|---|",
    ]
    doc_purposes = {
        "总规划_进度续表.md": "当前唯一施工总纲、完成记录、进度和下一任务",
        "项目总目录.md": "本目录",
        "BICH-CLOSE-1_比奇垂直切片缺口审计.md": "机器生成的比奇完成度和优先级缺口",
        "测试执行规范.md": "后续必须贯彻的轻量测试链",
        "装备自定义指南.md": "装备数值、词条、效果和美术修改说明",
        "Codex崩溃自检记录.md": "桌面崩溃与资源压力记录",
    }
    for path in docs:
        lines.append(f"| `{path.name}` | {doc_purposes.get(path.name, '阶段规范、数据报告或验收记录')} | `{rel(path)}` |")

    lines += [
        "",
        "## 外部研究资料（不打入游戏包）",
        "",
        "| 路径 | 用途 |",
        "|---|---|",
        "| `dev_art_sources/reference/original_gameofmir/` | 已迁入当前工程的原始服务端/客户端源码研究副本 |",
        "| `dev_art_sources/reference/mir2_client_raw/` | 已迁入当前工程的完整经典客户端Data、Map与Wav |",
        "| `dev_art_sources/reference/mir2_database_candidates/` | 已迁入当前工程的非官服数据库候选，必须按B/C级隔离使用 |",
        "| `dev_art_sources/external/mir2opensource_full/` | 已完整解包并逐帧建库的2013配套客户端 |",
        "| `dev_art_sources/reference/generated/black_iron_helmet/` | 用户确认的黑铁头方向概念图与透明后向三视图工作源 |",
        "| `tools/vendor/extract_wil.py` | 当前工程内通用WIL/WIX透明PNG提取器 |",
        "",
        "## 维护规则",
        "",
        "- `.godot/`、`.import`、构建日志和研究解包临时目录不是业务源文件，不手工列入核心目录。",
        "- 自动生成的来源表和图集应修改对应 `tools/build_*.py` 后重建，避免只改生成结果。",
        "- 服务端正式数据放入 `import_server_data/`，运行导入与差异审计后再覆盖候选值。",
        "- 每次任务完成后更新总纲、运行缺口审计，并重新生成本目录。",
        "",
        f"生成统计：脚本{len(scripts)}、数据文件{len(data_files)}、工具{len(tools)}、测试{len(test_scripts)}、运行美术{len(art_files)}。",
    ]
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"PROJECT_CATALOG={OUTPUT}")


if __name__ == "__main__":
    main()
