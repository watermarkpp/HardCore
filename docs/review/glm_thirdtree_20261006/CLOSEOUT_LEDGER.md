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
| 7 | 资源发布真实交错（scene-change 即时失败、publisher 物理替换、闭包打包） | 【v2 口径拆分】①scene-change：`feature_resource_scene_change_failure_test`（9 checks PASS）实测的是 `get_tree().current_scene = successor` **赋值后的未决 prepare 取消**（首观察即失败/零残留/不发布/恢复健康）——**未覆盖**"真实 `change_scene_to_file/packed()` 调用立即失败"的原始要求，该子项 **OPEN**；②publisher 物理替换：combined 场景证据成立；③闭包打包：audio_closure 复验 PASS，但 **APK 实际包含并读取全部资源**的证据属 S6 出包后核验，未关闭；④资源回归 11 项 PASS；⑤terminal_failure=BASELINE_EXISTING（**普通 runner 判 FAIL 是正确行为，不修白名单**；负例证据走严格限定验证），code handoff×4=Windows ad-hoc APPDATA 结构性环境差异（Linux formal 断言） | feature_resource_scene_change_failure_test + 资源回归 11 项 | 272430b36+ | **部分 PASS**（①SceneTree 立即失败子项 OPEN；②③各有边界注记） | S5 归因清单 + S6 闭包核验 |
| 8 | 35 秒自然六目标 FAIL 因果 | 【2026-10-06 发布迁移后更新】spawn 拒绝根因已按"测试适配"路径修复：natural_effect_lifecycle 的 30 目标改走 `publish_targets` 一次发布（feature 绑定先于发布、player 前态发布后重捕获），30 目标真实出生/AI/伤害/死亡全链真实运行（23 次施法=动作锁上限、死亡 5→20/30、states 峰值 30）；期间发现并修复 S1 REGRESSION（effect_runtime replacement 路径 state_loan_handles 缺键崩溃，498680579）。瞄准实验 5 变体（v3 风筝/v4 密度/v5 两阶段/v6 声明几何）已证：23 accepted=CD 上限、busy=正常 CD 等待（受击假设否证）、数据 area_radius 115px 不驱动实际伤害分发。**剩余失败=测试瞄准几何 vs 生产交付几何（取证中）+ 90 并发/30 死亡双断言在同一伤害预算内的可达性（待 GPT Pro 裁决）**。旧 73452a… 原件 FAIL 保留（第二轮 24/30）；cadence 系（同链 spawn 拒绝）已 5/5 全部 PASS（FAILURES_FOR_GPT_PRO.md F1） | natural_sustained_chain + natural_effect_lifecycle + state_loan + mixed_delivery + periodic_boundaries | 272430b36 | **FAIL（自然验收未完成；spawn 前置阻断已解除，业务主体真实执行中；剩余归因见 FAILURES_FOR_GPT_PRO.md F3）** | 阻断自然验收；S5 修复序第 3/5 步 |
| 9 | Windows 持续性能（P50/P95/P99、due 迟到、队列年龄） | 旧 V3/V4 FAIL 属第二树不同语义 source（不可比性维持）；新场景 `tests/framework/feature_residency_latency_distribution_test`（21 checks）：480 头满载 × 冷/热两轮同机自对照，4 秒采样窗逐帧记录帧间隔（cold p50=6160us/p95/p99=18533us；warm p50=7366us/p99=18025us）、每帧服务量（p95=20）、pending 队列年龄轨迹（facts 一秒内清空）与 due 延迟——**真实持续特征**：Budget 公平轮转下满载服务量子恰好=需求（2400/轮），due 波在窗口边界堆积（warm 实测最大延迟 4.48s，结构性有界上界 8s 内），与 trifold 的独占预算 1s 语义分开记档。【v2 口径】**定性=测试驱动时钟下、周期 HP 接口被替代（ObservedEnemy 空 take_feature_periodic_damage）的结构性调度测量**——不证明自然 AI、真实周期 HP、正式 physics 时钟或整体游戏性能已通过；单窗口迟到 <8s 不是长期数学上界；4.48s 迟到值得调查但该夹具不足以归因真实游戏调度故障；"产品 SLA 未定"不移出自然 35 秒要求作为 S6 前置 | feature_residency_latency_distribution_test | 272430b36+ | **结构性测量 PASS（不代表自然性能验收；PRODUCT SLA 口径保持 OPEN 不设门槛）** | S6 前置数据（非充分条件） |
| 10 | P0-P6 总账与统一回归（critical 逐项单项） | S5 统一回归分批推进（critical 全量 683 项，`outputs/test_logs/source176_r3/critical_members.json` 为准；三树新增 5 场景已注册进 critical：`run_godot_tests.ps1` thirdtree_20261006 块，含成员数与磁盘存在性守卫）。**第一批 63 项完成**：57 PASS / 6 FAIL（spawn 拒绝同源）→ 六项修复各自提交后【2026-10-06 修复序 6 复跑取证：6/6 逐项单项重跑 PASS，runner JSON 落档（164526/164637/164712/164841/165000/165029 五个 cadence 场景 + skill_plan，pass_marker=True exit=0 全绿）】→ **第一批 63/63 PASS 收口**。第一批已覆盖本任务修改面全集（feature/resource/receipt/natural/cadence/source176_r3 formal）；**其余约 620 项与本任务修改无调用链关联**（death_revival/device_lab/enemy/equipment 等），按分层纪律不为保险预跑全项目；全量逐项回归是否执行属 S6 前最终统一回归决策（工作量 ~620×单项），提交 S5 收口评估 | s5_batch1_results.json + 复跑 runner_results 六件 | a67d68d6b+ | **第一批 63/63 PASS 收口；第二批起 NOT_RUN（范围决策待定）** | S5/S6 |
| 11 | APK 构建（包名/版本/签名/内容闭包） | 【2026-10-06 S6 构建完成（Round 19，按用户指令拆步执行）】冻结 SHA `be92f2775`：Preflight PASS → stage worktree（52420 文件 clean）→ gradle 模板解包+splash 补丁 PASS → build_info（Dirty:False）/versionCode 注入 98/wall bindings PASS → `--import`（DONE reimport、0 errors）→ `--export-debug`（中间问题现场解决两处：stage 缺 outputs\hardcore 目录；verify 期望 commit 需传完整 SHA）→ **ANDROID_APK_VERIFY_PASS**。产物 `outputs/hardcore/HardCore-v98-thirdtree-debug.apk`：size=489226256、SHA256=7DE06E12470420E90CEE437326A6568D4A985911387B7E7E7A3DBADD4ADC7FEF、aapt=**com.personal.mafaoffline / versionCode 98 / versionName 一致 / min24 target36 / HardCore / arm64-v8a**；签名证书 SHA-256 c62d0f82… 与 v97 同证书（**直接升级身份 PASS**）；内容探针（PAPER_DOLL/CASTER_SKILL_FRAME_IMPORTS=586 等）PASS。stage worktree 已清理 | verify_android_build.ps1 输出（ANDROID_APK_VERIFY_PASS） | be92f2775 | **构建 PASS** | release keystore MISSING 仅阻断 release 正式包；S7 设备回测 NOT_RUN（需用户授权） |
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
