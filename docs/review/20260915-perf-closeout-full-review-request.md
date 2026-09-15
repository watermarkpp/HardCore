# HardCore 战斗性能收尾 — 全量复审请求（交给 GPT 审查）

- 日期：2026-09-15（会话内最后一次全量验收于 22:41–22:48）
- 工作树：`C:\Users\Administrator\Documents\HardCore-aoe-fix-20260915`
- 分支：`codex/fix-aoe-firewall-perf-20260915`，已全部推送
- 分支 HEAD：`8c7e9d94`（干净工作树，与远端一致）
- 复审范围：`98afcf47..8c7e9d94` 共 17 个提交（R1 弧线 + 五轮性能收尾）
- 配套评审文档：`docs/review/20260915-aoe-firewall-perf-hotfix-review.md`（R0–R7 全程记录，本文件是其面向 GPT 的完整转写与补充）

---

## 0. 任务来源与边界

1. GPT 对远端 `f8dda719..defcb726` 的终审结论：架构全部 PASS，但「彻底根除掉帧」= **BLOCKED**（无帧时间证据）。终审四项技术断言（record 路径每查询分配、manager 绕过服务、manager:285 直连 take_damage、`_max_actor_bounds_gu` 只增不减）经实码逐行核实**全部属实**。终审指令：不改写 R1，做 R1-C + PERF-CLOSE。
2. 用户批准五轮方案：PERF-1 热路径零分配 → PERF-2 max_bounds 收缩与 probe ORDER_NONE → ANIM-EVIDENCE 火墙动画取证与用户裁决 → R1-C damage 闭环 → PERF-EVIDENCE APK A/B 实测。约定：**APK A/B 数据出来前性能结论保持 BLOCKED**。
3. 边界：地图编辑器（MSE）不在本代理职责内；`combat_runtime_service.gd` 归 professions-skills 所有，本分支**只调用不修改**。

## 1. R1 弧线回顾（前序会话，复审范围起点）

- `153bf394`：火墙 source-aware 注册表（SOT max_active_fields_per_caster=8，cap_policy 显式化：未配置 fail-closed 到 reject_new，废除隐式 evict-oldest 运行时发明）。
- `58422737`：关闭 legacy 敌人组扫描与直连 take_damage 兜底（GroundSkillEffect 自管 tick 无空间上下文时 fail-closed）。
- `1478c5f0`：静态权威门禁 `combat_authority_static_gate_test`（收口函数冻结、ability-id 战斗枚举冻结、禁组扫描/禁直连伤害）。
- `cf47660a`：`CombatTargetQueryService`（scripts/layers/runtime/combat_target_query_service.gd，全局类）+ 随机化正确性 oracle：形状 single/circle/sector/capsule/cross + SHAPE_AABB 透传；fail-closed（`spatial_index_unavailable`/`runtime_map_unavailable`/`bounds_invalid`）。
- `d1d015ba` + `681dcb3e`（R1-A）：火墙 controller broadphase 迁服务。
- `f874a7d2` + `defcb726`（R1-B）：game_root 四个特殊几何收口（melee footprint/sector、wizard cell-union、sky strike、wild-rush blocker）迁服务；当时以 dict `query()` + record 解包 + 复刻活体过滤 wrapper 实现逐位一致。
- 诚实修正（本会话 R7.0 记录）：GPT 指出 R4 文档「唯一生产目标查询权威」表述过满（manager/ground_effect 自管 tick 当时仍直连索引）——采纳，R7 起以精确表述替代。

## 2. PERF-1 — 热路径零分配收口（`2170c414`）

### 2.1 机制
- **服务快路径**：`CombatTargetQueryService.query_envelope_into(bounds, output, stable_order=true, epsilon_gu=0.0) -> bool`。原始参数（**无 request Dictionary**）、caller-owned 输出数组、委托 `RuntimeCombatSpatialIndex.query_enemy_nodes_aabb_into`（caller-owned 节点查询：query-stamp 去重、内联活体过滤 queued/_dying/_death_pending/hp≤0、插入序 + instance_id 决胜）；拒绝语义镜像 `query()`（bool + `last_rejection_reason`），任何分支先清输出。dict `query()` 保留（oracle/锚定形状）。
- **索引参数**：`query_enemy_nodes_aabb_into` 增加 `stable_order := true` 可选参数（段查询同款先例），透传 `_query_enemy_nodes_in_aabb`。
- **宇宙恒等式（行为保持核心论证）**：record 路径 `query_aabb_candidates(map, bounds, ε)` = bounds grown by (ε + `_max_actor_bounds_gu`) 后桶迭代、**无活体过滤**；快路径 = `grow(ε)` 后节点查询再加 `_max_actor_bounds_gu` + **内联活体过滤**。ε 相同 ⇒ 候选集逐位一致。
- **四个消费者**：game_root 四收口（ε=0）改经 `_service_envelope_into(bounds, output)`（原 `_service_candidates_envelope_into` 删除，request dict 构造与 record 解包消失；`_aoe_service_enemy_broadphase_current` 活体过滤复刻件删除——节点查询内联同款过滤，复刻件不再需要）；**PersistentGroundEffectManager**（GPT 终审 P1 项）迁服务（自建服务实例，controller 同款模式；map id/index 变化重建），ε=EXPANSION_EPSILON_GU=0.05 保持原 record 宇宙；**FireWallFieldController**（最后一个 record 路径生产消费者）同轮迁快路径（ε=0.05 = d1d015ba 前直连值）。精确门 `runtime_target_is_inside`/`_canonical_target_is_inside`、claim、damage 路由**逐字不动**。
- **静态门禁**：manager 禁 `query_aabb_candidates(` 且必含 `query_envelope_into(`；controller 必含快路径且禁 `.query({`；服务必须保留快路径。
- **休眠合同如实声明**：`GroundSkillEffect` 自管 tick（`ground_effect.gd:351` 直连 `query_aabb_candidates`）为 R1-P0 门禁冻结的休眠合同——generic 效果全由 manager 拥有、火墙走 controller，生产不可达；留 R1-C 后续处理（见 §8）。

### 2.2 语义漂移（如实）
- fail-closed：manager/controller 对服务拒绝按「空候选集」处理（旧 record 查询对不可用 map 返回空、无拒绝）——净行为一致。
- 诊断口径：`candidate_count/total_candidate_count/max_candidate_count` 现统计**活体**节点（旧 record 路径把濒死注册者也计入）——仅诊断变化，已代码注释。

### 2.3 测试证据（49 项 PASS）
parity 测试升级三重断言（96 rect + 48 segment：快路径 ≡ 直连节点查询 ≡ record∩活体过滤；默认 ε ⊇ ε=0 两路径各自成立 + 快路径 fail-closed 用例）；门禁、oracle、fire_wall 12/12、persistent 10/10、plan 10/10、r3x6/warrior/wizard/sky_strike/melee 5/5、wizard_line 3/3、projection 6/6。中途一次门禁变量重名 parse error（新增 `query_service_source` 与 R1-A 段重名），修复后全绿。

## 3. PERF-2 — max_bounds 收缩 + probe ORDER_NONE（`65a0de59`）

### 3.1 max_bounds 惰性收缩（终审 §14 采纳）
- `unregister/_erase_entry/clear_map` 移除条目时，若其 `bounds_gu >= 当前 max` 则置 `_max_actor_bounds_dirty`；五个查询入口（record aabb/segment、节点 aabb/segment、批量段）首行 `_maybe_refresh_max_actor_bounds()` 一次 O(在册) 重算。
- **安全论证**：dirty 期间存量 max 偏大（被移除的是 max 持有者）——保守方向，superset 不变量（所有在册 actor bounds ≤ max）保持；重算只缩不涨，不可能漏活体候选。
- 诊断 `diagnostics()["max_actor_bounds_gu"]` 反映存储值（惰性，不主动刷新），已文档化。

### 3.2 probe ORDER_NONE（调用点逐一分类后最小切换）
全部 8 个 `_target_spatial_query_*` 调用点核实：
- **切无序（3 个，纯布尔存在性探测）**：`game_root.gd:5644` 野蛮冲撞 blocker（判定与顺序无关）、`:10314` 召唤占位、`:12903` 随机传送占位（均距离存在性判定）。
- **无序分支安全性论证**：无序预滤只丢弃「索引存储位置在查询矩形外」的桶边 actor（矩形已含 max_bounds 增长）；center 超出 ⇒ 身体（半径 ≤ max_bounds）够不到内层窗口 ⇒ 精确门必然拒绝——布尔结果不变。
- **保持 STABLE（5 个，保守裁定）**：`:7660` canonical 伤害投递路径（顺序即打击顺序）；`:5511` 野蛮目标搜索（best-first「先见者胜」，平局顺序敏感）；`:4876`/`:4994` 攻击/法术锁定（虽带 instance_id tie-break，保守保持）；`:6571` 纯诊断（无收益不切换）。
- **parity 新增性质断言**：无序结果 ⊆ 稳定结果（96 随机 rect）。
- **专测**：`runtime_combat_spatial_index_max_bounds_test`——5.0 大脚 actor 注销 → 查询前仍 5.0（惰性）→ 下次查询缩到 0.3 → 新 max 立即生效 → shrunk envelope 仍覆盖人群 → clear_map 归零。
- 门禁加索引 tripwire（`_max_actor_bounds_dirty`/`_maybe_refresh_max_actor_bounds` 必须存在）。

### 3.3 证据
50 项全 PASS（新增 max_bounds 专测 + parity 扩展 + 门禁 + oracle + 全功能回归）。

## 4. ANIM-EVIDENCE — 火墙动画节奏取证（`6b95d0aa`）

实测链（全部读自当前 HEAD，逐环核实）：
1. **权威数据**（`assets/data/caster_skill_visuals.json` fire_wall 条目，生成器 `tools/build_caster_client_art.py` 产出）：`frame_time_ms=40`、`frame_count=6`（source_index 1630–1635 = FIREBURNBASE+0..5）、`playback: loop`。mapping_rule：原版 clEvent.pas `FIREBURNBASE=1630+((m_dwCurframe div 2) mod 6)`，m_dwCurframe 每 20ms 步进 → 可见帧 40ms → **240ms 循环**。
2. **运行时**（`ground_effect.gd` `_install_visual` → `caster_skill_animation_player.gd`）：播放器读 manifest 时序；`configure()` 置帧 0 起步。
3. **相位**（`fire_wall_field_controller.gd`）：controller 持 `_anim_clock_ms`（`_physics_process` 累加，从 0 起步）→ 9 cell 经 `set_shared_anim_clock_ms` 共用现场时钟；`_apply_shared_clock_frame` 取 `fmod(clock,240)/40`。即每次施法独立计时、帧 0 起步、整墙同帧——与原版每道火墙魔法各自计数器语义一致。
4. **结论**：现行视觉节奏 = 原版 SOT 逐项一致（×1.0 即还原）。唯一量化差：帧切换由物理 tick（≈16.7ms）量化，原版同受 20ms 逻辑 tick 量化，幅度同级。
5. **伤害解耦**：伤害 tick（0.8s `tick_interval`）与动画时钟完全独立。

**待用户裁决候选**：×1.0（40ms/240ms，原版还原，现状）、×1.25（50ms/300ms）、×1.5（60ms/360ms）。实现注记：manifest 为生成物，裁决后走生成器侧显示节奏派生（如新增 per-skill `visual_frame_time_ms` 覆盖字段），保留 `frame_time_ms: 40` 作为 SOT 取证记录，**不手改生成 JSON**。

## 5. R1-C — damage 闭环：最后一个直连伤害口（`30af723f`）

1. **权威核实**：终审所称 "CombatHitRequest → CombatDamagePipeline" 在本仓实体为 `scripts/layers/runtime/combat_runtime_service.gd`（autoload `CombatRuntime`；注入式消费先例：game_root:353 与 skill_projectile 各持自有实例，M30-CLEANUP-001 所有权合同——服务实例由 Node 所有者持有，避免孤儿泄漏）。manager 生产路径本就走 entry `damage_callback`（game_root 注册必带，绑 `_apply_canonical_ground_tick` → `apply_enemy_direct_spell_damage` 完整法术解析：魔防/抗魔/红毒）→ effect `runtime_tick_adapter` → 兜底 `enemy.take_damage(damage, source)`——兜底**无任何生产或测试消费者**（fixture 全部自带 callback），纯逃逸口。
2. **改动**：manager `_init` 增可选 `combat_runtime` 注入（manager 是 RefCounted，不自建 Node，避免 M30 孤儿类）；game_root 传入自有 `_combat_runtime` 实例；兜底改走 `apply_enemy_physical_damage`——同数值、同 source 归因，附加服务侧 `can_receive_damage` 复检与 `take_damage_usec` 计时诊断；**无注入 fail-closed**：拒绝交付并计 `damage_delivery_skip_count`。生产数值零变化（兜底生产不可达；服务 `maxi(1,·)` 与既有 `damage > 0` 守卫等价）。
3. **门禁**：manager 必含 `apply_enemy_physical_damage(` 且**禁 `take_damage(`**；controller/ground_effect 既有禁令保持。
4. **专测**：`persistent_ground_effect_service_damage_delivery_test`——注入 → 经服务精确交付 7 点；未注入 → hp 不变 + skip 计数 1。
5. 50 项全 PASS（含全部功能回归）。

## 6. PERF-EVIDENCE — 采样与 A/B 准备（`eb9ca528`/`0e2b9dc9`/`8c7e9d94`）

1. **`frame_ms_max`**（eb9ca528）：`frame_sampling_snapshot` 补最差保留帧（原只有 P50/P95/P99 + 阈值桶）；环形缓冲溢出由既有 `frame_samples_dropped` 披露；`monster_density_diagnostics_window_test` 锁定新字段契约。采样入口 `DeviceLabRuntime._process`（仅调试门放行，Release no-op），指标经 Device Lab mailbox 导出——既有通道，无需新埋点。
2. **A/B 协议（R7.8）**：
   - 实验组 APK：`HardCore-20260915-aoe-fix-eb9ca528-debug.apk`，SHA256 `C6838DDE9D407E38F03295EAC93A0C8CF931147D30D22661314EC1410B0C8B7A`，versionCode=82，`com.personal.mafaoffline`，v2 签名与 splash 校验通过（8c7e9d94 为纯文档提交，APK 载荷=eb9ca528）。
   - 基线：98afcf47（R1 弧线之前，含用户报告卡顿的原始战斗实现），SHA256 `3B2057F9101E9A853439662896644399AAA8CD7DED31720DC025842B0D5F57CA` 已留档；**本地基线副本已按用户要求删除**（用户设备上现装旧版即基线；需要时可由构建脚本从 98afcf47 重出）。
   - 场景：蜈蚣洞（15 普怪+2 钳虫+固定节奏火墙）、祖玛寺庙、Gen1→Gen5；流程：预热 ≥60s → 战斗窗口快照 → 静置恢复后 120 帧快照；指标：`frame_count`、P50/P95/P99/max、over_16.67/33.33/50/100ms 计数与比率。
   - **裁决标准**：实验组 P95/P99/max 显著下降（重点 over_33_33/over_50 比率）且行为无回归 → 解除 BLOCKED；否则如实维持。
3. 构建过程如实记录：首次失败（脚本默认基线路径不存在）、第二次在 max 字段提交前启动被主动终止（保证 APK 与源哈希一一对应）、第三次成功。构建脚本末尾「直装 versionCode 门」对 A/B 并装不适用（同码 debug 可 `adb install -r` 覆盖），已文档化。
4. 桌面交付：实验组 APK 已复制到用户桌面（哈希校验一致）；基线组 APK（桌面副本 + 工作树 98afcf47/cbd84fd5）已按用户要求删除，仅存实验组。

## 7. 最终验收（干净 HEAD `8c7e9d94`）

全漏斗 **52/52 PASS**：门禁、parity（三重+unsorted⊆stable）、oracle、max_bounds、R1-C 交付双路径、诊断窗口（含 max）、persistent 10/10、fire_wall 12/12、r3x6/warrior/wizard/sky_strike/melee 5/5、plan 10/10、projection 6/6、wizard_line 3/3。工作树干净、与远端一致。

## 8. 想法与后续（一并如实写入）

1. **火墙节奏**：待用户实机裁决 ×1.0/×1.25/×1.5；实现走生成器侧覆盖字段。裁决不影响性能结论（视觉时钟与伤害时钟已证解耦）。
2. **GroundSkillEffect 自管 tick 迁移（休眠合同）**：生产不可达（generic 效果全归 manager、火墙被 game_root 显式拦截），但它是最后一个直连索引的战斗消费者。若未来该路径复活（新技能描述符化），应直接迁 `query_envelope_into` 快路径并过门禁扩展——不必先迁 dict 版。
3. **ORDER_NONE 保守余量**：锁定/搜索路径保持稳定序。若后续 profile 显示稳定插入排序成本可观，可先给 `:5511` 野蛮目标搜索补 instance_id tie-break（消除先见者胜的顺序敏感）再切无序——一个可控的小改造，本轮未做（无证据驱动，PERFORMANCE WORK 纪律：不做未测量优化）。
4. **`_enforce_bich_safe_zone`**：sanctioned 直连索引站点，push 语义顺序无关，理论上可切无序；本轮未动（不在服务路径、无 profile 证据驱动），留观。
5. **服务形状库**：sector/capsule/circle/cross 精确门尚未被生产技能消费；等新技能描述符化时启用，不发明消费者。
6. **R6.4 遗留 staged**：boss-surrounded 邻域组扫描（死亡窗口/召唤物计数合同未裁决，直接换 `query_neighbor_enemy_nodes_into` 需先裁决）；Gen1→Gen5 矩阵将在 A/B 设测中顺带补采。
7. **已知非本线债务**：equipment 套件 4 项基线既有失败（本线之前即存在，与本弧线无关）。
8. **max_bounds 语义**：dirty 期间 max 偏大是保守方向；诊断读数是存储值（惰性）。若未来要诊断即时准确，可在 unregister 后主动触发一次重算（当前无此需求）。
9. **性能结论纪律**：在 A/B 数据出来前，「彻底根除掉帧」保持 BLOCKED；静态候选、微基准、测试 PASS、用户实机确认分别记录，不互相替代。

## 9. 请 GPT 复核的具体问题

1. PERF-1 宇宙恒等式（bounds+ε+max_bounds vs grow(ε)+节点查询加 max_bounds+内联活体过滤）是否构成候选集逐位一致的充分论证？
2. PERF-2 的 ORDER_NONE 三点切换 + 五点保守保持的裁定是否认可？无序预滤安全性论证（center 超出 bounds+max_bounds ⇒ 精确门必拒）是否成立？
3. R1-C 兜底经 `apply_enemy_physical_damage` 闭环 + 无注入 fail-closed 的方案，对照终审「CombatHitRequest → CombatDamagePipeline」意图是否满足？
4. ANIM-EVIDENCE 取证链与「×1.0=原版还原」结论是否认可；候选实现走生成器侧覆盖字段的方案是否认可？
5. A/B 协议（场景/指标/流程/裁决标准）是否足以解除「彻底根除掉帧」的 BLOCKED？
