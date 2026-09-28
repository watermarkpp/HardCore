# 集成后失败场景的定向收口（2026-09-28）

## 源与结果边界

- 原始完整执行：`16ec5ef85f636f105ddd32eee71bd29d18f5b207`，566/566 实际执行，559 PASS、7 FAIL，集合核对 PASS、整套验收 FAIL。原始记录在 `critical_clean_16ec_20260928/`，保留失败和超时原貌。
- 修复提交：`965a0c7e883fb7505042a62e697a6b14418396fa`。干净工作树完成 Godot headless 导入，导入 exit 0；`critical_clean_965a_20260928/failed_scene_retests/` 中 8 项实际运行、8 PASS、0 FAIL、0 引擎日志错误，所有子进程正常退出、无超时。其中 7 项与原失败逐项对应，第 8 项是黑铁矿地面图标的直接回归。
- 用户于本轮明确要求：失败场景修复通过即可，不再跑第二次完整回归。因此 **修复后 566 项完整回归 NOT_RUN**；不可将修复前的 559 PASS 和修复后的 8 PASS 拼接成一次全绿执行。

## 七项失败的处理

| 原失败 | 根因和处理 | 定向结果 |
| --- | --- | --- |
| `monster_streaming_scaling_test` | 1800 个真实帧约需 38 秒；原 30 秒上限终止了已打印 PASS 但尚未退出的进程。实测 60 秒内正常退出后，仅将此重场景列入 runner 的 60 秒名单，普通场景仍为 30 秒。 | PASS、正常退出 |
| `item_catalog_test` | 锻造增加 6 件正式圣物/徽章，旧断言固定 175；更新为基础 175 加精确 6 个 ID，共 181。 | PASS |
| `complete_item_system_test` | 11 种纯度黑铁矿没有正式地面贴图；从主服务目录索引 828 精确引入 `DnItems_00284.png`，并在规则层验证路径。 | PASS；图标直接测试 PASS |
| `multi_character_save_test` | 旧测试仍读单宠 `slots`，当前正式存档按 `groups` 存最多 8 骷髅及 1 神兽；更新空组断言，保留旧档迁移检查。 | PASS |
| `user_loot_sheet_authority_test`、`armor_single_slot_authority_test` | 编译产物记录 Git LF 原始哈希，而 Windows 正式检出是 CRLF 原始字节。固定两个指令文件的 CRLF 检出合同，使用正式 `compile_authority.ps1` 重新生成。JSON 语义差异仅为两个 source SHA；5874 个表格槽位的正式重编译比对 PASS。 | 两项 PASS |
| `live_map_loot_authority_export_test` | 只读投影没有为锻造黑铁矿纯度 token 提供 RNG，误报未解析；给投影单独的固定种子 RNG，不消耗生产掉落 RNG。 | PASS |

锻造、拾取、仓库接入等 13 项相邻场景在提交前的同一工作副本上执行，原始结果保存在 `critical_clean_965a_20260928/related_retests/`：13 PASS、0 FAIL、0 引擎日志错误；该 runner 的 `git_head` 仍为提交前 `16ec5ef`，不能冒充干净检出的最终提交。最终提交的原失败复测原始 runner JSON 和每场景 stdout/stderr/Godot 日志保存在 `critical_clean_965a_20260928/failed_scene_retests/`。

## 最终源码负载观察

`native_final_965a_20260928/` 以最终源码在独立检出下执行 30 小怪、30 群攻死亡掉落、30 大体型加双宠场景；各自 600 个连续原生物理帧、正常退出、无引擎日志错误。群攻场景另重复两次，死亡数 124/125/126、实际掉落节点 100/99/99，物理回调大于 50ms 的数量为 7/5/5，P99 为 52.833/47.908/46.966ms。早先固定 `1b74e698` 的三次群攻候选为 3/4/4 个大于 50ms 回调；原 BASE `1381d283` 为 10/9/9。锻造集成改变了掉落数据，这些跨源码数值是风险观察，**不是**同输入的正式配对改善或回归结论。GPU 与实机仍 NOT_RUN。原始逐帧 `load.json` 和 runner 日志均保留。

当前裁定：原 7 项失败的定向修复 **PASS**；修复后完整 566 项 **NOT_RUN**（用户决定）；最终源码性能负载采集 **PASS**，跨源码严格配对和实机 **NOT_RUN**。本记录不代表 APK、设备或远端发布验收。
