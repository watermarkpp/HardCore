# BICH-MONSTER-ANIMATION-1 比奇怪物客户端动作补全报告

日期：2026-07-15  
状态：完成；未构建 APK。

## 完成内容

- 从当前工程内完整经典客户端 `dev_art_sources/reference/mir2_client_raw/Data` 读取 WIL/WIX，不依赖旧工程或外部临时路径。
- 依据客户端 `Actor.pas` 的 `TMonsterAction` 表与 `GetOffset` 公式，建立 11 种比奇常见怪物的待机、行走、攻击、受击、死亡五动作八方向映射：森林雪人、食人花、洞蛆、多钩猫、钉耙猫、稻草人、半兽人、山洞蝙蝠、蝎子、毒蜘蛛、蛤蟆。
- 其中此前使用静态图伪动画的森林雪人、食人花、钉耙猫、稻草人、半兽人，已经全部替换为经典客户端原始动作帧。
- 纠正动画目录先按 `baseName` 合并的错误：现在精确怪物名优先，僵尸1至僵尸5等独立映射不再被错误判为缺失。

## 可追溯映射

| 怪物 | 客户端容器 | appearance | position | 动作表/步长 |
|---|---|---:|---:|---|
| 森林雪人 | `Mon1.wil` | 1 | 1 | MA12 / 280 |
| 食人花 | `Mon2.wil` | 10 | 0 | MA13 / 230 |
| 钉耙猫 | `Mon3.wil` | 26 | 6 | MA14 / 360 |
| 稻草人 | `Mon3.wil` | 27 | 7 | MA14 / 360 |
| 半兽人 | `Mon4.wil` | 30 | 0 | MA19 / 360 |

完整 11 种映射见 `assets/data/bich_common_client_art_sources.json`；生成器为 `tools/build_bich_client_common_monsters.py`。

## 产物与验收

- 生成 11 组映射、55 张动作图集，位置为 `assets/art/monsters/client_bich_common/`。
- 动画目录统计由 `formal=23, provisional=9, missing=182` 更新为 `formal=42, provisional=0, missing=172`。
- 将源 WIL 再次独立解码并与每个图集逻辑帧逐像素比较：2,384 帧检查，0 失败。
- Godot 专项回归通过：`bich_common_client_art_test`、`bich_monster_visual_test`、`bich_undead_client_art_test`、`bich_runtime_fidelity_test`。
- 最小视觉验收图：`outputs/visual_acceptance/bich_monster_original_client_actions_20260715.png`。

## 长期施工规则

- 文件名、数据库分类、怪物职业分类只作为检索线索，不作为资源身份依据。
- 正式怪物动画必须同时满足：WIL/WIX 原始像素可追溯、客户端动作表和 `GetOffset` 公式可追溯、Godot 实际加载与动作方向测试通过。
- 仅有五张文件、静态转向图或生成补帧，不得记为“动作齐全”；生成图只能明确标记为 provisional，不能冒充客户端原帧。
