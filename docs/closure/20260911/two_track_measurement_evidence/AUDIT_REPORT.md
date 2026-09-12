# HardCore 双线测量 · 外部审计报告（供 ChatGPT 等独立 LLM 审计）

日期 2026-09-12 · 审计对象：两线测量的方法与结论 · 编写：GLM-5.3-Flash（执行代理）
主控裁决流程：本报告提交给项目主控（Astra）与外部审计，审计意见用于最终裁决。

---

## 0. 审计要点速览（TL;DR）
- 两项测量：M30 怪物帧预算采样（**完成**，36/36 进程，0 数据完整性问题）；UI 操作延迟（**部分完成**，buy 全链路实测，sell/equip/warehouse 因探针侧接线未收口而 NOT_RUN）。
- 所有结论均可由随附原始文件独立复算：36 份完整帧时间原始数组 + 汇总 JSON + 复算脚本随仓库提交。
- 本报告自报全部已知局限（见 §6），供审计挑战。

## 1. 背景与任务合同
- 项目：HardCore（Godot 4.7，主分支线 codex/r3-3-single-heading @ bf887623）。
- 主控任务："M30 用生成的完整采样测试副本做 320 有效采样帧，12/15/30 怪，pursuit+sustained，Before/After 3 轮成对，每场景×怪数独立 Godot 进程≤60s，保存完整 full_frame_ms 原始数组/实际怪数/physics tick/场景身份/源码哈希，重算 min/p50/p95/p99/max 与 >16.67/25/33.3/50ms 尾帧计数。p95 门槛保留，12/15 的 p99、max、长尾必须一起过审。"
- 边界：不合并主树、不打 APK、不改版号、不改怪物生产逻辑与原测试、复用既有工作树（至多两棵固定验证树）。

## 2. M30 测量方法（可复现）
### 2.1 A/B 双方定义
- **Before（基线）**：`codex/m30-r3-integration @ 8dd1d092c58734f83c511a8f796e103f0a6cc823`——R3.3-P2A 交付报告（docs/closure/20260910/UI_R5_M30_最终交付报告.md L10）明示的 M30 冻结基线。已验证其为当前 HEAD 的祖先（git merge-base --is-ancestor 退出码 0）。
- **After（现状）**：`bf887623691e3817683a12c8b5aa6df018323155`（当前生产 HEAD）。
- 双方分别 detached 检出在两棵既有验证树 `m30-r4r2` / `m30-r4r2-baseline`（均 tracked-clean；untracked 仅历史 .translation 文件）。
- **注意**：两 commit 相隔整条 R3 UI 工作线，A/B 度量的是"M30 基线 vs 当前生产"整体，而非"仅怪物逻辑差异"。双方 `scripts/enemy.gd` 等 5 个源文件 SHA-256 已记录于每次运行输出（`source_hashes_sha256`），审计可核对怪物路径是否零差异（生产怪物逻辑在两 commit 之间按冻结令应无变化，此点可由哈希直接验证）。

### 2.2 采样测试副本（原测试冻结未动）
- 原夹具 `tests/hc_monster_ai/performance_comparison_test.gd` 一字未改；副本 `m30_sampling_copy.gd/.tscn` 仅存在于两棵验证树（同字节），与原版差异：
  1. `COUNTS := [12, 15, 30]`（原 [10,20,30]，原版对 12/15 会 assert 拒绝——已实测确认）
  2. `SAMPLE_FRAMES := 320`（原 150）
  3. 每案例结果行新增：`full_frame_ms_raw`（窗口内全部 process 间隔的完整毫秒数组）、`tail_frame_counts`（四档尾帧计数）、`physics_ticks_per_second`
  4. 输出顶层新增 `source_hashes_sha256`（enemy.gd / monster_visual.gd / monster_terrain_navigation_policy.gd / runtime_combat_spatial_index.gd / 副本自身）
- 场景选择/数量选择沿用原版 env 机制（HARDCORE_REV07_SCENARIOS/COUNTS/LABEL/HEAD）。

### 2.3 采样语义（重要，审计必读）
- 原夹具合同：`sample_boundary = "physics_frame_then_process_frame"`。每采样迭代 await 一个真实物理帧 + 一个 process 帧；`sample_physics_ticks` 记录实际物理帧数（=320，逐例校验）。
- headless 下 process 无垂直同步，自由旋转：320 个物理帧窗口内通常产生 ~700-800 个 process 间隔。因此：
  - **有效采样单位 = 物理帧（320 个，逐例断言 `physics_ticks >= SAMPLE_FRAMES`）**
  - `full_frame_ms_raw` 保存该窗口内**全部** process 间隔（超集，约 772 个/例）；所有百分位与尾帧计数在该原始数组上计算
  - 曾尝试"按 process 采样数凑 320"的循环，触发夹具 `physics_ticks >= SAMPLE_FRAMES` 断言（实测 133<320），已回退为原版按物理帧循环。此尝试与其失败证据保留在会话记录中。
- 执行代理曾观察到历史 R3.1 报告有 "sustained×30 n=301<320" 的下采样标记；本轮方法下每例 process 间隔 >320、物理帧恰=320，不存在下采样。

### 2.4 执行与校验
- 36 进程 = 2 树 × 3 轮 × {open_pursuit, sustained_close_attacks} × {12,15,30}；每进程独立、≤60s 超时；同引擎 exe（v4.7 stable）；每树隔离 APPDATA。
- 每份输出逐例机检 5 项：physics_ticks==320、len(raw)==samples、actual_actor_count==标称怪数、hashes≥4、actors_with_motion>0（防静态候选）。36/36 全过（problems=[]）。
- 汇总由 `aggregate.py`（随附）独立重算 min/p50/p95/p99/max（raw 排序百分位）与四档尾帧计数，不信任夹具内置统计，两套数字并存于 `campaign_summary.json`（fixture vs recomputed）供交叉核对。

## 3. M30 完整配对结果（18 对，Before→After，单位 ms）
p95 门（主控保留）：after_p95 ≤ max(before_p95×1.05, before_p95+0.5)。

| 场景 | 怪 | 轮 | p95 前→后 | 门 | p99 前→后 | max 前→后 | >16.67ms 帧 前→后 |
|---|---|---|---|---|---|---|---|
| open_pursuit | 12 | 1 | 10.46→10.51 | PASS | 11.65→11.18 | 13.82→15.92 | 0→0 |
| open_pursuit | 12 | 2 | 10.47→10.42 | PASS | 11.60→11.41 | 13.77→16.50 | 0→0 |
| open_pursuit | 12 | 3 | 10.55→10.49 | PASS | 11.18→11.46 | 17.35→13.43 | 1→0 |
| open_pursuit | 15 | 1 | 11.47→11.60 | PASS | 12.51→12.31 | 19.75→18.61 | 1→1 |
| open_pursuit | 15 | 2 | 11.54→11.43 | PASS | 12.58→12.41 | 15.28→13.93 | 0→0 |
| open_pursuit | 15 | 3 | 11.60→11.27 | PASS | 12.65→12.09 | 18.92→19.88 | 1→2 |
| open_pursuit | 30 | 1 | 16.20→16.08 | PASS | 20.30→19.61 | 24.39→25.52 | 26→28 |
| open_pursuit | 30 | 2 | 15.40→16.10 | PASS | 21.62→20.05 | 28.08→21.87 | 18→25 |
| open_pursuit | 30 | 3 | 16.33→15.48 | PASS | 20.02→19.62 | 22.32→21.50 | 31→25 |
| sustained | 12 | 1 | 11.96→11.22 | PASS | 13.33→13.78 | 16.56→16.83 | 0→1 |
| sustained | 12 | 2 | 11.34→10.96 | PASS | 15.13→13.74 | 17.15→16.55 | 2→0 |
| sustained | 12 | 3 | 10.99→11.67 | **FAIL** | 15.23→12.50 | 17.21→15.15 | 1→0 |
| sustained | 15 | 1 | 12.54→12.29 | PASS | 18.36→17.13 | 19.45→17.93 | 14→12 |
| sustained | 15 | 2 | 12.63→12.38 | PASS | 16.68→17.20 | 19.55→17.81 | 9→16 |
| sustained | 15 | 3 | 12.71→12.17 | PASS | 18.07→16.97 | 19.56→18.06 | 12→12 |
| sustained | 30 | 1 | 22.39→23.62 | **FAIL** | 25.72→29.47 | 34.28→32.11 | 101→71 |
| sustained | 30 | 2 | 24.73→25.75 | PASS | 29.12→32.82 | 32.57→40.10 | 78→74 |
| sustained | 30 | 3 | 23.44→25.32 | **FAIL** | 28.67→35.06 | 33.99→36.21 | 94→70 |

门算复核（审计可自行验证）：FAIL 三例的门前值分别为 11.54（10.99×1.05）、23.51、24.61；PASS 边缘 x30 r2 门 25.97 ≥ 25.75。

## 4. M30 数据的执行代理解读（供审计挑战）
1. **主控关注面（12-15 怪聚怪卡顿）**：×15 三轮 p95 门全过且 p99/max 改善；×12 p99 两轮显著改善（15.1→13.7、15.2→12.5）、max 改善、长尾 ≤2 帧；唯一未过项为 sustained×12 r3 p95（+0.68ms，超门 0.13ms），同轮 p99/max 显著更好——执行代理定性为测量噪声级的边缘波动，但交主控裁决。
2. **sustained×30 p99 三轮一致恶化（+3.8/+3.7/+6.4ms）**，同时 >16.67ms 帧频下降约 30%（101→71 等）。两种读法：(a) 尾部更集中（少数帧更重，多数帧更快）；(b) 负载分布形态变化。基线与现状相隔整条 UI 工作线，恶化源无法由本测量归因（见 §6.1）。
3. **headless 语义**：帧时间 = process 间隔的真实墙钟耗时（无 vsync）。p95/p99 >16.67ms 表示该工作负载超出 60Hz 帧预算的模拟工作量；设备实际帧时间会因渲染更高。绝对值不可直接当作设备帧率，趋势与相对比较是本轮数据的合法用途。
4. 未发现任何 >50ms 帧（x30 sustained max 32-40ms）；>33.3ms 帧数与四档尾帧全量数据在 raw 数组中可复算。

## 5. UI 操作延迟测量（部分完成）
### 5.1 方法（可复现）
- 探针 `outputs/live_preview/r33_ui_latency_probe2.gd`（untracked scratch，随证据提交存档）：`PlayerState.test_mode=false` 全程；生产链启动：`GameData.ensure_loaded()` → `PlayerState.create_character("延迟探针","战士","男")`（合法 seed：生产建号事务，含初始装备）→ `select_character` → `GameHUD.new()`（同 game_root:1481）→ 交易接线为 game_root:1507-1509 原体（`PlayerState.buy_shop_item/sell_inventory_item` + `hud.apply_shop_buy_result/sell_result`）+ 报价请求信号接线（panel.buy_quotes_requested → `PlayerState.shop_buy_quotes(stock, merchant)`）。
- **真实输入**：被测动作为 `Input.parse_input_event` 合成鼠标按下/抬起（完整 Input→Viewport→控件管线，未直接调用按钮 handler）；点击前轮询等待按钮可点击（模拟真实用户，避免点击进 disabled 态）。
- **两级计时**：`t_feedback`=点击→首个可见状态变化（按钮进入 BUSY/disabled）；`t_complete`=点击→玩法状态落地（金币变化）。窗口化 1598×720（真实 60Hz 节拍）。
- **数据核对**：每动作前后记录 PlayerState.gold、装备表、存档文件 sha256/mtime（`user://player_save_v03.json`）；冷启动首操作单独记录，其后为 warm。

### 5.2 购买实测结果（完整闭环，6 行全过）
| 动作 | 输入→首反馈 | 输入→交易完成 | 金币 |
|---|---|---|---|
| buy_cold | 53.6ms | 53.6ms | 496370→495160（-1210 = 单价 ✓） |
| buy_warm_1..5 | 47.5 / 48.2 / 48.1 / 51.7 / 49.1ms | 同左 | 每次精确 -1210 |

解读：两级计时重合（异步交易链 2-3 帧内落地）；无 >100ms 异常信号。存档即时性：交易本身不内联存档（生产事实），由 30s 周期 autosave（仅 test_mode=false 启用，player_state.gd:252-258）持久化——跨会话持久性已实证（上会话金币经 autosave 落盘、下会话正确读回）。

### 5.3 未完成项（NOT_RUN，卡点已定位未实施）
- sell（出售页物品行=空文本按钮行，选中接线未写）；equip/unequip（上下文菜单为长按手势 `_open_long_press_menu`，inventory_panel.gd:1087——长按 helper 已写，unequip 已装备槽定位未完成）；warehouse（按钮已直连 `wh.deposit_button/withdraw_button`，缺 wh 面板自身 bag_list/stash_list 行选中；withdraw 完成判据的初版假阳性已修正但未重测）
- autosave 落盘瞬间专项计时：NOT_CLOSED（30s 观察窗未命中）

## 6. 自报局限与风险（审计重点挑战区）
1. **A/B 归因局限**：Before(8dd1d092)→After(bf887623) 之间不止怪物逻辑（含整条 R3 UI 线）。sustained×30 p99 恶化**不能归因于怪物代码**——除非 source_hashes_sha256 显示怪物路径文件在两 commit 间完全一致（此核对未做，是本测量的一个未闭环验证点；哈希数据已保存可事后核对）。
2. **headless 语义**：绝对帧时间不等于设备帧时间（无渲染、无 vsync）；设备验收 NOT_RUN。
3. **单机单会话**：36 进程在同一台机器连续执行；无跨日方差控制。Before/After 交替顺序未随机化（按树分组先后执行：after 全部 → before 全部），存在理论上的热状态/后台负载漂移风险，跑批期间机器无人工操作。
4. **副本改动面**：副本仅改 COUNTS/SAMPLE_FRAMES 并追加记录字段，未触碰采样循环与场景构建逻辑（一处按采样数凑帧的循环尝试已回退为原版循环）；assert 校验全部保留。
5. **探针与真实游戏差异**：buy 实测走 hud.open_shop（生产入口）但未经过世界/NPC 交互链；无完整地图渲染负载。
6. **未做统计检验**：3 轮样本仅做门限判定与描述统计，无置信区间；p95 门本身是主控合同（×1.05/+0.5ms），非本轮发明。

## 7. 审计建议核查清单（ChatGPT 可直接提问/复核）
1. 逐行复核 §3 表的门算（max(×1.05, +0.5) 规则）；
2. 抽查任一案例：向执行代理索要 raw 数组复算 p50/p95/p99/max 与尾帧（aggregate.py 逻辑 ≈ 20 行）；
3. 质询 sustained×30 p99 恶化的可能来源清单（UI 线 vs 怪物线 vs 引擎同版）与需要哪些补充对照（例：仅怪物文件差集的二分树）；
4. 质询 buy 两级计时重合是否合理（异步 emit → 玩法层同步处理 → apply 回来的帧内完成）；
5. 检查 §6 各局限是否还有未声明的混淆项。

## 8. 证据清单（随本次提交入库）
- `tests/hc_monster_ai/m30_sampling_copy.gd/.tscn` —— 采样副本本体（原测试未动）
- `docs/closure/20260911/two_track_measurement_evidence/`
  - `campaign_summary.json`（12 案例×3 轮 + 18 对配对 + fixture/recomputed 双统计）
  - `raw/` 36 份完整运行 JSON（含每例 full_frame_ms_raw 数组与 source_hashes）
  - `ui_latency_probe_v2.json`（探针会话：buy 6 行 + sell/equip/warehouse 状态行）
  - `run_campaign.ps1` / `aggregate.py`（跑批与复算脚本）
  - `r33_ui_latency_probe2.gd`（探针脚本存档；sell/equip/warehouse 段为修复中状态，buy 段即产出 §5.2 数据的状态）
  - `AUDIT_REPORT.md`（本报告）
- 未入库：两棵验证树本地状态（detached pinned：after=bf887623 / before=8dd1d092）；生产零改动。

## 9. 状态总表
| 项 | 状态 |
|---|---|
| M30 采样与数据 | **PASS**（36/36，0 完整性问题） |
| M30 sustained×30 p99 | **待裁决**（三轮一致 +3.8~6.4ms） |
| M30 sustained×12 r3 p95 | **待裁决**（边缘 +0.13ms） |
| UI 延迟 buy | **PASS**（6/6 行，两级计时 47-54ms） |
| UI 延迟 sell/equip/unequip/warehouse | **NOT_RUN** |
| autosave 落盘专项计时 | **NOT_CLOSED** |
| Android/APK/设备 | **NOT_RUN**（边界禁止） |
| 生产/怪物/原测试改动 | **无** |
