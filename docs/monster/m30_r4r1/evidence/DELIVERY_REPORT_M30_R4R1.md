# M30-R4R1 精修交付报告

- 分支：`codex/m30-r4r1-refine`（工作树 `HardCore-worktrees\m30-r4r1`）
- BASE：`fcc85acd5a7a4bca75372f900c46a35a3a425fb2`；FINAL：见提交表
- 包：`HardCore_M30_R4R1_审查精修核心施工包.zip`，SHA256SUMS 23/23 OK；`tests/test_offline.py` 33/33 OK；preflight 8 既有（enemy/monster_visual/walk_phase/summon_queue + 4 测试夹具）+3 新测试，无 GameRoot/AIA2/assets
- 证据归档：`docs/monster/m30_r4r1/evidence/`（INDEX.md 含 MISSING 标注）

## 提交表

| 提交 | 内容 |
|---|---|
| `901a331c` | 核心精修（apply_refinement.py --apply，candidate.patch+manifest 存于 `outputs/m30_r4r1_itd403g2`） |
| `da3e80c9` | R4 证据归档（33 文件） |
| （最终） | 八方向 art-wait 夹具适配 + R4R1 性能证据 + 本报告 |

## 分项结论

| 项 | 判定 | 说明 |
|---|---|---|
| 核心施工 | PASS | 安装器 blob 门禁通过，APPLIED_NOT_COMMITTED；未改核心语义外内容 |
| Godot 解析 | PASS | Godot 4.7.stable.official.5b4e0cb0f headless；首批 7/7（r1_core_test/test_m30_core/runtime/geometry/path/combat_epoch/repro）exit 0 无引擎错误 |
| 功能回归 | PASS | 同上 7 项；test_m30_ablation_d PASS |
| 八方向实际采样 | **FAIL（需复审）** | 包版严格夹具 completed=2/8。冷启动新鲜度 48 项失败已由"采样前等待 uses_final_art"夹具适配消除（断言不弱化，采样帧仍须全新鲜，0 残留）。剩余 10 项为真实行为差异：dir 0-2 无外圈首攻（到达 preferred 后循环早退，外圈攻击时序不确定）；dir 4/6 上侧攻击锁定不接近（314 攻击样本/0-11 行走）；dir 5 落点被出生权威重定位（预检 8 向 walkable+world 检查与实际落点清障不一致）。未改核心算法，失败证据保留：`outputs/test_logs/runner_results_adhoc_20260910_155627_406_23436.json` |
| 冷热前提 | PASS | D 探针：冷生 3.6–6.4ms vs 热生 3.3–3.9ms 分列；纹理在采样前实际生效（art-wait 后 visual_process_frame 全新鲜）；D=measurement integrity，性能 NOT_EVALUATED |
| 母体函数烟测 | PASS | 复现场景（精修核心）23/23；旧比奇函数烟测标签未升级 |
| 猪洞现场 | NOT_RUN | 候选地图已定位：monster 126 出没 `assets/data/runtime/map_editor/mengzhong_stone_tomb_f3/f4.runtime.json`（盟重石墓=猪洞，正式地图索引）；独立现场场景（母体 126/子怪 127/刷新位/map ID/generation/life）未及构建，留待下轮 |
| 12 组性能 | PASS（新） | R4R1 5 有效轮（r2 引擎 60s 超时作废，原样保留）vs v72 6 轮 vs fcc 6 轮：**12/12 PASS**（对 v72 与 fcc 门槛均 PASS）；sustained@30 中位 30.931 < v72 32.702 < fcc 34.468 |
| fcc 遗留 FAIL | 保留 | fcc sustained@30 0.131ms FAIL **原样保留**（不因新结果抹除）；历史绝对门槛（11.962/11.720）v72/fcc/R4R1 三方同 FAIL（本机环境） |
| ground_contact 独立遗留 | 已归档 | 预存失败（主树同败+隔离还原证据），见 `evidence/ground_contact/` |
| 真机 | NOT_RUN | 无设备接入本会话 |
| 录屏 | NOT_RUN | 依赖真机；八方向场景清单已在包测试中程序化覆盖 |

## 适配清单（最小 diff）

1. `tests/m30_r4/test_m30_eight_direction_steps.gd`：每方向采样前等待 `visual.uses_final_art()`（断言保持：所有采样帧仍须 `visual_process_frame==当前帧`）。原包文件与适配 diff 见提交（901a331c 为原包字节，最终提交为适配）。
2. 无核心代码改动。

## 待复审（不自改）

1. 外圈首攻时序（dirs 0-2 到达即 break，未观察到两格外首次攻击——行为随机性还是节奏违规需主控裁决）。
2. 上侧攻击锁定（dirs 4/6 在 2.0 GU 反复攻击不接近——预检 walkable 与实际寻路/落点清障不一致）。
3. dir 5 出生权威重定位（预检通过仍重定位）。
