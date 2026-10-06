# CLOSEOUT_LEDGER（架构收口总账）

- 建立：2026-10-06（S0）；固定基线：`272430b3692e776b25df820eaa8b53ed9f34bd8e`
  （parent `160e9c79b`）；分支 `codex/glm-thirdtree-continuation-20261006`（唯一施工线）。
- 本表是施工计划的新记录（S0 完成条件要求），不是现有实现的验收声明。
- 状态只用 PASS / FAIL / BLOCKED / NOT_RUN / MISSING / OPEN。

## 需求 → 路径 → 测试 → 状态

| # | 需求（合同条目） | 当前生产路径 | 覆盖测试 | 固定 source | 状态 | 阻断范围 |
|---|---|---|---|---|---|---|
| 1 | 初始 READY fixture 完成条件 = 正式四条件合同 | `tests/helpers/formal_initial_ready.gd`（新增）；`tests/helpers/formal_world_skill_fixture.gd` `wait_for_formal_world`；`tests/initial_world_bootstrap_test.gd` | initial_world_bootstrap_test、monster_summon_formal_birth_test + 同 helper 全部消费者（13 场全绿） | 272430b36 | **PASS**（14 场 + birth direct 210 + mixed 380 逐场 receipt 见 evidence_20261006/） | 无 |
| 2 | 启动性能 SLA | 生产未改（60 秒有界等待合同） | ready 诊断（8513/8163ms 实测） | 272430b36 | **OPEN / PRODUCT SLA MISSING**（60 秒 ceiling 非门槛） | 无（不阻断独立项） |
| 3 | 同种 DOT 完整替换（new_due=施加时刻+新period、expiry=施加时刻+全新期限、新 source/credit/lease） | `scripts/features/runtime/effect_runtime.gd` `_apply_command` 同种替换分支（原子新 incarnation、heap.remove、presentation refresh 同头、chain_owners 承接、旧 loan 槽归还、`replaced` 终态）+ `ignite_handler.gd` species/layer/refresh_policy 注入 | dot_replace_contract_test（20/20 RED→GREEN）、feature_receipt_retirement（replaced=65970）、periodic_effect_boundaries、periodic_refresh_period_boundary、periodic_refresh_horizon、feature_state_loan_lifetime（期望随 2026-10-05 用户裁决更新） | 272430b36+ | **PASS**（S1） | 无 |
| 4 | 认证 species / 独立层权限（default-off，接受时冻结） | `feature_compiler.gd` 可选 status_layer 校验（稳定 ID + `effects.layered_status` 权限；config 可选键）；`feature_authority.gd`/`handler_registry.gd`/`ignite.json` 授予该验证能力；`combined_effect_lifecycle_test` 90 状态=三层表达、`feature_mixed_delivery_test` 同种多源收敛 1 头 | combined_effect_lifecycle_test（39）、feature_mixed_delivery_test（380）、feature_compiler_test、feature_production_loadout_test | 272430b36+ | **PASS**（S1） | 无 |
| 5 | 出生闭包（完整 base 计划 + SummonQueue 真 ordinal） | 已有生产实现 + birth direct 11 场；新组合 `tests/feature_birth_capacity_combination_test`（385 checks）：正式世界内召唤闭包（3 源→25 子嗣 ordinal、materialization 预算、landing 预算）与 feature 16 层×28 活体=448 头满载并存，4 自然仿真秒逐秒 ordinal 不变量保持、全部 due tick 帧节奏内服务，真实死亡同时出清两本账（feature fatal retire + 召唤 slot 释放），双侧 retire 尾部记账归零 | feature_birth_capacity_combination_test + monster_summon_formal_birth_test（复验） | 272430b36+ | **PASS**（S2 组合收口） | 无 |
| 6 | 容量三份证明（同时驻留/累计合法工作/可服务时效） | 新组合 `tests/framework/feature_capacity_trifold_test`（85 checks）：①16 登记层×30 目标=480 头同时驻留、第 17 层在动作发生前经 `feature_action_target_capacity` 显式拒绝且无 HP 副作用；②20 轮 retire 后每轮全配额归还、累计 630 facts/1080 receipts 走 write boundary、无泄漏；③满载 1920 due tick 全部在自身 1s 周期内服务（lateness<1s）；历史 pending8192/AOE 反例的原记录保留 | feature_capacity_trifold_test | 272430b36+ | **PASS**（S2 三份证明）；历史 FAIL 保留 | S6 判定参考 |
| 7 | 资源发布真实交错（scene-change 即时失败、publisher 物理替换、闭包打包） | scene-change 即时失败新实现（`feature_resource_preparation.gd`：Request.scene_epoch + 服务 quantum 首观察即失败 `feature_resource_scene_changed`，仅 kind=module，四种 code kind 显式豁免）；新场景 `tests/framework/feature_resource_scene_change_failure_test`（9 checks）：切换后未决 prepare 立即显式失败、job/retirement/application 零残留、失败候选不发布进后继场景、恢复后新 prepare 健康。publisher 物理替换（combined，行 6）与闭包打包（audio_closure 复验 PASS）已有证明在改动后复验成立。资源回归 11 项（lifecycle/world_activation/audio_closure/promotion_cancel/queued_cancel/started_cancel/continuous_service/shared_quantum/preparation/publication + 新场景）PASS。基线定性（受控实验，字节精确）：terminal_failure 与 code handoff×4 的 FAIL 为既有（HEAD 同 checks 同断言同文本）——前者是测试故意注入损坏纹理而 runner EngineErrorAllowlist 缺该模式的既有缺口；后者是 Windows ad-hoc APPDATA 无 cloud 子目录/尾斜杠 vs Linux formal 断言的结构性环境差异（kind 豁免另经代码审查+运行时同构双证） | feature_resource_scene_change_failure_test + 资源回归 11 项 | 272430b36+ | **PASS（S3）**（terminal_failure/code handoff×4 = BASELINE_EXISTING，正式绑定留 S5 formal runs） | S5 归因清单 |
| 8 | 35 秒自然六目标 FAIL 因果 | 旧 73452a… 原件 FAIL 保留（第二轮 24/30）；S4 归因材料已补（88409ff34 冻结点，未一边改 DOT 一边归因）：当前 FAIL 与旧原件模式不同——归因拨开三层遮蔽后到达真实根因。①APPDATA 尾斜杠环境断言（S1 natural 同款适配，`natural_sustained_chain` L371）；②S1 遗留编译断裂：S1 在 `hc.ignite.v1` contract.capabilities 授予 `effects.layered_status` 后未同步 10 个 validation 模块声明（state_loan/mixed_delivery/sustained_chain/periodic 系编译全拒 `missing_trigger_permission`），已补齐声明（数据同步，零生产行为改动）并复验 state_loan/mixed_delivery(60s)/periodic_boundaries 三场景 PASS；③真实根因暴露：`_spawn_enemy` 30 次全返 null（targets=0，战斗未开始），与基类 `natural_effect_lifecycle` 的 "all thirty real receivers" 断言同源——该断言 S1 会话已在纯净基线（272430b36 三文件还原）定性 BASELINE_EXISTING，本轮以 S1 父版本（5fbac9797）与 HEAD（88409ff34）两轮受控实验复证一致（同 checks 同断言），且非 S3 scene_epoch 所致（HEAD 对照排除）。spawn 拒绝根因归 S5 归因清单精确项 | natural_sustained_chain + natural_effect_lifecycle + state_loan + mixed_delivery + periodic_boundaries（受控实验 5 轮） | 272430b36 | **FAIL（归因推进：遮蔽层已修，根因=spawn 拒绝既有项）** | S5 归因清单 |
| 9 | Windows 持续性能（P50/P95/P99、due 迟到、队列年龄） | 旧 V3/V4 FAIL 属第二树不同语义 source（不可比性维持）；新场景 `tests/framework/feature_residency_latency_distribution_test`（21 checks）：480 头满载 × 冷/热两轮同机自对照，4 秒采样窗逐帧记录帧间隔（cold p50=6160us/p95/p99=18533us；warm p50=7366us/p99=18025us）、每帧服务量（p95=20）、pending 队列年龄轨迹（facts 一秒内清空）与 due 延迟——**真实持续特征**：Budget 公平轮转下满载服务量子恰好=需求（2400/轮），due 波在窗口边界堆积（warm 实测最大延迟 4.48s，结构性有界上界 8s 内），与 trifold 的独占预算 1s 语义分开记档 | feature_residency_latency_distribution_test | 272430b36+ | **PASS（同机分布数据已记录；PRODUCT SLA 口径保持 OPEN 不设门槛）** | S6 前置数据 |
| 10 | P0-P6 总账与统一回归（critical 逐项单项） | 部分历史证据；总账待建 | S5 | 待 S5 冻结 | **NOT_RUN** | S5 |
| 11 | APK 构建（包名/版本/签名/内容闭包） | preset=Android/Gradle/arm64-v8a、`com.personal.mafaoffline`、version/code=82（**S6 改 ≥98**，旧包实测最高 97） | S6 实测 | 待冻结候选 | 前置核对 **PASS**（工具链全 HAVE，见 S0B_APK_PREREQ_20261006.md）；构建 **NOT_RUN** | release keystore MISSING（仅阻断 release 正式包）；debug 测试包不阻断 |
| 12 | 设备回测 | 无 | S7 | — | **NOT_RUN**（需用户授权） | 全部设备分项 |
| 13 | v97 B 角色背包故障 | 输入 MISSING | — | — | **MISSING**（输入），修复 NOT_RUN | 仅该故障自身；不阻断 APK 交付 |

## 原始失败保留（不删改）

- 旧 2-frame / 5-second startup FAIL：`evidence_20261006/runner_receipts/…100338/101046/101444/101523…`（exit 137）+ 云端 EVIDENCE_INDEX fixed_candidate 节。
- 迁移中间 FAIL（physics 观察点修正前的两次 input 断言失败）：…104521 / …104655。
- 历史 658/25 组合、V3/V4 性能、容量、save/teardown 六 FAIL、33 检查时效、B 任务全字典：按 FRAMEWORK_PROGRESS / USER_SCOPE_LEDGER 原记录保留。

## S1 期间固定的新增基线分类（2026-10-06）

- `feature_queue_retention_test`：当前 FAIL（18 checks/4 errors，510 retained ActorRef）；纯净基线
  （HEAD 三文件）对照同 FAIL（early_script_error×5 崩溃形态）→ **本树从未 PASS 的既有失败**
  （FAIL_CHANGED 形态，人工审查结论：与 S1 无因果），S5 统一归因。
- `natural_effect_lifecycle_test`：292 行 refreshed 期望已按裁决更新为 replaced；138 行 APPDATA
  尾斜杠环境合同已修；剩余 receivers 断言在纯净基线同 FAIL（early_script_error 崩溃形态）→
  **既有失败**，S5 归因。该测试每跑必在沙盒创建真实角色（重跑前需清 `.godot/runtime_appdata`）。

## 环境纪律（S0 复验结果）

- EntityRegistry 15 源文件原字节 SHA256：**15/15 匹配**（autocrlf 风险控制中；未来任何 checkout 后必须复验）。
- untracked `.uid`（301 个）：docs/review 证据伴生物，生产构建路径不含 docs/，不入 APK、不入库。
- 引擎哈希核对：`d8055fb8…`（= handoff Windows 基线）MATCH。
- 未提交改动禁止以 checkout 恢复覆盖；stash `af8bbdd1…` 永不 pop。
