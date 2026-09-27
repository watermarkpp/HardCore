# HardCore R3 整改交付（monster combat R3）

施工分支：`codex/monster-combat-r1-20260925`（施工树 `mct-r1-f5d6308f`）。
R3 交付 HEAD：见 `SOURCE_SHA.txt`（SOURCE 与 DOCUMENT 分开登记）。

| 身份 | 提交 |
|---|---|
| BASE | `f5d6308f53162509bffd30f6981987cbfe80fa68` |
| R1 | `9a399c242c51dd4068d2dc155829449f6159c3f1` |
| R2（复审对象） | `2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a` |
| R3 交付 | 见 SOURCE_SHA.txt |

## 1. W0-W7 完成对账

| 项 | 内容 | 提交 | 关键证据（runner JSON，副本在 evidence/） |
|---|---|---|---|
| W0 | 审查包三反例入库并在 R2 源码上实证行为级 RED | `3e022a28` | `runner_results_adhoc_20260926_232424_753_12080.json`（3/3 RED） |
| T1 | 156 身份深度普查矩阵 + 五调用点/伤害分发矩阵 | `f9f6d2d2` | `docs/monster_combat_r2/runtime_census.json`（v2 schema，147 战斗+9 合同禁战） |
| W1 | 单一战斗动作钟 + 父动作身份进真实 release record | `ff659233` | `runner_results_adhoc_20260926_234229_805_5724.json`、`..._234843_842_3952.json` |
| W2 | 音频阶段绑定动作逻辑年龄（同动作一次提交、过期不补声）+ 身体/overlay/tracker 同一冻结朝向 | `57f9cb70` | `runner_results_adhoc_20260926_235933_198_22428.json`、`..._000523_298_13244.json` |
| W3 | 身体 rule→tier 钉死 + 被拒实体完整世界准入隔离（不入组/不受伤/不掉落/无孤儿碰撞节点） | `520c1c80` | `runner_results_adhoc_20260927_000726_636_8504.json`、`..._001050_713_5884.json` |
| W4 | reswap 校验器三类漏检关闭 + 两次正式重建字节一致 | `c23d21d3` | `evidence/reswap_probe_fixed_results.json`（5/5）、`evidence/reswap_rebuild_attestation.json` |
| W5 | 玩家死亡生命周期代际 token（跨复活/二次死亡作废旧通知） | `fddc8b91` | `runner_results_adhoc_20260927_001631_040_15356.json`、`..._001725_763_11188.json` |
| W6 | 真实战斗准入普查（4 身份×20 轮真实起手+结算+身份链）+ R2 基线 34 项逐项核对 | `9264372d`+`7a57a353`+`30d6621b`/`8f15db67` | `runner_results_adhoc_20260927_002158_205_4008.json`、`BASELINE_RECONCILIATION.md` |
| W7 | 配对负载真实化（真 SceneTree 帧/真召唤物/真群死/每条件 3 次/INVALID_WORKLOAD 判据） | `1281fc21` | `runner_results_adhoc_20260927_004304_709_22160.json` + `r3_paired_load_*.json` |

## 2. 三个审查反例：RED → GREEN

| 反例 | RED 证据（R2 源码） | 修复 | GREEN |
|---|---|---|---|
| body_rule_tier_cross_test（76 boss+small / 24 small+large 绕过） | W0 RED 实测 | W3 rule→tier 钉死 | `runner_results_adhoc_20260927_000726_636_8504.json` |
| audio_stale_frame_test（跨动作误消费 frame4 音频阶段） | W0 RED 实测 | W2 音频阶段绑定动作逻辑年龄 | `runner_results_adhoc_20260926_235933_198_22428.json` |
| stale_death_notification_test（复活后旧死亡通知触发） | W0 RED 实测 | W5 死亡生命周期代际 token | `runner_results_adhoc_20260927_001631_040_15356.json` |

## 3. R2 基线 34 项逐项核对（R3-09）

见 `BASELINE_RECONCILIATION.md`：9 项 `CLOSED_THIS_ROUND`（4 项 W6 权威依据修复 +
5 项当前树转绿）、2 项 `USER_DATA_GAP`（21cq 用户权威源对 183/241 攻击间隔=0、
33/183/241 无移速权威——需用户提供数值后经正式生成链补录，代码不得伪造）、
23 项 `OTHER_DOMAIN_OWNERSHIP`（技能/快照/装备/音频服务域，按所有权登记不越权）。

## 4. 配对性能真实化（R3-08）

`tests/hc_monster_combat_r3/paired_load_realism_test.tscn`：真实 SceneTree 物理帧
（引擎 TIME_PHYSICS_PROCESS 监视器）、真实召唤物骷髅参战、真实群死（10/25/35 只），
每条件 3 次重复取中位，INVALID_WORKLOAD 判据（无真实战斗工作的条件直接 FAIL，不产假数）。
桌面结果：三组×三规模 p50 0.080-0.167 ms，随规模线性，远低于 33 ms 帧预算。
**BASE 对照 NOT_RUN**（BASE 无同款探针，无法同条件对比）；R2 时代桌面数字与规模线性关系
是对比锚点。设备帧仍 NOT_RUN（设计边界）。

## 5. full critical（本轮两次，均为规则允许）

- **第 1 次（冻结源码 `1281fc21`）**：491 项 465 PASS / 26 FAIL。26 项中 25 项完全落在
  已分类集合（23 外域 + 2 用户数据缺口）；**唯一新失败 `corpse_king_boss_test` 为
  REGRESSION**——根因是 W2 把 R3-03 冻结朝向错误地扩到了逻辑层（用户合同是"冻结只给
  overlay，身体仍读 actor.facing"）。已在 `3e05e703` 修复（恢复 pending 活转向与 boss
  finalize 原逻辑、overlay 绘制行冻结保留），相关组 4 项 PASS 复验
  （`evidence/runner_results_adhoc_20260927_020037_911_17660.json`）。
- **第 2 次（最终 HEAD `3e05e703`，确认复跑）**：491 项 **466 PASS / 25 FAIL**
  （`evidence/runner_results_critical_20260927_031400_019_10948.json`）。
  `corpse_king_boss_test` 转绿；25 个 FAIL **全部落在已分类集合**：23 项外域所有权 +
  2 项用户数据缺口（33/183/241），**零未分类失败、零回归**。

## 6. 干净检出轻量 Godot 运行（R3-10）

方法：`git worktree add`（detached HEAD `3e05e7035`，`git status --short` = 0 dirty）→
单次最小 `--import`（一个 Godot 进程；**未使用** R2 故障史中的全量 `-PrepareProject`
准备模式）→ 单测试运行级验证。

结果：**PASS** — `tests/hc_monster_combat_r3/attack_facing_freeze_test.tscn` +
`tests/hc_monster_combat_r1/monster_melee_body_pair_test.tscn` 2/2 PASS
（干净检出自身 runner JSON：`evidence/runner_results_adhoc_20260927_032105_655_23972.json`）。
首次未导入运行出现的 global class 解析失败按既有规范定性为"缺导入"环境问题，经单次
最小导入后消除。R2 交付中该验证为 NOT_VERIFIED（系统故障中止），本轮补上。

## 7. 交付边界与 NOT_RUN 清单

- 手机/设备帧测试：NOT_RUN（本轮桌面采样交付，设备验收属发布门禁）。
- 配对 BASE 对照：NOT_RUN（BASE 无同款探针）。
- 33/183/241 用户权威数据补录：MISSING（用户输入）。
- 23 项外域失败：按所有权登记（见 BASELINE_RECONCILIATION.md）。
- 证据归档：`outputs/test_logs/` 的 R3 全部 `runner_results_*` + `r3_paired_load_*` JSON
  副本随本目录 `evidence/` 交付（outputs 被 gitignore，副本才是交付件）；
  SHA256 清单见 `DELIVERY_MANIFEST.sha256`。

## 8. push 与远端核对

R3 全部提交 push 到同一分支（不 merge 主树、不强推）。推送后以 `git ls-remote` 核对
远端 SHA 并记录于 SOURCE_SHA.txt。
