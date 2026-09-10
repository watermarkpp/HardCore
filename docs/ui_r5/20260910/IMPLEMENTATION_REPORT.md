# HardCore UI R5 实施报告

实施代理：GLM-5.3-Flash（实现者，非设计者；按 `HardCore.UI.R5.complete.v1` 包指令执行本地接入、编译检查、回归、自审与报告）。

## 1. 版本与范围

- 包 ID：`HardCore.UI.R5.complete.v1`（2026-09-10）。
- 源 ZIP：`C:\Users\Administrator\Downloads\HardCore_UI_R5_Complete_20260910.zip`，SHA-256 `92C41D32987D34EAE7D0890C083663C82A037918374DD653766E905354F58544`。
- 解包目录：`C:\Users\Administrator\Documents\HardCore_UI_R5_package\HardCore_UI_R5_Complete_20260910`（含包自带 `.gdignore`，未复制到项目根）。
- 工作树：`C:\Users\Administrator\Documents\HardCore-worktrees\ui-r5-dock-audio-dismiss-20260910`；分支 `codex/ui-r5-dock-audio-dismiss`（新建，追踪 `origin/codex/integration`）。
- 开始 HEAD：`c91781bdf59bde825a6de13b6c96e86453c40b92`（= 审查 SHA，`origin/codex/integration` HEAD，fetch 后核实）。
- 最终 commit：见本报告同目录 Git 记录（单一提交，未 push、未合并、未改版本号）。
- 唯一写者：本工作树为本会话新建，仅本代理写入（git status 始终精确等于 22 包路径 + 1 个经授权的旧测试更新 + 报告文件）。`project.godot`、`scripts/game_root.gd`、`scripts/player_state.gd` 属 integration 独占文件，本任务按包指令由主控+执行同一代理完成，合并时须由 integration 复核。`HardCore-worktrees/m30-r4r2` 代理一直在其自有树内运行，无共享写面。
- bootstrap：在专项树按 `tools/agent_bootstrap.ps1 -Compact` 运行，仅因分支名 `codex/ui-r5-dock-audio-dismiss` 不在旧白名单而失败（`Unknown branch for bootstrap routing`），按 AGENTS 记录后以等价预检继续：基线=c91781bd ✓、HEAD 一致 ✓、状态干净 ✓、适用规则 `docs/agent_rules/integration.md`（已读）✓。主树 bootstrap PASS（head 92c3f753）。
- 基线/preflight/receipt 路径：
  - 预检：`outputs/ui_r5_install/preflight.json`（PREFLIGHT_PASS）
  - 候选补丁：`outputs/ui_r5_install/candidate.patch`
  - 应用回执：`outputs/ui_r5_install/receipt.json`（APPLIED，22 文件）
  - 应用审计：`outputs/ui_r5_install/installed_audit.txt`（PASS，22 安装 + 8 受保护依赖，errors=[]）
  - 备份：`outputs/ui_r5_install/backups/`
- 9 现有 + 13 新增一致性：candidate.patch 恰好触及 BASE_MANIFEST 的 22 条路径（9 修改：project.godot、audio_runtime_service、game_root、inventory_panel、loot_pickup、player_state、shop_panel、system_menu_panel、warehouse_panel；13 新增：5 个 payload 脚本 + 8 个测试文件）；逐文件哈希复核"除第 5 节补充修订外，9 修改文件与 receipt after_sha256 一致、11 个新增文件与包 payload 字节一致"（`integrity check ok: True`）。
- .uid 来源：Godot 4.7（v4.7.stable.official.5b4e0cb0f）在隔离导入/运行时对 9 个新 `.gd` 实际生成 9 个 `.uid`，逐路径核对后纳入：`scripts/audio_preferences.gd.uid`、`scripts/item_detail_docked_presenter.gd.uid`、`scripts/ui_item_detail_dock.gd.uid`、`scripts/ui_item_selection_visual.gd.uid`、`scripts/ui_selection_dismiss_guard.gd.uid`、`tests/ui_r5_core_test.gd.uid`、`tests/ui_r5_audio_test.gd.uid`、`tests/ui_r5_delete_test.gd.uid`、`tests/ui_r5_panels_test.gd.uid`。导入还为他人/基线缺 uid 的旧文件生成了 .uid（如 tests/hc_monster_ai/*、docs/bugfix24 下 .translation 等），均不属于本任务，保持未暂存、未提交。

## 2. 实施结果

| 需求 | 最终方法/接口 | 自动化证据（本工作树实测） | 未验项 |
|---|---|---|---|
| 音乐/音效滑条，离开菜单自动保存 | `AudioPreferences` autoload（`user://audio_preferences_v2.cfg`，.tmp+.bak 原子写）；v2 合同 `AudioPreferences.set_level`；v1 合同兼容映射保留；SFX 用户增益仅经 `AudioRuntimeService`（SFX 总线 0dB，不二次衰减）；离开路径 flush，值变更不落盘 | `ui_r5_audio_test` 23/23：移动不写盘、首存/再存 .bak 精确字节、注入失败保持 dirty 且不改已存字节、重试成功、重载为数值、语义损坏走备份恢复；`ui_r5_panels_test` 菜单滑条接线 | 真机重启后数值、系统强杀中保存（物理层） |
| 商店属性/必要提示右停靠且居中 | `shop_panel.gd` + `UIItemDetailDock.shop_region`（右停靠、居中、买/修/出售行保护；共享 `_ui_show_shop_message` 单一入口） | `ui_r5_core_test`（37/37，shop_region 分支）；`ui_r5_panels_test` 34/34；`shop_gothic_ui_test` PASS；`shop_sell_performance_contract_test` PASS | 真实买卖交易 |
| 仓库详情在整个仓库格左侧；背包详情在背包格右侧 | `warehouse_panel.gd`/`inventory_panel.gd` 经 `UIItemDetailDock.side_region(left/right)`，12px 间隙；空间不足 `UI_R5_DOCK_NO_SPACE` 报错不隐藏 | `ui_r5_core_test`：left/right 双向 bounded、永不覆盖格子、长正文可滚动不截断；`ui_r5_panels_test` 真实面板构建；`inventory_equipment_ui_test`（按 §5-S4 更新）停靠零重叠 | 真机不同分辨率布局 |
| 删除静默、成功后清空全部选中 | `player_state.gd::destroy_inventory_indices`：快照→删除→`_commit_save`→失败恢复快照并返回 `save_failed`；成功仅发一次信号 | `ui_r5_delete_test` 14/14（对**已安装**函数做故障 seam：失败提交恢复精确记录、成功恰好一次信号、重复/空目标原子拒绝）；`safe_logout_save_failure_test` PASS | 完整存档服务物理原子性 |
| 空白点按清选；空格例外=原有功能保护（卸装到槽） | `ui_selection_dismiss_guard.gd` 被动观察：DOWN 只记录、UP 延迟判、≤8px/≤450ms、第二指双向作废、canceled 忽略、仿真设备忽略；功能性控件（按钮/滑条/输入/ItemList/虚拟摇杆等）与模态一律保护；卸装目标空格保持可点 | `ui_r5_core_test`：空白清一次、功能钮保护、被动空格可清、拖动不清、长按后第二指不清、原生取消忽略、延迟清不得抹新选择、仿真事件不重复、**启用卸装目标的空格受保护** | 真实 Android 触摸分发、多指、真实长按 |
| 选中/取消选中恢复语义边框（残留高光） | `ui_item_selection_visual.gd`：按语义主题统一 hover/pressed/hover_pressed/focus；取消选中回归普通主题；仅用于物品格/装备槽/商店卡 | `ui_r5_core_test`：hover 不得复活选中框、pressed 等于未选普通框、无幽灵 focus 框、toggle 按压语义 | 真机视觉复核 |
| 地面掉落静止 | `loot_pickup.gd`：删除 `_bob_time`；`manager_visual_tick` 仅把图标校正到 (0,-5)（is_equal_approx 防每帧重绘）；`_draw` 固定菱形；拾取权威未动 | `ui_r5_panels_test`：120 tick 位置恒定；`loot_pickup_runtime_manager_test`、`loot_feedback_gothic_ui_test` PASS | 真机帧率观感 |
| 稀有出售确认对话框保留确认/取消 | 确认路径不自动确认；对话框按钮保留（`gothic_confirmation_panel` 保护清单含于观察器模态保护） | `ui_r5_panels_test` 34/34 含确认分支；`shop_gothic_ui_test` PASS | 真实出售交易 |

## 3. 命令与退出码

| 命令/场景 | 版本和路径 | 退出码 | 证据 | 状态 |
|---|---|---|---|---|
| `py -3.12 tools\test_package_tools.py` | Python 3.12.7，包目录 | 1（24 项：22 过，2 环境性错误，见 §5 注） | 会话记录；WinError 1314 + TEMP 8.3 短名诊断 | PARTIAL（环境） |
| `py -3.12 tools\apply_ui_r5.py --repo . --check` | 同包 | 0 | outputs/ui_r5_install/preflight.json | PASS |
| `apply_ui_r5.py --apply`（两次，含回滚往返） | 同包 | 0（两轮均 0） | receipt.json；回滚后 `git status` 0 行；重应用 22 文件 | PASS |
| `tools\audit_installed.py --repo .` | 同包 | 0 | installed_audit.txt（22+8，errors=[]） | PASS |
| 回滚边界 `--rollback receipt.json` | 同包 | 0 | ROLLED_BACK，索引未动 | PASS（CLI 全链路） |
| `Run_UI_R5_Tests.ps1 -Repo <工作树>` | Godot v4.7.stable.official.5b4e0cb0f | 1 → 0（§5 修订后） | outputs/test_logs/runner_results_adhoc_20260910_210013_786_2504.json | 4/4 PASS，engine_log_errors=0 |
| ui_r5_core_test | 同上 | 0 | 同上（checks=37 failures=0） | PASS |
| ui_r5_audio_test | 同上 | 0 | 同上（checks=23 failures=0） | PASS |
| ui_r5_delete_test | 同上 | 0 | 同上（checks=14 failures=0） | PASS |
| ui_r5_panels_test | 同上 | 0 | 同上（checks=34 failures=0） | PASS |
| 邻接批（13 tracked 场景） | 同上 | 首轮 1（10 过 3 失败）→ 分处置后 11 过 | runner_results_adhoc_20260910_210333_660_5452.json；inventory 复跑 runner_results_adhoc_20260910_211205_355_12352.json | 见下 |
| └ inventory_equipment_ui_test | tests/inventory_equipment_ui_test.tscn | 0 | §5-S4 更新后复跑 PASS | PASS（更新后） |
| └ warehouse_gothic_ui_test | tests/warehouse_gothic_ui_test.tscn | — | 专项树失败=基线缺 92c3f753 晋升合同（c91781bd..92c3f753 对 manual_layout_overrides.json 507+/8376-）；主树同测试 PASS（runner_results_adhoc_20260910_210803_523_21360.json） | FAIL（基线，非 R5） |
| └ system_menu_gothic_ui_test | tests/system_menu_gothic_ui_test.gd:32 | — | 主树（无 R5）同样失败同一断言；`GothicSystemMenuGemButton` 在基线即已存在，R5 diff 未触及 | FAIL（预存，非 R5） |
| └ 其余 10 项 | inventory_multiselect_discard_sort / inventory_weight_authority / shop_gothic_ui / shop_sell_performance_contract / shared_warehouse_transaction / safe_logout_save_failure / loot_pickup_runtime_manager / loot_feedback_gothic_ui / hud_ui_action_bridge / android_attack_action_lifecycle | 0 | 邻接批 JSON | PASS |

已知无关预存失败（本任务未复跑、不属邻接面）：`ui_runtime_layout_overrides_test`（character_select 竞态致引擎日志污染，此前会话已用 git-stash A/B 证明与本仓库改动无关）。

## 4. 真机/实际业务

全部 NOT_RUN：无设备自动化授权与设备接入。待真机/真实业务矩阵（docs/03）至少包括：功能空格卸装、多指、正常长按、关闭菜单保存、重启后数值、删除保存失败（物理层）、拾取观感、商店真实买卖、仓库/银行真实事务、不同分辨率停靠、长正文滚动。设备型号/系统版本/应用版本/源SHA/截图视频：未取得。依据包纪律与用户要求，手机未验证前只能判定"代码候选已接入，真机待验"。

## 5. 补充修订

原始候选审计 PASS（preflight/apply/audit 全绿，原始 receipt 与 installed_audit.txt 保留，未伪造新 receipt）。应用后做了以下最小修订；除 S4 外均属"引擎实际报出的局部 API/类型错误或仓库 runner 合同适配"，`supplemental.patch`（本目录 + outputs/ui_r5_install/）记录全部差异，重跑后 4/4 PASS：

- S1 `scripts/ui_selection_dismiss_guard.gd::_exit_tree`：`get_meta(NAME, null)` 在 Godot 4.7 对缺失键仍报引擎错误（实测 engine error）；改为 `has_meta(NAME) and get_meta(NAME) == self`，行为不变，消除假引擎错误（runner 计入 engine_log_failures）。
- S2 四个 R5 测试 PASS 标记格式：`UI_R5_CORE %s` → `UI_R5_CORE_%s`（音频/删除/面板同理）。仓库 runner 合同为 `[A-Z0-9_]+_PASS`；原格式三场景内部 23/14/34 项全过却报 missing_pass_marker。仅改打印格式，不改任何断言。
- S3 `tests/ui_r5_core_test.gd` 夹具主题补 `set_type_variation("R5Plain","Button")`/`("R5Chosen","Button")`：Godot 4.7 只有注册过的类型 variation 才参与链解析（判别实验：注册后 `get_theme_stylebox("normal")==plain` 为 true；仓库 `gothic_ui_theme.gd` 全部变体均先注册，生产面板用的 Gothic 变体都已注册）。生产 `UIItemSelectionVisual` 无需改动；两条断言语义原样保留并转为通过。
- S4（仓库既有测试，非包文件）`tests/inventory_equipment_ui_test.gd` 两处旧浮窗断言按 docs/01 §六（"旧测试若坚持详情必须出现在背包内部…按逐断言说明更新"）与 docs/04（`_empty_bag_region_candidates` "不再依赖空格分布"）更新：
  - 旧断言 A：`_empty_bag_region_candidates().size() > 0`（枚举连续空格作浮窗候选）＋存在小于 5列×3行 的候选；
  - 新断言 A：停靠详情可见、尺寸非零、与全部背包格零重叠（加严）；
  - 旧断言 B：满背包长详情须在"面板矩形内缩 18px"内；停靠权威边界是视口安全区（`UIItemDetailDock.EDGE=18`，与屏幕边 18px）；
  - 新断言 B：视口安全区包含 + 覆盖选中格面积=0（加严）；
  - 用户依据：用户明确要求背包详情停靠背包格右侧、仓库详情停靠仓库格左侧，空格仅作卸装目标/清选（"空格例外是原有功能保护，不是漏做"）。
- 包工具自检 2 项环境性错误定性（非工具缺陷、非环境虚构）：① `test_symlink_refused` 因非提升进程无 `SeCreateSymbolicLinkPrivilege`（WinError 1314），夹具创建失败；工具的符号链接拒绝守卫（is_symlink+resolve 包含性）静态核实在案且每次 apply/audit 对全部真实路径执行。② `test_apply_and_rollback_restore_exact_bytes` 因本机 TEMP 为 8.3 短名（`ADMINI~1`），单元测试直接以未 resolve 的 Path 调 `rollback()`，与 `.resolve()` 展开后的长名做词法比较失败；生产 CLI 不受影响（`main()` 入口 `args.repo.resolve()`），并以真实 CLI `--rollback`→0 差异→`--apply` 全链路补证。

## 6. 冻结对象

- `git status`/diff 证明本分支仅含 22 包路径 + S4 测试更新 + 报告；地图、装备属性主表、怪物、技能、爆率、共享金币事务、`assets/data/ui/manual_layout_overrides.json`（人工校准合同）零改动。
- `audit_installed.py`：8 个受保护依赖 blob 全部一致（errors=[]）。
- GameRoot 仅 2 方法：`_build_system_menu`（`set_audio_levels` 替换总线布尔）与 `_on_system_menu_audio_setting_changed`（v2 合同 + v1 兼容映射）；攻击输入 owner/token 生命周期零触及（android_attack_action_lifecycle_test PASS 佐证）。
- PlayerState 仅 `destroy_inventory_indices` 单方法（包工具 `test_game_root_scope_is_only_audio` + 补丁审阅）。
- `project.godot` 仅在 DeviceLabPatch 之后追加 `AudioPreferences=` 一行，首个 autoload 保持（`test_autoload_keeps_device_patch_first` + 补丁审阅）。
- 掉落拾取权威、存档格式、银行/交易事务未动。

## 7. 发布状态

- 本地单提交已完成（分支 `codex/ui-r5-dock-audio-dismiss`，基于 `c91781bd`）。
- 未合并、未 push、未改 Android 版本号、未构建/分发 APK。
- 未获合并/推送/构建授权；未来合并需注意：本分支与本地未推送的 `92c3f753`（仓库转移分隔线 + 用户仓库布局晋升）均改 `warehouse_panel.gd` 与正式 UI 合同，由 integration 控制器裁决合并顺序与冲突。

## 8. 最终判定

**引擎通过待真机（代码候选已接入，真机待验）。**

- 包 22 路径按审查基线完整接入；4 个 R5 场景 4/4 PASS（engine_log_errors=0）；邻接 13 项 11 PASS，2 项失败均以主树 A/B 证明为基线差异/预存失败，非 R5 回归。
- 剩余风险：真实 Android 触摸分发与多指行为（观察器为被动设计且有分支覆盖，但未经真机）；真实交易/删除物理层；不同真机分辨率下的停靠空间（不足时会按设计报 `UI_R5_DOCK_NO_SPACE` 而非挤压）。
- 精确下一步：integration 控制器审阅本报告与 supplemental.patch → 裁决与 `92c3f753` 的合并顺序 → 真机矩阵验收（重点：空格卸装、多指、长按、关菜单保存、重启数值、删除保存失败、拾取观感）。
