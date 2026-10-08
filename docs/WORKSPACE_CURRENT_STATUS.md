# 当前主树与工作区

2026-10-08 13:47 UI核验：唯一路径、codex/integration和HEAD215f0b2f651a51e6855ee813ddd99221690311a1保持，混合dirty保留。UI触控与尺寸、仅两种超级药水、目标血条掩膜/完整底色/普通字体改动见docs/review/hud_touch_20261008/RESULT.md及VERIFICATION.json。6专项最新PASS，实际GPU预览正常退出0，截图待用户确认；没有新提交/push/APK/安装，DEVICE TEST: NOT_RUN。先前群怪/特装状态不因本轮局部验证变为整体验收。

2026-10-08 本轮群怪续接核验：当前Git工作树仅C:/Users/Administrator/Documents/HardCore，codex/integration，HEAD215f0b2f651a51e6855ee813ddd99221690311a1，混合dirty保留。phone-crowd-v106临时托管树（基线78d0775b4b22f40ad1f54426639d867310dae41a）已通过Codex可恢复归档；33份日志/receipt/结果及单独fixture在outputs/phone_crowd_local_20261008/v106，PRESERVED_FILE_HASHES.json记录字节保全。实际worktree list只剩主树，app artifact已转archived_worktree。没有沿共享联接删除素材、没有新commit/push/APK。

群怪源码/本地同条件CPU对比及最新AOE/投射物合同见docs/review/phone_crowd_20261008/LOCAL_COMPARISON.md和VERIFICATION.json；本候选DEVICE TEST: NOT_RUN，CPU结果不代表手机呈现帧率。旧日期条目继续保留为历史。

2026-10-08 01:24 续接核验：唯一路径/工作树仍C:/Users/Administrator/Documents/HardCore，codex/integration，HEAD215f0b2f651a51e6855ee813ddd99221690311a1。指定特殊装备及战士开关居中已实现，主界面目标血条文字几何PASS；各源码阶段专项结果与失败完整保存在docs/review/special_equipment_20261008/FINAL_RESULT.md及FINAL_RECEIPTS.json。不合并为全量验收；混合暂存/未暂存改动保留，无新提交/push/APK。音频/拾取证据复用；群怪留至今日手机演示。DEVICE TEST: NOT_RUN。

2026-10-07 23:32 续接：唯一主树仍为下述 integration，HEAD 215f0b2f651a51e6855ee813ddd99221690311a1，保留本轮混合暂存/未暂存源码与证据。音频、拾取、售价、概率、Loading专项已有PASS；当前入口 docs/audio/20261007/CURRENT_RESULT.md。群怪问题按最新指令放最后，由用户手机演示并同步监测数据；没有新APK/设备验收，没有新提交或push。

核验日期：2026-10-07（Asia/Shanghai）。当前 Git 和实际文件优先于历史报告。

- 唯一工程路径：`C:/Users/Administrator/Documents/HardCore`。
- 唯一施工基线：`codex/integration`，内容来自原第三树 `pluggable-framework-v2`。
- 第三树生产快照：`b3d144061b9b0aef419ce6b746ddc476023fd912`（父提交 `fedce38a379325005adb5d03db2db40eae231b92`）。已包含原 B01 未提交改动；历史 v97 状态不再代表当前源码。
- 原第二树、11 个已登记 Android 临时树已移出，原第三树旧路径已移除；本轮v106封装的4个隔离构建树也已保全日志/生成证据后移除；本次核验登记工作树只剩上述主入口。
- 外部独有编辑器工具、原始素材与文档已补入；冲突旧实现、人工数据和证据保全于 `outputs/retired/20261007/`。远端历史 SHA 与恢复入口见 `docs/retired/20261007/README.md`。
- 远端已只保留 `codex/integration` 并设为默认；195 个旧远端分支与 248 个旧本地分支引用已删除，8 个发布标签保留。全部旧提交仍可从新主树归档父链恢复，详见 `docs/retired/20261007/CLEANUP_VERIFICATION.json`。
- 共享 `dev_art_sources` 保持原位置、原字节；本地 Godot/Android 工具不入 Git。退役档案不参与 Godot 导入。
- 弃用 GLM、dots 及旧 CLI/MCP/队列流程；按根 `AGENTS.md` 和用户最新授权工作。

架构仍有未闭合工作；静态阅读覆盖、局部 headless PASS 和历史 v105 包不能作为当前全量验收。此次不构建或安装 APK，DEVICE TEST: NOT_RUN。

下一轮先运行 `tools/agent_bootstrap.ps1 -Compact`，查看当前分支/HEAD/dirty、`git worktree list --porcelain`，再从 `docs/retired/20261007/README.md` 与第三树保留的交接证据定位剩余任务。

迁移验证：bootstrap PASS；身份注册 15 源哈希 PASS，B01 24 检查 PASS/0 引擎错误。旧编辑器回归 48 PASS/13 FAIL/1 ERROR（历史素材/manifest 合同不兼容，未改正式素材）。首次 headless 资源导入完成但原生编辑器退出 FAIL（-1073741819），原日志保留；完整架构、APK和设备验收继续开放。

## v105反馈的继续施工

2026-10-07：怪物系统修复源码已固定于 `c8477058a0c2f67f7a9e39f3523f4ea7693bd5cd`（施工基线 `aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`）。用户已授权受击移动解锁、祖玛行动边界召唤、Boss基础主属性及群怪局部追击/包围简化。具体合同、基线及受测源码范围见 `docs/review/monster_system_20261007/FINDINGS.md` 与 `PROJECT_CURRENT_STATUS.md` 最新条目。相同最终内容指纹的18项原生功能回归PASS，v106已通过正式两遍封装及独立APK校验并交付桌面；构建源码78d0775b4b22f40ad1f54426639d867310dae41a，构建工具LF属性修复215f0b2f651a51e6855ee813ddd99221690311a1不改变运行内容。原生功能PASS不代替设备试玩，群怪流畅度按用户体感验收；不将旧迁移126检查或历史v105包作为本轮验收。

本轮构建清理及APK核验时间：2026-10-07T20:44:46.225750+08:00；证据见docs/review/monster_system_20261007/APK_DELIVERY.md与BUILD_STAGE_RETIREMENT.json。DEVICE TEST: NOT_RUN。
