# 精确恢复点 2026-09-28

唯一工程主控、串行执行。主目录 C:/Users/Administrator/Documents/HardCore，codex/integration 已有 docs/evidence-only 提交 bc55d71ff6bd05f2f664af6d581e0bec57074be0；功能源码仍为 e367150b0c46c040e67b4ebd1b750ccd1ff5a536。后续 docs-only 提交以实际 `git rev-parse HEAD` 为准。用户dirty AGENTS.md与原始untracked保持，禁止add-all/清理/重置。

## 当前活跃执行

- exec session **52922**：独立目录 C:/Users/Administrator/.codex/worktrees/r4-clean-verification/HardCore 固定e367，`tools/run_godot_tests.ps1 -Suite critical -TimeoutSeconds 30`，重R4沿现有60s规则。
- evidence/critical_clean_e367：正式headless import正常退出且无错误；expected_paths.json实际546；identity.json含源码tree/runner/engine/用户目录/导入后状态。
- 日志和用户数据独立；等completion.json、实际正常退出、精确集合546、全部原始stdout/stderr/Godot及引擎错误核对。不能因中间PASS宣布完成。
- 此目录源文件/Git/用户数据在执行结束前禁止修改；不要并行启动性能测量。
- 完成后使用 evidence/verify_full_critical.py 验证实际546集合/次序/正常退出/原始日志/固定源码及工作目录。其未完成拒绝分支已实际执行，返回NOT_RUN且未写裁定；完整 verifier 尚未运行，不能记PASS。

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
