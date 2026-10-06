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
| 3 | 同种 DOT 完整替换（new_due=施加时刻+新period、expiry=施加时刻+全新期限、新 source/credit/lease） | 未实现：`scripts/features/runtime/effect_runtime.gd` `_apply_command` 仍取更大伤害/更晚到期/保留旧周期 | 待 S1 新反例（RED） | 272430b36 | **NOT_RUN**（S1） | S1/S2/S4 组合 |
| 4 | 认证 species / 独立层权限（default-off，接受时冻结） | 未实现（无层权限编译产物） | 待 S1 | 272430b36 | **NOT_RUN**（S1） | S1/S2 |
| 5 | 出生闭包（完整 base 计划 + SummonQueue 真 ordinal） | 已有生产实现 + 局部 PASS（birth direct 11 场） | published_world_birth_guard 等 11 场 | 272430b36 | 局部 **PASS**；完整组合与 retire 尾部记账待 S2 收口 | S2 |
| 6 | 容量三份证明（同时驻留/累计合法工作/可服务时效） | 历史 FAIL 保留（pending8192 消费权、AOE 3 目标 2 项旧记录） | 待 S2 新组合 | 272430b36 | **FAIL（历史，保留）** / S2 待做 | S2/S6 判定 |
| 7 | 资源发布真实交错（scene-change 即时失败、publisher 物理替换、闭包打包） | 部分已有；scene-change 即时失败 MISSING | 待 S3 | 272430b36 | **NOT_RUN/MISSING（S3）** | S3/S5/S6 内容闭包 |
| 8 | 35 秒自然六目标 FAIL 因果 | 旧 73452a… 原件 FAIL 保留（第二轮 24/30） | 归因材料 S4 补 | 73452a…（原件，不改写） | **FAIL（旧合同原件）**；S4 因果 NOT_RUN | S4；不得一边改 DOT 一边归因 |
| 9 | Windows 持续性能（P50/P95/P99、due 迟到、队列年龄） | 旧 V3/V4 FAIL 属第二树不同语义 source | 待 S4 同机对照 | 待 S4 冻结 | **OPEN** | S4 |
| 10 | P0-P6 总账与统一回归（critical 逐项单项） | 部分历史证据；总账待建 | S5 | 待 S5 冻结 | **NOT_RUN** | S5 |
| 11 | APK 构建（包名/版本/签名/内容闭包） | preset=Android/Gradle/arm64-v8a、`com.personal.mafaoffline`、version/code=82（**S6 改 ≥98**，旧包实测最高 97） | S6 实测 | 待冻结候选 | 前置核对 **PASS**（工具链全 HAVE，见 S0B_APK_PREREQ_20261006.md）；构建 **NOT_RUN** | release keystore MISSING（仅阻断 release 正式包）；debug 测试包不阻断 |
| 12 | 设备回测 | 无 | S7 | — | **NOT_RUN**（需用户授权） | 全部设备分项 |
| 13 | v97 B 角色背包故障 | 输入 MISSING | — | — | **MISSING**（输入），修复 NOT_RUN | 仅该故障自身；不阻断 APK 交付 |

## 原始失败保留（不删改）

- 旧 2-frame / 5-second startup FAIL：`evidence_20261006/runner_receipts/…100338/101046/101444/101523…`（exit 137）+ 云端 EVIDENCE_INDEX fixed_candidate 节。
- 迁移中间 FAIL（physics 观察点修正前的两次 input 断言失败）：…104521 / …104655。
- 历史 658/25 组合、V3/V4 性能、容量、save/teardown 六 FAIL、33 检查时效、B 任务全字典：按 FRAMEWORK_PROGRESS / USER_SCOPE_LEDGER 原记录保留。

## 环境纪律（S0 复验结果）

- EntityRegistry 15 源文件原字节 SHA256：**15/15 匹配**（autocrlf 风险控制中；未来任何 checkout 后必须复验）。
- untracked `.uid`（301 个）：docs/review 证据伴生物，生产构建路径不含 docs/，不入 APK、不入库。
- 引擎哈希核对：`d8055fb8…`（= handoff Windows 基线）MATCH。
- 未提交改动禁止以 checkout 恢复覆盖；stash `af8bbdd1…` 永不 pop。
