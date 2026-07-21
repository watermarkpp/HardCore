# PROJECT-OPTIMIZATION-1：项目瘦身与工具归档报告

日期：2026-07-15

## 结论

旧的独立游戏工程已确认位于 `C:/Users/Administrator/Documents/Codex/2026-06-28/xian/work/legend176_game`；此前误查了 `Documents/My Games`，后者仅包含 Borderlands 4 和 Grim Dawn。

本轮采取保守瘦身策略：只删除可证明为临时生成物的扫描 smoke 目录和 Python `__pycache__`，不删除客户端/服务端原始证据、地图编辑器工作区及回滚备份、正式验收产物或 Godot/地图/WIL/WZL 工具。

旧工程逐项对照结果：旧工程 20,622 个文件中，正式输出 44 个文件与当前项目逐一 SHA-256 相同；地图编辑器工作区 518 个文件、旧版端资料和源码工具均已在当前项目中存在。没有发现尚未迁移的可用游戏文件。旧工程的 `.godot`、`.tmp_asset_inspect` 和重复 `outputs` 已安全删除。

## 已清理

- `outputs/resource_catalog/` 下 6 组 smoke 扫描结果；正式 58 端全量档案保留。
- `tools/`、`tests/` 及其子目录中的 Python `__pycache__`。
- 清理规则固化在 `tools/project_maintenance.py`，以后可使用 `--clean` 重复执行；工具只允许清理上述白名单。

## 保留边界

- `dev_art_sources/`：14,595,954,010 字节的客户端、服务端、源码和资源原始证据库，不能删除，否则会破坏 58 端全量验收的可追溯性。
- `map_editor_workspace/`：比奇地图版本、手工工作区、自动备份和交付回滚目录仍被地图编辑器工具或文档引用。
- `tools/godot-4.7/`、`tools/map_editor/`、`tools/map_assets/`、`tools/vendor/`：项目专用运行、地图生产、资源解码和导入工具。
- `outputs/legend176/`：历史 APK 与签名文件仍被施工记录、Android 验收和构建校验引用，暂不删除。

## 固化工具

`tools/project_maintenance.py` 提供项目目录审计、体积统计和安全清理；审计结果写入 `outputs/validation/project_maintenance_audit.json`。工具明确禁止触碰原始资料、地图编辑器备份和正式验收产物。

## 后续规则

新增资料必须先归入 `dev_art_sources/` 的明确客户端/服务端端档案，新增工具必须放入 `tools/` 对应子目录并写入项目目录；临时扫描、缓存和中间产物不得进入正式验收目录。

## 2026-07-15追加清理

- 删除`outputs/device`、`outputs/test`、`outputs/test_logs`及旧构建临时输出。
- 删除7组过期APK/签名与旧下划线命名debug包，只保留当前`MafaOffline_Bich_Map3_v35-debug.apk`、对应签名及release包；本批释放约1.385 GB。
- 删除`outputs`下1,767个无效Godot`.import`旁车并用`.gdignore`阻止重新生成。
- 最终运行`project_maintenance.py --clean`删除Python缓存和回归日志；复核`safeCleanupCandidates`为空。
- 当前`.godot`是隔离非资源目录后重建并通过压力测试的稳定缓存，不作为冗余删除；整库删除会触发已知高风险的首次全量导入。
