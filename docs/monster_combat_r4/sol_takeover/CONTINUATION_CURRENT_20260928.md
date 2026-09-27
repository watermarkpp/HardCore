# 精确恢复点 2026-09-28

## 06:20 新恢复点（覆盖下方旧“当前活跃执行”）

- 主树当前源码与证据候选 `1b74e698728af725595118d0a30ab59c0f0ac58b`；用户 dirty `AGENTS.md` 和原始 untracked 保留。c917 全图正式传送扫描已闭环，67 图/132端点，9原生测试通过，山谷密道 A/B 两点修复；无需重扫或重新批量发布地图。
- 固定 BASE1381/CAND1b74、同字节原生连续600 tick 探针、相同正式输入，完成 small30、AoE+死亡+掉落30、large30+双召唤的各8份 full 样本，以及 large30+双召唤8份 frame_only 样本。32/32 实际收集 PASS；原始逐帧JSON/日志、源码身份和runner结果在四个 native_t6_*_1b74 目录。新 `PERFORMANCE_1B74_REVIEW.md` 判定：桌面严重长帧目标PASS，但CPU与召唤场景小幅P99并非全改善；GPU和手机NOT_RUN。旧e367 FAIL保留为历史，不冒用。
- 下一步精确stage本轮证据与说明并本地提交；然后在新的干净固定检出运行正式548项完整回归，核对最终退出、实际集合、原始日志。既有 e367 独立检出保留为历史，不改它。完整门禁通过后才实际集成7提交锻造链、完成其RED/GREEN及最终全套验证、正常push，逐树审查后安全退休。**仍停在APK之前**。

唯一工程主控、串行执行。主目录 C:/Users/Administrator/Documents/HardCore，codex/integration 已有 docs/evidence-only 提交 bc55d71ff6bd05f2f664af6d581e0bec57074be0；功能源码仍为 e367150b0c46c040e67b4ebd1b750ccd1ff5a536。后续 docs-only 提交以实际 `git rev-parse HEAD` 为准。用户dirty AGENTS.md与原始untracked保持，禁止add-all/清理/重置。

## 当前活跃执行

### 最新恢复点（原04:17执行已结束，不得按下方旧段重跑）

- 52922 已结束：e367 独立完整回归 546 实际项，545 PASS / 1 FAIL；exact_execution_check.json collection PASS / acceptance FAIL，无集合/源码漂移。唯一失败为缺少 ignored 资源扫描清单。1638 测试原始日志与导入/包装器日志全部已入库并保留原始字节。
- 18f71f608fe99a6f770dcab08d0f8b4da4043533：portable catalog fixture 与原断言/来源 SHA，目标测试实际 GREEN。dd7c9655faeef1b79ae59a1f6d85bc1bbc3490066：全部原始日志保存。10de9f4feda5797707b4544879c49c396c8146d9：原生连续tick探针及真实慢帧反例、两有效负载 smoke，均 GREEN；首轮测试类型/API错误原始 FAIL 保留。
- 本次 F03 新闭环：公开 warehouse direct deposit/withdraw 旧PROMOTE未ACK时的实际物品归属反例原生 RED（正常退出1/0引擎错误）；仅两处 batch 入口加既有 before-state barrier；同一四格 GREEN、9项相关回归 GREEN。见 warehouse_receipt_regression_55f_20260928_0552/CLOSURE.md 与 scoped_closure_receipt.json。不是新存档格式或自动存档频率修改。
- 新 formal critical 注册共548（原546 + native sampler + warehouse receipt）。最终该源码 full/clean 尚 NOT_RUN；不能把先前e367完整回归冒用为新源码完整通过。
- 当前没有活跃 Godot；下一步先重新保护/同步 BASE 三项 overlay，核对共同字节与 BASE1381生产未变，随后在固定提交执行真实 AA2 + AB/BA/AB3 性能矩阵。旧性能接纳 FAIL 仍保留，不能以 sampler 修复直接关闭CPU警告。
- 主树 AGENTS 和原始 untracked 仍保持；未push、未实际merge锻造、未删除树、未APK。退休 inventory37GB仅为只读候选清单，需另行保存/哈希必要ignored内容。

- exec session **52922**：独立目录 C:/Users/Administrator/.codex/worktrees/r4-clean-verification/HardCore 固定e367，`tools/run_godot_tests.ps1 -Suite critical -TimeoutSeconds 30`，重R4沿现有60s规则。
- evidence/critical_clean_e367：正式headless import正常退出且无错误；expected_paths.json实际546；identity.json含源码tree/runner/engine/用户目录/导入后状态。
- 日志和用户数据独立；等completion.json、实际正常退出、精确集合546、全部原始stdout/stderr/Godot及引擎错误核对。不能因中间PASS宣布完成。
- 此目录源文件/Git/用户数据在执行结束前禁止修改；不要并行启动性能测量。
- 完成后使用 evidence/verify_full_critical.py 验证实际546集合/次序/正常退出/原始日志/固定源码及工作目录。其未完成拒绝分支已实际执行，返回NOT_RUN且未写裁定；完整 verifier 尚未运行，不能记PASS。

## 05:00 本地待验证变更（尚未提交）

- 当前主树 HEAD 为 docs-only `55f32c34728eae0407bc3654b5c8f9ad339bc0ac`。生产源码/素材仍 e367，独立完整回归继续固定 e367；本地测试改动不能冒用它的结果。
- 旧 quiet_full_aoe_e367_20260928_0410 八份流水，经新 verify_native_physics_cadence.py 实际验证全部 FAIL：600 条记录跨越约618–674原生物理tick，signal后再等process的旧探针跳过catch-up tick。原CPU警告保留，尚未证明这就是唯一根因。
- t6_real_load_probe 改用最高末位优先级测试节点逐次观察原生physics回调，另记有界process间隔；native_physics_sampling_test 增加真实50ms idle阻塞反例，pairs/summary工具要求600连续tick。生产actor时钟/频率/代码未改；PowerShell/Python静态解析PASS，原生Godot NOT_RUN，等当前完整回归结束后执行。
- 当前完整回归实际 FAIL：complete_client_resource_catalog_test 缺少 ignored outputs/resource_catalog/.../manifest.json。未跳过或削弱断言，独立检出保持不动。新 exporter 从既有正式manifest及只读SQLite逐122行/962251帧/332460候选核验后导出同字节测试fixture，实际出口PASS；新portable fixture测试原生Godot NOT_RUN。不重新搜索头盔或重建任何美术。
- 本地新增/修改路径仅上述 tests/tools 与原始证据。原dirty AGENTS、untracked素材/工具/UID保持；这些新增路径须精确stage，禁止add-all。
- 新增 f03_warehouse_receipt_boundary_test.gd/.tscn，四格真实IO候选反例（deposit/withdraw × direct/prepared），先让旧拾取真正PROMOTE且未主线程ACK，再调用公开存取路径，检查金币、唯一实例、live/disk一致。源码显示 deposit/withdraw 批量入口在副本前缺 `_before_state_transaction`；底层同步写才 drain 可能太迟。当前只补测试，未动生产；原生RED/GREEN均 NOT_RUN，等当前full结束。与后续锻造四入口缺barrier是同类，但不能用此替代各自真实证明。
- retirement_intake_bc55/inventory_needed_ignored.py 完成23树限定目录只读清单，v2还检查每层祖先联接，82658文件约37.2GB、0读取错误；不读文件内容、不沿联接、不扫描导入/Gradle中间缓存，未backup/删除。v1原始清单保留；主树本身27.6GB包含历史备份且不在退休范围，其他树约7.9GB需后续保留/哈希。清单不代表清理许可。
- prepare_native_sampler_overlay.py 已实际保护并替换 BASE 的三项测试文件（probe/scene/runner），D:/HardCoreAudit/native-sampler-overlay-before-20260928-0525 保留原始字节及两个index/working patch；BASE HEAD1381不变、生产diff为空、共同字节PASS。后续若修改probe/runner，必须重新核对双方共同哈希；不能直接运行已有陈旧身份矩阵。
- native clean full 已完成四个20起手：24/238各20扣血；76为19扣血+真实release13→child14 mixed_magic_evaded；239为18扣血+真实release11→child12、release15→child16 mixed_magic_evaded。24射程外追击1次实际自然起手/扣血保持。五份原始报告复制到 critical_clean_e367/natural，哈希和零扣血逐release原因见receipt.json；这不替代整个546集合的最终正常退出核验。

## 已完成

- c9172af201831b9401f5cfcda1aa31804dc41178：67地图132端点，A/B两条作者出口角色修复，CLI正式发布补共享派生墙绑定；9定向测试PASS、64其他地图/57墙计划/390PNG不变。用户最新全图传送请求已本地关闭。
- e367：真实Boss默认魔闪合法miss反例、旧成功命中夹具采样前明确设置真实防御，6相关PASS；原full542的539PASS/3FAIL原始日志完整保留，三个失败有定向闭环。正式注册当前546。
- 本轮24 full +24 quiet frame +8 quiet full AoE有效样本；严重尾部改善，CPU仍不利，**性能接纳FAIL**。PERFORMANCE_E367_REVIEW.md及phase_cost_review.json是当前裁定，不沿旧台账假设全绿。
- protection_locked.json：13611保护对象、229dirty备份、4152存档备份核验PASS；19授权变化/0未知/用户AGENTS未变。13地图变化锁到c917blob与首次实际PASS原始SHA。
- 清理前23工作目录只读 inventory、bfe90有效变更逐项主树保留核对和86331弃用自制雷电边界见 retirement_intake_bc55/；两条 create-only 本地保护引用实际回读。尚未退休任何目录，未提交/ignored内容仍须保护。
- 计时窗口重置假设未得到证据：RuntimeDiagnostics仅初始化字段，不自动周期清零；T6采样前明确reset一次，DeviceLab只在显式开始/命令时reset。不能据此实施猜测修复或把CPU警告关闭。

## 顺序与边界

1. 等当前546完整独立回归并逐FAIL裁定。继续性能源码/真实负载归因，不用加大AA噪声覆盖警告。
2. R4门禁通过后完整7提交锻造DA41实际合入，不能只摘tip；已发现四公共写入口缺F03 barrier、relic/badge严格身份和同ID失效风险、正式NPC单目标发布、19正式测试注册等，见forge_intake_c046/REVIEW.md。
3. 最后锻造源码相关/full/clean/有效输入性能/保护；正常push核对远端；逐树确认独有内容/dirty/存档/素材/证据后安全退休。
4. **停在APK之前**。不构建、不安装、不hotpatch、不改版本。当前远端integration仍f5d6308f53162509bffd30f6981987cbfe80fa68，尚未push/锻造实际merge/删除工作树。

旧CONTINUATION_C046是历史现场，旧活跃session已结束，不按它重跑或恢复。
