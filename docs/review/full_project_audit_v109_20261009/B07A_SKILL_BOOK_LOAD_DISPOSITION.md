# B07A-GD-005 / GD-006 — GameData skill-book load rejection

固定审查基线为 `b09ac5c2c41517ed516f11b91d09e435813465f2`。当前 `scripts/game_data.gd` 的 LF 归一化 SHA256 为 `56F77940DC2994BCCEE1257EF3E1AFF21016D6B68BA0844755071BAE60CCDD8A`。

## 修复

- `_build_skill_book_index()` 改为返回 `bool`，所有拒绝分支都写入稳定 `load_error` 码并返回 `false`（含重复目标专用的 `skill_book_index_duplicate_target`）。
- `_build_item_catalog()` 复用该失败信号。
- `_build_indexes()` 在目录构建失败时清理已构建的目录、价格和物品索引，拒绝发布半成品并返回 `false`。
- `load_database()` 开始时清除 `_initial_load_complete`。这样 `runtime_service_facade.gd:set_expansion_enabled` 与 `game_mode_service.gd:apply_mode` 直接重载失败时，旧的成功状态不会继续被 `is_loaded()` 报告。
- 成功路径仍在完整索引、掉落规则准备完成后才设置 loaded 并发出 `database_reloaded`。

## 独立回归

`tests/framework/skill_book_load_rejection_20261010_test.gd` 先显式调用现有 `ContentLayers.ensure_loaded()` 与 `GameData.ensure_loaded()` 建立组件目录 READY 前提，再用 detached `GameData` 实例和组件 READY 目录的深复制 fixture 调用真实 `_build_indexes()`／`_build_skill_book_index()`。覆盖完整索引、运行时导入器对未知目标的安全降级、直接可用未知目标的关系拒绝、重复目标、缺失目标、装备授予技能误绑定、目录投影清理，并在临时内存 merged input 上验证直接重载失败清除 loaded 状态且不发布 `database_reloaded`。它不会写入正式 authority；直接重载负例只暂时切换内存 loaded 标志，并在正式重载前恢复。本专项不宣称完整世界、传送或 UI READY；这些仍由 B01 独立证据覆盖。

相关消费链回归也已补入 `tests/framework/skill_book_identity_test.gd`：它保留原有真实学习、背包消费、存档失败回滚和身份查询断言，并按正式技能注册表与装备授予技能闭包区分“必须有书”和“明确无书”。

主控已执行组件专项 native55：64 项检查 PASS、原生退出 0、日志无错误。相关学习/消耗专项复用 native54 的 58 项 clean PASS；该相关源码和生产 GameData 未变。native53 两项 FAIL、native54 直接专项 FAIL 均原样保留。具体每阶段冻结指纹、完整检查和原生结果见 `B07A_FINAL_EVIDENCE_LEDGER.json`。发布时仅删除直接专项文件多余空白 EOF，没有改断言或业务语句，原始受测字节仍由 native55 冻结清单保留；不因此重复执行无变化的业务测试。

## 边界

扩展和模式调用者目前仍忽略 `load_database()` 的返回值。此修复保证状态所有者 fail-closed；调用者如何向界面或模式切换报告失败，需要主控另行决定，当前未引入第二套状态权威。
