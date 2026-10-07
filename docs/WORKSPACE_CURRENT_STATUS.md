# 当前主树与工作区

核验日期：2026-10-07（Asia/Shanghai）。当前 Git 和实际文件优先于历史报告。

- 唯一工程路径：`C:/Users/Administrator/Documents/HardCore`。
- 唯一施工基线：`codex/integration`，内容来自原第三树 `pluggable-framework-v2`。
- 第三树生产快照：`b3d144061b9b0aef419ce6b746ddc476023fd912`（父提交 `fedce38a379325005adb5d03db2db40eae231b92`）。已包含原 B01 未提交改动；历史 v97 状态不再代表当前源码。
- 原第二树、11 个已登记 Android 临时树已移出，原第三树旧路径已移除；登记工作树只剩上述主入口。
- 外部独有编辑器工具、原始素材与文档已补入；冲突旧实现、人工数据和证据保全于 `outputs/retired/20261007/`。远端历史 SHA 与恢复入口见 `docs/retired/20261007/README.md`。
- 远端已只保留 `codex/integration` 并设为默认；195 个旧远端分支与 248 个旧本地分支引用已删除，8 个发布标签保留。全部旧提交仍可从新主树归档父链恢复，详见 `docs/retired/20261007/CLEANUP_VERIFICATION.json`。
- 共享 `dev_art_sources` 保持原位置、原字节；本地 Godot/Android 工具不入 Git。退役档案不参与 Godot 导入。
- 弃用 GLM、dots 及旧 CLI/MCP/队列流程；按根 `AGENTS.md` 和用户最新授权工作。

架构仍有未闭合工作；静态阅读覆盖、局部 headless PASS 和历史 v105 包不能作为当前全量验收。此次不构建或安装 APK，DEVICE TEST: NOT_RUN。

下一轮先运行 `tools/agent_bootstrap.ps1 -Compact`，查看当前分支/HEAD/dirty、`git worktree list --porcelain`，再从 `docs/retired/20261007/README.md` 与第三树保留的交接证据定位剩余任务。

迁移验证：bootstrap PASS；身份注册 15 源哈希 PASS，B01 24 检查 PASS/0 引擎错误。旧编辑器回归 48 PASS/13 FAIL/1 ERROR（历史素材/manifest 合同不兼容，未改正式素材）。首次 headless 资源导入完成但原生编辑器退出 FAIL（-1073741819），原日志保留；完整架构、APK和设备验收继续开放。
