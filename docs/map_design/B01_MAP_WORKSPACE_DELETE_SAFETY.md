# B01 map workspace deletion safety

审计基线：`c97a08b43832b174f98de31f5ed6673ccda344ae`；专项分支：`codex/audit-map-safety-20260905`；日期：2026-09-05。

## 根因与边界

旧的 `MapEditorSaveService.delete_workspace_map(map_id)` 只检查空 ID，并以字符串前缀判断 `res://map_editor_workspace/<map_id>/` 是否在工作区内，再递归删除目录。因此 `.` 可以解析为工作区根，`prefix` 与 `prefix_neighbor` 也没有目录身份绑定；调用者没有把待删除目录、文档和文档内身份作为同一对象验证。

本次只改地图编辑器删除相关域：保存服务、模板目录服务，以及删除确认/结果文案。没有改地图数据、资产、几何、发布 registry、全局存档或测试 runner；生产默认工作区仍为 `res://map_editor_workspace/`，现有合法编辑地图的保存/列举路径不变。

## B01 删除合同

`MapEditorPathSafety` 对 map ID 执行单一 ASCII 身份组件校验：首字符为字母或数字，其余只允许字母、数字、`_`、`-`；空白、`.`、`..`、斜线和反斜线均拒绝。路径统一斜线并 `simplify_path()` 后转为绝对路径；目标必须是工作区根的直接子目录，根本身、嵌套路径和前缀邻居均不能通过 lexical scope 检查。

删除计划还必须证明：

* 目标目录及 `<map_id>/<map_id>.editor.json` 存在，且二者不是链接/reparse point；
* 可选的 expected document path 与实际文档路径一致；expected document 的 `map_id`/`path` 与操作一致；
* 实际 JSON 的 `map_id` 与目录身份一致，`editor_meta.workspace` 与目录绝对路径一致；
* formal identity registry、runtime release registry、冻结/锁定/正式/发布/已实现字段命中的地图 fail closed；非 `custom_empty_map` 也不视为用户可删除地图；
* 目标树的每一层都用 Godot `DirAccess.is_link()` 检查，任一可观测的 symlink、directory junction 或其他 reparse point 都拒绝。

Godot 能证明的是运行时 `DirAccess.is_link()` 的 reparse-point 探针边界；它不是完整的并发 TOCTOU 防护，也不宣称解析所有平台文件系统语义。正式删除前会再次扫描目标树和 recovery 根，然后只做一次同文件系统目录 rename。

## 可恢复方案

删除不是递归 `remove`。`delete_map_authoring_transaction()` 先完成 map ID、formal/frozen、模板双 ID、文档路径/身份和 workspace 计划；随后将整个目标目录移动到同一工作区下的 `.recycle_bin/<map_id>.deleted-<ticks>`，只有移动成功才提交模板目录。模板提交失败时恢复 catalog 快照并把 workspace rename 回原目标；任一回滚失败都返回失败，不报告 partial success。移动失败不会清理目标；recovery 根由本次操作创建时若为空也会回收。恢复只需将返回的目录 rename 回原目标路径，因此测试也验证了完整树和隐藏文件可恢复。

事务失败结果有明确三态，UI 只按该状态提示：`not_started` 表示尚未移动工作区或提交模板，`rolled_back` 表示模板和工作区均已完整恢复，`rollback_incomplete` 表示至少一个回滚步骤失败。后者始终返回 `recovery_path`/`recovery_root_path`、原目标路径、模板 catalog 路径和错误数组；工作区未恢复时，回收目录仍保留且可用 `restore_workspace_map()` 复原。UI 不再把不完整回滚说成“原状保留”，而是显示保留位置与错误。

`.recycle_bin` 是工作区内部的可恢复隔离区，不使用系统回收站；系统回收站可能被禁用且不适合作为项目级事务边界。生产清理策略不在本 B01 范围内。

## R01 只读核查

审计包原文只把 journal/单一发布指针列为 R01 的候选改造，并要求未来验证进程 kill 后的恢复；没有把本 B01 回合实施持久 journal 写成已授权/必做项。`MapEditorBuildRuntimeService` 当前的 publish helpers 使用 `.tmp`/`.bak` 和同进程内的 promote/restore 回滚；现有 `publish_failure_rollback_test` 覆盖的是注入失败后的即时回滚。针对进程 kill、重启后恢复，没有发现持久 journal 或启动恢复证据，因此 R01 状态记录为 **UNVERIFIED risk**；本次未进行大重构，也没有把同步 rollback 宣称为崩溃恢复。

## 专项验证

测试只把 workspace 与 blank-template catalog 指向 runner 独立的 `user://` 临时位置，绝不对真实地图执行删除。覆盖：`.`/`..`、斜线/反斜线、prefix neighbor、文档/身份/路径错配、formal/frozen 保护、formal/runtime registry 缺失 fail-closed、formal 模板零写入、workspace 计划失败零写入、catalog 提交失败后的 workspace/catalog 恢复、无 workspace 的 blank template 兼容、合法单 target、失败无变化、可行时 symlink/junction/reparse-point 隔离，以及 quarantine 恢复。

```powershell
git add tests/map_editor_workspace_delete_safety_test.tscn
& .\tools\run_godot_tests.ps1 -TestPaths @('tests/map_editor_workspace_delete_safety_test.tscn') -TimeoutSeconds 30
```

若当前 Windows 权限/开发者模式不允许 `DirAccess.create_link()`，链接分支只记录 `B01_LINK_TEST=SKIPPED`，不把“无法创建测试链接”伪装成运行时已验证；Godot 的 `is_link()` 边界仍由正式代码执行。
