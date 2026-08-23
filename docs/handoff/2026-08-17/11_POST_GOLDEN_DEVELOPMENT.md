# Post-Golden 后续开发记录

> 以下是 Golden APK (1.18.3, commit 9d6435bc) 之后的明确后续开发。
> 这些内容不在已验收 APK 中，不属于错误，而是用户继续要求开发的功能。

## 1. canonical_monster_catalog (217 条)

- **文件**: `assets/data/runtime/canonical_monster_catalog.json`
- **生成器**: `tools/build_canonical_monster_catalog.py`
- **APK 中**: 不存在此文件
- **当前数量**: 217 条 (vs Golden 214)
- **新增来源**: post-APK commits 在 vanilla_176/monsters.json 中添加了 3 条新记录
- **状态**: 后续开发，非 Golden 回退目标

## 2. vanilla_176/monsters.json (+3 条)

- **Golden**: 214 条
- **当前**: 217 条
- **变更 commits**: `5dda4611`, `b893b951`
- **性质**: Excel 导入追加，用户确认的新增怪物

## 3. monster_behavior_profiles (+1 原型)

- **Golden**: 35 个行为原型
- **当前**: 36 个
- **变更 commit**: `58665f12` (fix(monsters): classify zuma guards for holy word)
- **性质**: 新增 zuma guard holy word 分类

## 4. 地图编辑器 canonical monster ID 迁移

- **Commit**: `666e2883`
- **影响**: 11 个地图编辑器 JSON + 11 个地图运行时 JSON + 地图编辑器脚本
- **性质**: 将地图数据从旧 ID 格式迁移到 canonical monster ID
- **状态**: 后续数据规范化

## 5. NPC 世界标签优化

- **Commits**: `dd17716e`, `c1a60bcb`, `d148e2a1`, `59724524`
- **影响**: npc_actor.gd, npc_visual.gd, player_health_bar.gd
- **性质**: 4 个 commit 改进世界标签对齐和显示
- **状态**: 后续 UI 改进

## 6. game_root.gd / game_data.gd 后续修改

- **game_root.gd**: post-APK commit `a91bc586` 修改怪物权威逻辑
- **game_data.gd**: post-APK commits `a91bc586`, `5c1e6697`, `7bbb4bbc` 修改掉落和地图引用
- **性质**: integration 层面的全局脚本演进
- **状态**: 后续开发，当前 HEAD 匹配最新 post-APK commit

## 7. map_panel.gd 后续修改

- **Commit**: `5c1e6697` (retire legacy map boss lookups)
- **性质**: 移除旧版地图 Boss 查找逻辑
- **状态**: 后续开发

---

## 总结

| 类别 | 数量 | 说明 |
|------|:---:|------|
| 新增 canonical 怪物 | +3 | vanilla_176/monsters.json 追加 |
| 新增行为原型 | +1 | zuma guard holy word |
| 地图数据迁移 | 22 文件 | canonical ID 迁移 |
| NPC UI 改进 | 4 commits | 世界标签对齐 |
| 全局脚本演进 | 3+ commits | game_root/game_data/map_panel |

**重要**: 这些内容不应被回滚或视为错误。它们代表 Golden 验收后用户继续推进的开发工作。
