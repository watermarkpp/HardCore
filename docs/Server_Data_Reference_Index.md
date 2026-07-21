# 服务端数据参考索引

本文件用于记录当前项目可用的 MIR2 服务端数据来源，后续数值、地图、刷怪、Boss、掉落和任务施工优先参考这里，而不是凭感觉改。

## 当前本地可用来源

| 来源 | 路径 | 用途 | 可信度 |
|---|---|---|---|
| 服务端运行配置 | `research/MIR2/GameOfMir/MirServer/Mir200/!Setup.txt` | 出生点、经验表、攻击/移动间隔、刷怪比例、职业成长、技能/怪物别名 | 高 |
| 服务端源码 | `research/MIR2/GameOfMir/M2Server/*.pas` | 怪物生成逻辑、战斗规则、怪物字段含义、技能运行逻辑 | 高 |
| 客户端动作源码 | `research/MIR2/GameOfMir/MirClient/Actor.pas` | 人物/怪物动作帧号、帧数、方向步长、播放时间 | 高 |
| 客户端资源库 | `research/mir2_client_raw/Data/*.wil`、`research/mir2_client_raw/Map/*.map` | 人物、怪物、技能、NPC、地图资源 | 高 |
| Crystal社区数据库 | `research/mir2_database_candidates/suprcode_crystal_database/` | 四套社区怪物、地图、刷新与掉落数据交叉验证 | B；经典白名单选择性采用 |
| Crystal中文导出 | `research/mir2_database_candidates/angelk727_full/` | 六张结构化导出表与1261份掉落文件 | B/C；含后期与私服改值，禁止整库覆盖 |
| 当前结构化数据 | `work/legend176_game/assets/data/legend176_data.json` | 项目已接入的地图、怪物、Boss、装备、技能、掉落、任务 | 中，高可信字段需逐步回填来源 |

## 重要服务端参数摘录

| 参数 | 当前值 | 说明 | 当前处理 |
|---|---:|---|---|
| `HomeMap/HomeX/HomeY` | `0 / 289 / 618` | 默认出生点 | 后续出生/回城应对齐 |
| `RedHomeMap/RedHomeX/RedHomeY` | `3 / 845 / 674` | 红名回城点 | 后续 PK/死亡系统参考 |
| `MonGenRate` | `20` | 全局刷怪数量比例 | 区域刷怪密度参考 |
| `HitIntervalTime` | `600ms` | 服务端普攻间隔参考值 | 用户已指定手机版普攻为 `850ms`，暂不覆盖 |
| `MagicHitIntervalTime` | `600ms` | 魔法攻击间隔参考值 | 技能冷却基准参考 |
| `WalkIntervalTime` | `400ms` | 行走间隔 | 移动手感参考 |
| `RunIntervalTime` | `400ms` | 跑动间隔 | 移动手感参考 |
| `ActionIntervalTime` | `320ms` | 动作间隔 | 防连点/动作锁参考 |
| `MagicAttackRage` | `8` | 魔法攻击视野/距离参数 | 法师技能范围参考 |
| `LevelValueOfWarrHP/HPRate` | `4 / 4.5` | 战士 HP 成长相关 | 后续职业成长表校准 |
| `LevelValueOfWizardHP/HPRate` | `15 / 1.8` | 法师 HP 成长相关 | 后续职业成长表校准 |
| `LevelValueOfTaosHP/HPRate` | `6 / 2.5` | 道士 HP 成长相关 | 后续职业成长表校准 |

## 原始传统数据包状态

当前本地没有找到完整的传统服务端数据目录：

- `Envir/MapInfo.txt`
- `Envir/MonGen.txt`
- `Envir/MonItems/*.txt`
- `Market_Def/*.txt`
- `Monster.DB`
- `StdItems.DB`
- `Magic.DB`

现已取得可追溯社区数据库，但仍不是2003官服传统DBF原件。因此数据优先级调整为：

1. 服务端 `!Setup.txt` 与源码规则；
2. 客户端资源与原MAP文件；
3. Crystal社区数据库与1.76资料站交叉一致的经典字段；
4. 当前 `legend176_data.json` 的结构化候选；
5. 其他网络或人工整理数据，必须标记来源和可信度。

社区库包含刺客、坐骑、英雄、觉醒、钓鱼和私服化爆率；只能按经典地图、怪物和物品白名单选择性导入。采用细则见 `BICH-COMMUNITY-DATA-1_Community_Database_Research_and_Adoption_Report.md`。

## M7-2 当前执行约束

- 人物动作帧号以 `MirClient/Actor.pas` 的 `HA` 动作表为准。
- 战斗间隔以用户明确指定的手机手感为准；服务端 `HitIntervalTime=600ms` 作为参考，不强制覆盖 `850ms`。
- 后续地图/怪物/Boss/掉落/任务施工，若没有完整 `Envir/DB` 数据，必须在记录中标明“服务端完整数据缺失，使用项目结构化数据/客户端资源补齐”。
