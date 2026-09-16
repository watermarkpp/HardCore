# HardCore 火墙第九道整改（R2）+ C1 相机边缘解锁 复审请求

- 日期：2026-09-16
- 工作树：`C:\Users\Administrator\Documents\HardCore-aoe-fix-20260915`
- 分支：`codex/fix-aoe-firewall-perf-20260915`
- 复审基线：`c748340a`（20260915 上一次全量复审请求文档提交）
- 复审 HEAD：`963327f0`（本地 == 远端 `origin/codex/fix-aoe-firewall-perf-20260915`，工作树 tracked 零残留）
- 复审范围提交链（7 个，自旧到新）：

```
4028289e fix(skills): record fire wall ninth-field ruling as SOT cap_policy evict_oldest (R2-1)
9844440f fix(gameplay): release fire wall registry slot proactively on field exit (R2-2)
5a0e4756 test(skills): gate fire wall cap_policy through the production canonical plan (R2-3)
75dcdaca feat(gameplay): add debug fire wall registry invariant validator (R2-5)
f42f2639 test(gameplay): ninth fire wall field must create visuals and deal damage (R2-4)
acd718f0 fix(gameplay): close fire wall lifecycle windows and lock the formal plan consumer (R2-6)
963327f0 fix(camera): strict map-edge follow unlock, remove 14% tanh central band (C1 CAMERA-EDGE)
```

- 总量：11 文件，+1052 / −271。

---

## 0. 一句话结论

第一批火墙整改（R2-1~R2-6，用户裁决 evict_oldest）与 C1 相机边缘解锁（删除 14% tanh 中央带/动态缩放，恢复"中心居中、边缘相机停在最后合法中心"的原始语义）已完成实现、专项与回归测试、提交并推送；等待用户实机验收 + 本复审。

---

## 1. 授权链（谁批准了什么）

1. 用户实机测试 `eb9ca528` 基线包后反馈 5 条异常（含"火墙第 9 次施放不生成"）。
2. GPT 20260915 全量复审裁定：火墙 P0（第 9 道）必须按用户实机裁决修复，随后按 CAMERA-EDGE → CAMERA-PIXEL-STABILITY → AUDIO-STARTUP → DEVICE FRAME-PACING 顺序推进。
3. 用户逐项批准（原话摘录）：
   - 「可以进入下一步。**我批准把第一批火墙整改冻结，转入 CAMERA-EDGE。**」
   - 「你可以开始下一步了」（= 批准实施 CAMERA-EDGE C1）。
4. 用户对相机语义的关键澄清（原话）：
   - 「注意 gpt说的相机解锁并不是镜头视距解锁，是我要求的屏幕边缘ui解锁，用意是减少黑幕范围，你不要搞错了」
   - 即：**不是视距/zoom 解锁**（zoom 恒定 1.06 不变），而是地图中心=人物居中、接近地图边缘=相机停在最后一个合法中心、人物继续走动并可偏离屏幕中心，从而最小化地图外黑幕。
5. 火墙第 9 道语义由用户 2026-09-15 实机裁决：**evict_oldest**（第 9 道生成时最旧的一道消失），已写入 SOT provenance。

---

## 2. R2 批次逐项（火墙第九道）

### 2.1 R2-1 `4028289e` — SOT 记录裁决 + 运行时线程化

- `assets/data/vanilla_176/skills_source_of_truth_v1.json`：`wizard.fire_wall.mechanics` 新增
  - `cap_policy: "evict_oldest"`
  - `cap_policy_ruling`（来源：用户 2026-09-15 实机裁决）。
- `scripts/skills/runtimes/wizard_skill_runtime.gd:62-78`：火墙分支把 `stacking_policy` / `max_active_fields_per_caster` / `cap_policy` 从 mechanics 线入效果参数。
- 下游权威链（生产路径已逐步核验）：
  1. SOT（唯一权威）→ `skill_data_loader.gd` 读取；
  2. `wizard_skill_runtime.gd` 线入 effect 参数；
  3. `SkillExecutionPlanContract` 把参数复制到 `ground_effect_descriptors` **和** `gameplay_actions`；
  4. `game_root.gd` 的 `_canonical_plan_ground_effect(plan)` 从 `plan["gameplay_actions"]`（`type == "persistent_ground_damage"`）读取——**不是**从 descriptors（GPT 前次审计纠偏点，本次已按正确对象门禁）；
  5. `_spawn_canonical_ground_field()` 执行 cap：`_fire_wall_cap_allows_new_field()` → evict_oldest 走 `_fire_wall_evict_oldest_field_for_caster(caster_prefix)`，reject_new 走显式拒绝。
- 注：该 JSON 在 git 历史上显示为 Bin（内含特殊字符、无 BOM、`7B 0A` 开头），本次编码零变更，diff 为字段级文本插入。

### 2.2 R2-2 `9844440f` — 字段退场主动释放 registry 槽

- `scripts/game_root.gd` 火墙 registry 块（~9240–9520）：
  - 新增 `_on_fire_wall_field_tree_exited(registry_key, controller)`，创建时 `tree_exited.connect(...)`；
  - **身份护栏**：回调先核对注册表中该 key 当前指向的 controller 与触发者同一实例，防错删；
  - 定义 CAST_ACTIVE 语义：`controller is FireWallFieldControllerScript and is_instance_valid(controller) and not controller.is_queued_for_deletion()`（Godot `queue_free()` 是延迟的，"已排队未注销"窗口真实存在，该窗口内不算活跃）；
  - `_fire_wall_prune_invalid_registry_entries()` 的 stale 判定同步改为 CAST_ACTIVE。
- 效果：字段销毁（到时/驱逐/释放）立刻归还槽位，不再依赖下一次施放的 lazy prune。

### 2.3 R2-3 `5a0e4756` — 生产 canonical plan 门禁测试

- 新增 `tests/fire_wall_cap_policy_canonical_plan_test.gd` + tscn：
  - 走真实 `Router.build_canonical_plan()`（非构造 fixture plan）；
  - 断言 `plan["gameplay_actions"][0]`（`type == "persistent_ground_damage"`）携带 `cap_policy == "evict_oldest"` 与 `max_active_fields_per_caster`；同时断言 `ground_effect_descriptors[0]` 同步携带；
  - 断言接受性读取权威键 `plan["rejection"]["accepted"]`（本会话纠错点：不是 `plan["accepted"]`）。

### 2.4 R2-5 `75dcdaca` — 调试不变量校验器

- `game_root.gd` 新增 `_debug_validate_fire_wall_registry(context)`：
  - 双门：`OS.is_debug_build()` 且 `_fire_wall_registry_validation_enabled`（默认 `true`）；
  - STRUCTURAL_VALID 语义：条目类型 + 实例 valid + registry 与 order 一一对应；**queued（已排队未释放）条目按"释放中"接受**——结构与 CAST_ACTIVE 是两个概念，文档注释已按此修正（GPT 纠偏点）；
  - 在 cast_insert / evict / expiry 三个变动点调用。
- **诚实披露**：正式性能 A/B APK 必须证明该项为 `false`（例如启动诊断输出证据），否则校验器本身污染 perf 数据。这属于 DEVICE FRAME-PACING 阶段（见 §7），当前包是功能验证包，保持默认 true。

### 2.5 R2-4 `f42f2639` — 第九道"看得见 + 掉血"E2E

- `tests/fire_wall_field_registry_test.gd` 第 5 节：
  - 先灌满 8 道（同图不同格），第 9 道正式施放路径生成；
  - 断言：新 controller 创建且注册、最旧一道被驱逐、新道存在可见节点、`_apply_field_tick()` → `_combat_runtime.apply_enemy_direct_spell_damage()` 真实掉血；
  - 修复过程披露：(a) 首跑 E2E 格位与灌满格位相撞被"同格刷新"吞掉（改为独立格位 e2e_field_index 12）；(b) 校验器首版把 queued 条目判死（改按 STRUCTURAL_VALID 语义放行）。

### 2.6 R2-6 `acd718f0` — 竞态窗口关闭 + 正式消费者锁定

- 第 6 节 生产 bridge 测试：真实 Router 产物 plan → `game._spawn_canonical_cast_nodes_from_plan(...)` 全链（锁定正式消费者签名，防未来契约漂移）。
- 第 7 节 queued 同格连放竞态：`dying.cancel()` 后不等待立刻同格重放 → 新 controller 创建、旧的按队列释放、registry 最终只跟踪新的、新的存活——回归窗口已关闭。
- 披露：bridge 测试中 `plan["canonical_snapshot"] = {}` 为人工覆盖（走生产 fallback 路径）。GPT 已裁 non-blocker；后续应改用合法 cell-union 快照（列入 §7 改进项）。

---

## 3. C1 CAMERA-EDGE `963327f0`

### 3.1 根因

`e7c0c6bf` 修 zoom 时保留了 `resolve_soft_follow()` 的 `player_priority_soft_edge_v1` 行为：±14% tanh 中央带（把人物强制限制在屏幕 36%..64% 带）、边缘压力、`recommended_zoom` 动态混合。这与用户原始的"屏幕边缘 UI 解锁"语义直接冲突，也是每帧双次约束求解 + exp/tanh + exposure + Dictionary 构造的性能热点之一。

### 3.2 删除清单（`scripts/map_editor/map_diamond_camera_constraint_service.gd`）

- `resolve_soft_follow()` 整体；`_soft_saturate()`（tanh）；`_exposure_metrics()`；
- 常量 `SOFT_FOLLOW_MODE_ID`、`DEFAULT/MIN/MAX_PLAYER_SCREEN_OFFSET_FRACTION`、`DEFAULT_MAXIMUM_ZOOM`；
- 返回键 `recommended_zoom` / `edge_pressure` 等。
- **保留**：`constrain_center()`（唯一几何权威，零改动）、`minimum_uniform_zoom`、`viewport_corners` / `viewport_inside_boundary`、`_inward_constraints` / `_margin` / `_centroid`、`EDGE_SKIRT_CONTRACT_ID`（skirt 未动）。

### 3.3 新增：缓存化严格求解

- `STRICT_FOLLOW_CONTRACT_ID := "map_diamond_camera_strict_edge_follow_v1"`；
- `resolve_strict_follow_cached(design_size, viewport_half, zoom, desired_center) -> Vector2`：
  - 约束几何按 `(design_size, viewport_half, zoom)` 键缓存（静态 Dictionary；扁平 `Array[Vector2]` 点/法向 + `Array[float]` 支持）；
  - 逐帧路径 = 一次缓存命中 + 最多 32×4 次半平面投影循环，**零分配**（无边界重建、无 Dictionary/Array 构造）；
  - 投影数学与 `constrain_center()` 逐式相同。初版用 `PackedFloat32Array` 存 support，1 万次 parity 出现 ~2e-4 px 级偏差（packed 32 位截断所致），已改为 64 位 `Array[float]` 后与参考求解器**逐位一致**；
  - infeasible（视口大于地图）退化为边界质心——与参考求解器行为一致（小地图露边缘不拉近，维持用户 20260915 裁决）；
  - `strict_cache_build_count()` / `clear_strict_cache()` 供测试证明"不逐帧重建"。
- `scripts/game_root.gd` `_update_world_camera_constraint()`：唯一调用点改为缓存求解 + `zoom = 1.06` 恒定赋值；注释记录裁决与"C2 未动"声明。

### 3.4 单变量纪律

- 本提交只动边缘跟随行为；pixel snap、平滑、视口/纹理过滤、CanvasItem、渲染层全部未碰（C2 范围）。zoom 全路径恒定 `ArtSpec.CAMERA_ZOOM = 1.06`，不存在任何动态缩放代码路径（测试含源码文本门禁）。

---

## 4. 测试证据总表（全部在干净 HEAD `963327f0` 上运行）

| 测试 / 套件 | 结果 | 覆盖 |
|---|---|---|
| `tests/map_diamond_camera_strict_edge_test.tscn`（新增） | PASS | 中心=人物；四边钳制且人物越走偏移越大；四角偏移比例 >14%（证明旧带已删）；缓存 build 计数（同输入不重建、viewport/zoom/map 变更各重建一次）；**10,000 次 parity**（缓存 vs `constrain_center` ≤1e-4 px 且期间零重建）；服务与 game_root 源码无 soft-follow/tanh/recommended_zoom 残留 |
| `tests/game_root_diamond_camera_constraint_test.tscn`（重写） | PASS | 生产路径：zoom 恒 1.06；每探针相机中心==严格参考解；可行时视口四角守恒；中心探针相机==人物；走出边界偏移单调增；角点偏移比例超 0.14；相机不继承人物位移；game_root 源码无残留符号 |
| `tests/map_soft_camera_edge_skirt_contract_test.tscn`（相机段重写，skirt 段保留） | PASS | 80×80/38×38 全探针 parity+合法性；边缘跟随连续性（64 步无跳变）；skirt 覆盖按严格解中心仍全覆盖 |
| `tests/fire_wall_cap_policy_canonical_plan_test.tscn`（R2-3） | PASS | 生产 canonical plan 携带 cap_policy/max_active_fields |
| `tests/fire_wall_field_registry_test.tscn`（R2-2/4/6） | PASS | 7 节全绿（首投/刷新/未配置拒绝/显式驱逐/键源感知/到期+身份护栏/主动释放/第九道 E2E/连发/生产 bridge/queued 竞态） |
| `tests/skills/wizard_canonical_runtime_test.tscn` | PASS | `fire_wall.effects[0].cap_policy == "evict_oldest"` |
| Suite `fire_wall_controller_critical` | 12/12 PASS | 火墙控制器回归 |
| Suite `persistent_ground_effect_critical` | 10/10 PASS | 地面效果回归 |
| `tests/combat_authority_static_gate_test.tscn` | PASS | 战斗权威静态门 |
| Suite `formal_map_projection_critical` | 8/8 PASS | 地图投影回归 |
| Suite `map_runtime_release_critical` | 5/5 PASS | 地图发布门回归 |

测试命令形态：`tools\run_godot_tests.ps1 -TestPaths @('tests/<x>.tscn') -TimeoutSeconds 60`（套件同 runner，`-Suite <name>`）。

---

## 5. APK 产物

| 包 | 来源 HEAD | 状态 |
|---|---|---|
| `outputs\hardcore\HardCore-20260915-aoe-fix-eb9ca528-debug.apk` | `eb9ca528` | 用户已实测基线（保留） |
| `HardCore-20260916-r2-firewall-f42f2639-debug.apk` | `f42f2639` | 中间产物（已被取代） |
| `HardCore-20260916-r2-firewall-acd718f0-debug.apk` | `acd718f0` | 火墙功能验证包（已被取代） |
| **`HardCore-20260916-c1-camera-edge-963327f0-debug.apk`（444MB，已复制桌面）** | `963327f0` | **当前验收包：火墙修复 + C1 相机** |

- 归因说明：`eb9ca528 → acd718f0` 只含火墙 registry/SOT/测试变更（零相机/渲染变更），`acd718f0 → 963327f0` 只含相机服务 + game_root 调用点。一个包可同时验收两系统，反馈可分别归因。
- 直更校验 N/A：`tools/verify_android_build.ps1:62` 在 versionCode 82≡82 时按设计抛错（"higher version code"）；导出与签名已完成，侧载不受影响。是否将 versionCode 递增纳入出包流程**待用户裁定**。

---

## 6. 已知偏差与诚实披露（GPT 重点核对区）

1. bridge 测试 `canonical_snapshot = {}` 人工覆盖（走生产 fallback）——GPT 已裁 non-blocker，列入改进项。
2. `_fire_wall_registry_validation_enabled` 默认 `true`：当前包为功能验证包；**正式 perf A/B 包必须出示该项为 false 的启动证据**（DEVICE FRAME-PACING 阶段执行）。
3. 显式 `reject_new` 配置路径（非默认）仍发生在资源提交后、无玩家反馈——默认 evict_oldest 下不可达；列为后续 UX 债。
4. 相机缓存为静态 Dictionary、字符串键、无逐出：条目数 = (地图 design_size × 视口 × zoom) 组合数，实际运行 ~个位数，泄漏面可忽略；如 GPT 认为需要 LRU/上限可加。
5. SOT JSON 的 git "Bin" 显示为历史既有状态（特殊字符、无 BOM），本次零编码变更。
6. 删除 `resolve_soft_follow` 前已全仓 grep：生产消费者仅 `game_root.gd` 一处；其余引用全部在测试内并已同步重写。

## 7. 未施工项与顺序（均已获用户批准的路线，非本报告请求范围）

1. **C1 设备验收**（§8 门 2）→ GPT 复审本报告 → 下一批。
2. **C2 CAMERA-PIXEL-STABILITY**：手动平滑 + 相机独占 pixel snap（debug 门），A/B Camera-A/B/C；针对地面横纹/全局迟滞。
3. **AUDIO-STARTUP（R2-7）**：BGM 取证先行（prepare/play 用时 + 帧数据），PreparedMusicStream vs 原生 `AudioStreamOggVorbis` A/B（3 冷启 5 重进）；native 胜则删 wrapper；禁止假播放/Timer 掩盖。
4. **DEVICE FRAME-PACING（R2-6 诊断）**：IDLE/WALK/COMBAT/AOE/BGM_START 场景帧数据；perf 包出示校验器关闭证据；可选 RenderingServer 指标。
5. 最终 PERF-CLOSE A/B（用户快照）解锁被阻塞目标 `goal-69fe8003`；合并门：GPT 复审 + 用户实机 + 用户明示「通过，授权合并」。
6. 改进项（非阻塞）：bridge 快照合法化；reject_new 反馈；versionCode 策略。

## 8. 设备验收门（请用户执行）

- **门 1 火墙**（12–15 连放）：第 9 道起持续生成；最旧一道依次消失；新道有动画有伤害；人群中帧率不塌。
- **门 2 相机 C1**：地图中心人物居中；边缘走位时相机停住、人物偏离屏幕中心、地图外黑幕明显减少；**视距与此前完全一致（不拉近不拉远）**；无硬跳/抖动新引入。

## 9. 交付格式合规（AGENTS.md）

- 修改文件：`scripts/game_root.gd`、`scripts/map_editor/map_diamond_camera_constraint_service.gd`、`assets/data/vanilla_176/skills_source_of_truth_v1.json`、`scripts/skills/runtimes/wizard_skill_runtime.gd`、测试 6 个（3 新增 + 3 重写/扩展）。
- 新增稳定 ID：`map_diamond_camera_strict_edge_follow_v1`；SOT 字段 `wizard.fire_wall.mechanics.cap_policy` / `cap_policy_ruling`。
- integration 跨系统接入：无（全部变更限 game_root + 相机服务 + 火墙 SOT/registry 链，归属边界内）。
- 当前提交哈希：`963327f074ecbe6b21c85671251495cab5b736ef`（已推送）。

## 10. 请求 GPT 裁决的问题

1. C1 缓存化严格求解的键设计与静态缓存生命周期（§6.4）是否可接受进入设备验证？
2. 相机测试的"1 万次 parity + 缓存计数 + 源码文本门禁"组合是否满足 CAMERA-EDGE 的回归门要求？
3. C2 是否按"平滑 + pixel snap 同批（同属渲染稳定性）"施工，还是再拆单变量？（我倾向同批、一次 A/B）
4. versionCode 递增是否纳入下次出包（解除直更校验 N/A）？
