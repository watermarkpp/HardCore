# HardCore UI R5 施工报告（R1 收尾与临时集成验证修订版）

- 任务：UI R5-R1 小范围收尾与临时集成验证（迁移菜单测试 / 补最终审计 / 临时集成验证 / 关键边界与报告纠错 / 交付）
- 约束遵守：保留现有 R5 实现，未重写核心模块；未重复应用原施工包覆盖补充修订；未直接合并主树、未改版本号、未构建或分发 APK。
- 交付格式按 AGENTS.md：修改文件、测试命令与结果、新增/变更稳定 ID、integration 接入点、提交哈希（见 §九）。

## 〇 版本链与关键 SHA

| 对象 | SHA | 说明 |
| --- | --- | --- |
| R5 集成基线 | `c91781bd` | `origin/codex/integration` 顶部（R5 施工起点） |
| R5 集成提交 | `4004874f04cd0d72744567faef41ea9149d0f4c4` | 34 文件，已推送 origin |
| R1 修订提交 | `f9716ac1`（完整 SHA 见 §九） | 菜单测试迁移 + 边界增强 + 无空间分支证据，已推送 origin |
| 主树（验证时刻） | `92c3f753a0b22a248e6e4a6e906cfae5ac4b793a` | 本轮核实为 `c91781bd` 直接子提交、5 文件改动、未推送 |
| 主树（本轮会话期间被 m30-r3-integration 任务推进） | `7db453a1` → `112090af` → `8dd1d092`（分支 `codex/m30-r3-integration`） | 其合并说明明确"UI warehouse fix 92c3f753 preserved"；本报告 A/B 运行绑定的精确 SHA 见 §五 |
| 临时集成结果 | `0b25e1e0`（完整 SHA 见 §九） | 本地临时树合并提交，未推送；工作树保留在 `HardCore-worktrees\ui-r5-tmp-integration-20260910` 供最终审查 |

祖先关系核实（本轮实测）：`92c3f753` 为 `c91781bd` 直接子提交（`merge-base --is-ancestor` = True，无分叉）；R5 分支与主树在 `c91781bd` 处分叉；临时集成将 `f9716ac1` 合入 `92c3f753`，merge-base 同为 `c91781bd`。

## 一 菜单测试迁移（system_menu_gothic_ui_test）

**纠错声明**：此前报告称该测试的失败是"第一个旧主题断言的预存失败，与 R5 无关"，以此为概括跳过后续断言——该结论作废。实际核查：该测试后半段存在多处依赖已退役节点的断言（CheckButton 音量开关、MusicFrame/SFXFrame、"已开启/已关闭"文案、旧关闭保存断言），必须逐条迁移。本次已全部迁移并通过，未跳过任何后半段断言。

### 断言迁移表（旧要求 → 新要求 → 用户依据）

| 旧断言 | 新断言 | 用户依据 |
| --- | --- | --- |
| `menu.music_toggle` 为 `CheckButton` 且可切换（已开启/已关闭） | `MusicVolume`/`SFXVolume` 设置行（356×96、行距 112）内各含 `HSlider`：0–100、step=1、`scrollable=false`，`setting_id` 元数据为 `audio.music.volume`/`audio.sfx.volume` | 用户已退役音乐/音效 CheckButton，改为真实音量滑块；docs/01 §三 音量事件契约 |
| `MusicFrame`/`SFXFrame` Frame 节点存在 | `Caption` 文本"音乐音量"/"音效音量" + `Percent` 标签与滑块右缘对齐 + `VolumeSaveNote` 关闭保存提示存在 | docs/01 §三（设置行结构）与 v2 契约 |
| 开关切换发 `ui.audio.setting.v1`（`enabled` 布尔）事件 | 滑块 `value_changed` 发 `ui.audio.setting.v2`（channel=`music`/`sfx`，value=0–1 浮点）：滑块置 31 → 请求 contract/channel/value=0.31 一次 | 用户指定 v2 音量事件契约 |
| `set_audio_settings(true, true)` 检查开关状态 | `set_audio_settings(true,true)` → 两滑块值 100、`Percent` 文本"100%"（旧开关联动适配层保留为布尔→滑块映射） | docs/01 §三 适配层要求 |
| 首按钮为 GothicSystemMenuGemButton | 保留，且断言 `not toggle_mode and not button_pressed`（迁移自旧开关断言）；设置页返回钮 variation 断言迁移为 `GothicSystemSettingsBackGemButton` 且 `not toggle_mode` | 用户退役开关按钮、保留宝石按钮视觉规范 |
| （无） | **新增实际菜单关闭保存接线测试**：覆盖 `AudioPreferences.storage_path` 至测试目录 → 滑块 55/66 → 预览态 dirty 且文件不存在 → `menu.close_menu()` → dirty 清除、文件真实写出 → `ConfigFile` 读回 `meta/version=2`、`audio/music_volume=0.55`、`audio/sfx_volume=0.66` → 全新 `AudioPreferences` 实例从同路径加载同值 → `open_menu()` 滑块回显 → `storage_path` 还原。**不是**直接调用 `AudioPreferences.flush` | 用户明确要求"补实际菜单关闭保存接线测试，而不只直接调用 AudioPreferences.flush" |
| （无） | v1 兼容单独验证：`game_root.gd` 的 `_on_system_menu_audio_setting_changed` 处理器以 `Node2D.new()+set_script` 独立实例接入信号，v1 开关事件 → 音量 0/1 映射，且 v1 音乐关闭不动音效音量（先采样后比对）；不要求旧开关节点复活 | 用户要求"旧 v1 兼容单独验证，不要求旧开关节点复活" |

保留未动的断言：暂停时可操作（PROCESS_MODE_WHEN_PAUSED）、居中（±1px）、触控区域 ≥56、页面返回、动作信号、v1 契约 JSON 检查（`ui.audio.setting.v1` 契约文件仍存在）。

实测：`tests/system_menu_gothic_ui_test.tscn` → **PASS**（`SYSTEM_MENU_GOTHIC_UI_PASS`，engine_log_errors=0），证据 `evidence/runner_results_adhoc_20260910_215118_998_12440.runner.json`（HEAD `4004874f`）。临时集成组合上再次 PASS（§五）。

## 二 最终审计（原 receipt / installed_audit 未覆盖、未改写）

原始 `outputs/ui_r5_install/receipt.json`（APPLIED 22 文件）与 `installed_audit.txt`（PASS 22+8）保持原样。新增最终审计产物：

- `docs/ui_r5/20260910/evidence/final_audit.json`（由 `evidence/final_audit.py` 生成，脚本一并入库可复跑）
- `docs/ui_r5/20260910/supplemental.patch`：完整补充差异（418 行，仓库相对路径），含 S1–S3（5 个包文件相对原包 payload 的差异）与 S4–S5（`tests/inventory_equipment_ui_test.gd`、`tests/system_menu_gothic_ui_test.gd` 相对基线 `c91781bd` 的修订，按 docs/01 §六 用户授权）

三态区分（逐文件 SHA256 审计结论）：

| 状态 | 覆盖 | 结论 |
| --- | --- | --- |
| 原包安装态 | receipt.json `after_sha256`（9 改动文件；13 新文件以 payload 字节为安装态） | 与包 payload 全部一致 |
| 补充修订态 | payload + supplemental.patch（S1 guard、S2 core、S3 audio、S3 delete、S3 panels、S4 inventory、S5 menu） | 5 个包文件偏离安装态：`scripts/ui_selection_dismiss_guard.gd`、`tests/ui_r5_core_test.gd`、`tests/ui_r5_audio_test.gd`、`tests/ui_r5_delete_test.gd`、`tests/ui_r5_panels_test.gd`——与申报的补充修订清单**逐一吻合，无未申报偏离**；其余 17 路径与安装态逐字节一致 |
| 最终测试态 | R1 修订提交工作树字节（含 S4/S5 与边界增强） | `final_audit.json` 逐文件记录 SHA256 + git blob |

受保护依赖复核：`manifest.dependency_blobs` 全部逐字节吻合（`all_match: true`），原包未夹带依赖改动。

## 三 临时集成验证（以最新已验收仓库布局为目标）

步骤与每次运行的精确状态：

1. 临时树 `HardCore-worktrees\ui-r5-tmp-integration-20260910`（分支 `codex/ui-r5-tmp-integration-20260910`，仅本地、不推送）自 `92c3f753` 创建。
2. 合并 `f9716ac1` → 合并提交 `0b25e1e0`。**冲突数 = 0**：92c3f753 对 `scripts/warehouse_panel.gd` 的 3 行改动位于 `_build_storage_sections` 的 TransferDivider 区（R5 未触碰），R5 的 dock 改动区 92c3f753 未触碰，git 按块自动合并。无整文件 ours/theirs 操作。逐处核验：
   - `warehouse_panel.gd` 同时含 `TransferDivider` 命名 + `calibration_layer=warehouse_transfer_divider` + `calibration_layout_revision` 元数据（92c3f753 侧）与 `UIItemDetailDockScript.side_region` dock 逻辑（R5 侧）；
   - `assets/data/ui/manual_layout_overrides.json` 保留 92c3f753 晋升版，SHA256 = `DDFDBFC3418D8286EE6264AC24FB725B5BB0B5E1285410EE62CC31837B349496`，与 `ui_runtime_layout_overrides.gd` pin 精确一致——**用户最新仓库界面未被旧包或旧文件覆盖**。
3. 隔离 `--import`（独立 `$env:APPDATA/LOCALAPPDATA` → 本树 `.godot\runtime_appdata`），EXIT=0。
4. 测试批（9 场景，HEAD `0b25e1e0`）：

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| ui_r5_core_test | PASS | |
| ui_r5_audio_test | PASS | |
| ui_r5_delete_test | PASS | |
| ui_r5_panels_test | PASS | 含 §四 全部边界项 |
| system_menu_gothic_ui_test | PASS | 迁移后测试在最终组合通过 |
| inventory_equipment_ui_test | PASS | 含 S4 dock 断言 |
| shared_warehouse_transaction_test | PASS | 冲突文件 `warehouse_panel.gd` 的邻接交易测试 |
| warehouse_gothic_ui_test | 首跑 FAIL → **复跑 PASS** | 失败根因见下（每树校准工作文件缺失，非代码回归） |
| ui_runtime_layout_overrides_test | FAIL（已知预存环境竞态） | 自身断言全部通过并打印 `UI_RUNTIME_LAYOUT_OVERRIDES_TEST_PASS profiles=9 hash=DDFDBFC…`，进程退出竞态见下 |

**warehouse 首跑 FAIL 根因**：`load_profile` 读取 `res://outputs/ui_calibration/manual_layout_overrides.json`（校准器工作文件，gitignored、每树独立）。主树有该文件（1,965,493 字节，用户校准状态），临时树没有 → "当前界面没有已保存数据"。将主树该文件**只读复制**进临时树后复跑 → PASS（engine_log_errors=0）。这是复现"最新已验收布局状态"的必要每树工件，不涉及任何仓库跟踪文件。

**ui_runtime_layout_overrides_test FAIL 定性**：与此前主树 stash A/B 结论一致的环境竞态——测试自身断言（9 profile、合同哈希 pin、无文本冻结、幂等）全部通过后，`character_select.gd` 链路的贴图 preload 与测试退出竞态产生 26 条 stderr 噪声导致 runner 判 `process_did_not_exit;early_script_error;stderr_failures_26`。A/B 证据：主树 `8dd1d092` 上独立复跑出现**完全相同签名**（`evidence/main_tree_pins_ab.runner.json`），与 R5/合并无关。

### 同基线 A/B 汇总（每次运行绑定精确 HEAD）

| 运行 | HEAD | 结果 | 证据 |
| --- | --- | --- | --- |
| 主树（92c3f753 提交时刻） | `92c3f753` | warehouse PASS；system_menu FAIL（旧断言依赖已退役开关——迁移动机） | 主树 `outputs/test_logs/runner_results_adhoc_20260910_210803_523_21360.json` |
| R5 分支 | `4004874f` | warehouse FAIL（基线差：旧合同+无晋升 pin），R5 四场景 PASS | `evidence/runner_results_adhoc_20260910_210333_660_5452.runner.json` |
| 临时集成 | `0b25e1e0` | 上述 9 场景结果（7 PASS + warehouse 复跑 PASS + pins 环境竞态） | `evidence/tmp_integration_battery.runner.json`、`evidence/tmp_integration_warehouse_rerun.runner.json` |
| 主树 pins A/B | `8dd1d092` | 与临时集成相同环境竞态签名 → 证明预存 | `evidence/main_tree_pins_ab.runner.json` |
| 主树 m30-r3 合并后冒烟（他任务运行，佐证 92c3f753 保留） | `7db453a1` | warehouse PASS 等 4/4 | 主树 `outputs/test_logs/runner_results_adhoc_20260910_215119_672_22420.json` |

临时集成工作树与结果提交保留在本地磁盘供 integration 最终审查；**本轮未执行正式主树合并**。

## 四 关键边界补充（全部实测）

1. **稀有出售确认窗口 × 清选观察器**（`tests/ui_r5_panels_test.gd` 新增）：真实批量出售请求（`requires_confirmation` 报价）打开 `sell_confirmation`（GothicConfirmationPanel，确认/取消按钮保留，labels "确认出售"/"取消"）→ 确认窗口打开时空白点按不清选、窗口不关（模态保护：guard 在 `_begin`/`_commit` 双重 `_blocked_by_modal()` 检查）→ `confirm_button.pressed` 仍发真实 `sell_requested` 请求并关窗 → 再次打开后 `cancel_button.pressed` 关窗、清 pending、**绝不自动确认**且保留选择。
2. **详情必须实际可见**：仓库/背包/商店三面板断言 `debug_layout_valid() == true` 且 `modulate.a == 1.0`（不是只查 `visible`——无空间分支下 `visible` 属性仍为 true 而 alpha=0，只查 visible 会漏检）。inventory_equipment_ui_test S4 同步补齐两项断言。
3. **仓库两侧停靠**：stash 侧详情停靠仓库格左侧（区域右缘 ≤ 仓库格左缘）且在整视口内不被交易按钮遮挡；bag 侧详情停靠背包格右侧（区域左缘 ≥ 背包格右缘），不覆盖任一格。
4. **长文本与滚动**：80 行长文写入真实面板 → `scroll_active`、`scroll_to_line(40)` 后滚动条值 > 0，且停靠矩形（position/size）与滚动前逐值一致（布局键不含滚动值，滚动不触发重排）。
5. **无空间分支如实描述**（探针证据 `evidence/no_space_branch_probe.log.txt`）：区域 < 100×80 时 `_relayout` 置 `_layout_ok=false` → `modulate.a = 0.0`、正文 `mouse_filter=IGNORE`、`push_error("UI_R5_DOCK_NO_SPACE: <owner> <region>")` **每态一次**（`_dock_error_reported` 门闩）；`visible` 属性保持 true；区域恢复充足后 alpha 回 1、报错门闩复位。**支持的真实布局均未触发该分支**（三面板 + 仓库两侧全部 alpha=1 且 layout_valid），故按任务要求无需修复、也未去掉报错或放宽测试；如未来在支持布局内触发，报告义务为记录真实矩形与布局来源后修复。

## 五 报告纠错（用户指名）

1. **"panels 34 项包含确认分支"为不准确的证据归属**：原 `ui_r5_panels_test.gd` 的 34 项检查只覆盖背包停靠/仓库 stash 停靠/菜单滑块 v2 事件/loot 静止，**不含任何稀有出售确认分支检查**。本轮已补上真实确认分支覆盖（§四.1），检查数随之增长，并在本节留档纠正。
2. 系统菜单测试"预存失败、与 R5 无关"结论作废，已按 §一 迁移。
3. 无空间 alpha=0 行为本轮已在 §四.5 如实描述并附探针证据，不再含糊。
4. 本报告所有测试证据绑定实际代码版本：每条 runner JSON 均记录 `git_head`，见 §三 A/B 表与 §九。

## 六 Windows 工具自检（2 项未通过，单列）

1. `test_symlink_refused`：WinError 1314 —— 非提升进程无 `SeCreateSymbolicLinkPrivilege`，符号链接拒绝用例按预期路径触发但断言的环境前提（可创建 symlink）不满足。环境性失败，非工具缺陷。
2. `test_apply_and_rollback_restore_exact_bytes`：单元测试将未解析的 TEMP `Path`（8.3 短路径 `ADMINI~1`）传给 `rollback()`，而 CLI `main()` 会 `.resolve()`，二者词形不同导致比对失败。生产 CLI 已用真实回滚→零差异→再应用往返证明不受影响；属测试用例词形问题，未修改工具。
其余 22/24 用例通过；包工具 `check/apply/rollback/audit` 生产路径不受影响。

## 七 NOT_RUN（Android）

- Android 真机/模拟器实机验证：NOT_RUN（本轮不构建、不分发 APK）。
- Android 触控链路（真机手套/多点）对 `UISelectionDismissGuard` 的手感验证：NOT_RUN，待下次带设备验收。
- 项目配置版本号：未改（约束）；主树版本号由 m30-r3-integration 任务在 `8dd1d092` 管理。

## 八 剩余风险

1. `ui_runtime_layout_overrides_test` 的退出竞态（character_select 贴图 preload vs 测试 quit）在两棵树上同签名复现，属预存环境问题；其断言全过，但 runner 判 FAIL，正式 suites 中需按已知问题处理或由 integration 排期修复竞态本身。
2. 校准器工作文件 `outputs/ui_calibration/manual_layout_overrides.json` 为每树 gitignored 状态：任何新工作树跑 `warehouse_gothic_ui_test` 前需从主树复制，否则 FAIL（已在本轮临时树验证并记录根因）。
3. 主树在验证期间被推进到 `codex/m30-r3-integration`（`8dd1d092`，其合并自述保留 92c3f753）。本报告的临时集成基于 `92c3f753`；正式合并时 integration 需以当时真实主树 HEAD 复核 92c3f753 仍被保留，并复跑 §三 批次（预期无需改代码）。
4. 稀有出售确认窗口的真实触控焦点序列（`grab_focus` + 手柄/键盘导航）仅做了按钮 pressed 信号级验证，未做真机焦点遍历验证（归入 §七 NOT_RUN）。

## 九 交付清单

- **修改文件**（R1 修订提交 `f9716ac1` + 交付提交）：`tests/system_menu_gothic_ui_test.gd`、`tests/ui_r5_panels_test.gd`、`tests/inventory_equipment_ui_test.gd`、`docs/ui_r5/20260910/IMPLEMENTATION_REPORT.md`、`docs/ui_r5/20260910/supplemental.patch`、`docs/ui_r5/20260910/evidence/*`（final_audit.json/py、runner JSON ×9、无空间分支探针日志）。
- **测试命令与结果**：`tools/run_godot_tests.ps1 -TestPaths <tracked .tscn> -TimeoutSeconds 60`；各运行结果见 §三/§五（每运行含 `git_head` 的 runner JSON 已入库）。
- **新增/变更稳定 ID**：无新增；复用既有 `ui.audio.setting.v2`、`shop.sell.risky_item`、`UI_R5_DOCK_NO_SPACE`、`setting_id=audio.music.volume|audio.sfx.volume`。
- **integration 所需跨系统接入**：正式合并由 integration 最终审查后另行执行（本报告 §三 提供合并与冲突依据）；临时树保留在 `HardCore-worktrees\ui-r5-tmp-integration-20260910`（结果提交 `0b25e1e0`）。
- **当前提交哈希**：
  - R1 修订提交：`f9716ac158c4480d696bc112461e525e978ea603`（分支 `codex/ui-r5-dock-audio-dismiss`，已推送）
  - 临时集成结果：`0b25e1e07615d58b98e48a5e6610bbe4227309e2`（分支 `codex/ui-r5-tmp-integration-20260910`，仅本地）
  - 交付提交：`6a2beba83ef70eb676a7fbe1cb00e2d2f97e7b5e`（本报告 + 最终审计 + 补充差异 + 全部 runner 证据入库，已推送）
