# UI 响应机制有界只读审计

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

日期：2026-09-22。结论级别：静态候选证据，交由 Astra 主控复核；运行验证：`NOT_RUN`。

本次仅检查 HUD、全部九个 `scripts/*_panel.gd`、直接共用的按钮/主题/布局/纹理缓存，以及必要的 GameRoot 信号消费者和现有测试。不运行 Godot，不修改生产、已接受的 UI 美术、布局、背包/装备格子，也不把静态代码路径耗时当成设备实测。

## 1. 主要结果及边界

- `scripts/ui_feedback.gd`：`MISSING`。当前共用视觉反馈入口是 `scripts/gothic_ui_theme.gd:542` 的 `set_button_feedback()`；`scripts/ui_error_feedback.gd` 只负责错误理由到文字的映射，不负责动画。
- 本次扫描的 17 个 UI 脚本中，`Tween`、`create_tween`、`tween_property`、`AnimationPlayer`、`animation_finished` 均无命中。因此这些脚本没有可列出的 Tween 动画时长、重复点击 Tween 队列或 Tween 取消器。此结论不外推到未扫描的场景资源、角色特效或其他 UI。
- 没有项目自定义的统一 Panel 基类：背包、仓库、商店、技能、任务、地图直接继承 `Panel`；系统菜单、复活、确认框直接继承 `Control`。反馈状态和清除时间由各面板持有。
- 已确认的机制差异包括：业务信号前后设置 busy 的顺序不同、结果反馈有的等待一个 `process_frame`、固定结果状态寿命不同、冷开时可能同步补齐控件或加载资源。它们是可复核的响应候选，尚不是用户所见“有的拖延、有的流畅”的最终根因。

## 2. 公共按钮与输入入口

| 位置 | 已确认行为 | 对响应调查的意义 |
| --- | --- | --- |
| `scripts/gothic_ui_theme.gd:542` `set_button_feedback()` | 当次调用备份/替换样式、设置状态元数据和文字颜色；本函数不创建定时器或动画 | 设置状态与真实绘制之间仍可能夹有同一帧的业务工作；不能把函数调用完成视为用户已经看见反馈 |
| `scripts/gothic_ui_theme.gd:805` `_prewarm_action_feedback_styles()` | 预生成背包、仓库、商店、任务、复活、确认等动作的 success/failure 样式 | 已有样式预热，不宜未经测量再次添加一层缓存 |
| `scripts/adaptive_button_style_box.gd:162` `clone_with_feedback()` | 以反馈色和边距等组成缓存键；复用已生成样式；绘制为静态 draw | 公共样式不是逐帧 Tween；缓存命中与首次生成应分别测量 |
| `scripts/hud.gd:611` 起的入口连接 | 地图、菜单、背包、技能书使用 `pressed`；交互按钮在 `:1453` 使用 `button_down`；切目标 `:1466` 使用 `pressed` | 连接的信号时点不完全一致。需使用同种真实触摸序列比较，不能只调用处理函数比较观感 |
| `scripts/circular_touch_button.gd:51,65,122,169` | GUI 负责开始，额外全局输入接收释放安全网；开始时检查 enabled/disabled/visible、活动触点和 token；立即发 `input_started`，结束消费 token；失焦/隐藏/退出会取消 | 有重复开始和生命周期保护；本文件未发现等待动画结束再交付输入的路径 |

`set_button_feedback()` 包含 normal/selected/busy/success/failure/transition 状态。transition 的结束依赖业务或面板生命周期，不能将其解释为固定秒数的动画。

## 3. 反馈时间与重复操作保护

下表的秒数是状态寿命或输入门槛，不是经过设备测量的绘制延迟。

| 面板 / 精确入口 | 顺序和时间 | 重复操作 / 清理 |
| --- | --- | --- |
| 背包 `inventory_panel.gd:1482` `_on_auto_sort_pressed()`；`:1522` `_show_inventory_action_result()` | 先 busy，再同步整理和刷新；结果先等待一个 `process_frame`，成功保持 **1.0 s**，失败 **0.45 s** | 面板反馈 serial 使旧结果/定时器失效；`:1542` 清除递增 serial；关闭和取消选择会清除反馈 |
| 商店 `shop_panel.gd:1300` `_buy_selected()`；`:1356` `_show_transaction_result_feedback()` | 先 busy 和锁，再发购买信号；结果等待一个 `process_frame`，成功 **1.0 s** / 失败 **0.45 s**；购买独立锁 **0.2 s** | 购买锁有独立 serial；`apply_buy_result():446` 不提前清除此锁。结果反馈 serial 避免旧回调覆盖新状态；关闭清理反馈但选择取消不绕过交易锁 |
| 商店 `shop_panel.gd:1282` `_repair_all()` | busy 后同步执行修理、刷新，再交给同一结果反馈函数 | 使用结果反馈 serial；需要区分修理业务耗时与结果等待一帧 |
| 商店 `shop_panel.gd:986,1001,1020` 数量长按 | 按下先变化一次；首次重复等待 **0.42 s**；后续间隔从 **0.16 s** 基准乘 **0.82**，最低 **0.035 s** | 重用同一个 Timer，开始前停止，释放/关闭时停止；不可变化或隐藏时停止。不是每次重复追加独立动画 |
| 技能 `skill_panel.gd:905` `_assign_selected_to_target()`；`:943` `_request_clear_target()`；`:985` `_show_assignment_sent()` | **先发出业务请求信号，随后才设置 busy**；“已发送”反馈固定 **0.25 s** 后清除，无结果等待一帧 | serial 防止旧清除覆盖新反馈；这表示发送后的短提示，并非等待事务完成的统一 busy 合同 |
| 系统菜单 `system_menu_panel.gd:387` `_show_menu_action_result()` | 直接设置 success/failure，不先等待一帧；成功 **1.0 s** / 失败 **0.45 s** | serial 使旧定时器失效；继续/选角/保存入口先 flush 音频，再 transition 并发信号，结束由后续流程控制 |
| 任务 `quest_panel.gd:461` `_act()`；`:584,604` 两个结果反馈函数 | 动作锁和 busy 后调用实际任务变更；结果等待一帧，再成功 **1.0 s** / 失败 **0.45 s** | 结果共用 serial 保护；打开时清反馈。`:640` `_close()` 本身不清结果 serial，隐藏期间计时可继续，下一次打开会使旧反馈失效 |
| 仓库 `warehouse_panel.gd:1141` `_sort_requested()`；`:1147` `_show_transfer_result()` | 整理先 busy 再发信号；结果等待一帧，再成功 **1.0 s** / 失败 **0.45 s** | serial 保护；实际存取在 `:849,966,1001` 等处等待 prepared 事务，另有 pending 防重复；不能将真实提交等待统一缩成固定动画时间 |
| 复活 `death_revival_panel.gd:272` `_request_revival()`；`:305` `_show_revival_result_feedback()` | 请求锁、transition、刷新选项、发信号；普通结果等待一帧，再成功 **1.0 s** / 失败 **0.45 s** | request lock 防重复；transition 交由 Loading/复活流程接管；结果 serial 保护 |
| 确认框 `gothic_confirmation_panel.gd:150` `_confirm()` | 设置 busy 后，在同一同步流程内关闭/隐藏，再发 `confirmed`；无等待帧或结果计时 | busy 元数据可能已被设置，但确认框在下一次绘制前已隐藏。现有元数据断言不能证明用户看到了 busy 状态 |

反馈定时器通常依靠 serial 失效检查，而非显式停止已创建的 SceneTreeTimer。因此快速操作可能暂时留下尚未到期的旧回调；现有保护能避免它们清除后来的反馈。静态证据不足以将这称为积压故障或内存泄漏，需要重复输入时的数量、CPU 和生命周期实测。

信号消费者的必要链路已确认：

- `game_root.gd:1637` 连接技能分配请求到 `:6987` `_on_skill_button_assignment_requested()`；处理规则、应用分配结果和更新 HUD 都发生在面板设置 busy 之前。尚未量化该处理器的实际耗时。
- `game_root.gd:1639` / `:2575` 购买请求同步执行 `PlayerState.buy_shop_item()`，再将结果交回 HUD。
- `game_root.gd:1643` / `:2592` 仓库整理同步执行排序，再将结果交回 HUD。

## 4. 首次打开、预热和布局结算

| 路径 | 已有保护 | 未测量的候选 |
| --- | --- | --- |
| HUD `_ensure_inventory_panel():1711`、shop `:1724`、skill `:1749`、quest `:2072`、map `:2088`、warehouse `:2106`、death `:2122` | 面板实例可复用；后台预热可先完成创建 | 预热尚未完成时，入口仍需同步 `load(script)`、实例化、连接、`add_child` 并执行 ready 构建，可能落在点击当帧 |
| HUD `_run_panel_prewarm():1779` | 分阶段创建；阶段间等待帧和后台许可；诊断包含各面板 construction ms、总时间、脚本失败/待完成项目，`:2068` 可取快照 | 脚本预取在后台 gate 之前发起；单个面板的同步构建仍是一个阶段内的工作，并没有每阶段毫秒预算证明 |
| HUD `_prefetch_panel_scripts():1958`、`_start_catalog_icon_prewarm():2003` | 脚本 threaded 请求；图标路径去重、每批 12 个请求；等待上限为帧数；`_ui_l1_background_blocked():2871` 在暂停、按键输入、任何面板可见时阻止后续后台阶段 | 预取/编译与真实输入竞争的设备影响尚未测量；120 帧是等待上限，不代表固定开销，也不能直接换算成设备响应毫秒 |
| 背包 ready `inventory_panel.gd:112`、后台补格 `:679`、可见变化 `:472` | 先建 30 格，后台每批补 10 格并跨帧 | 用户在后台补齐前打开时，同步补到 100 格并刷新；已经进入的补格循环没有逐批 HUD background gate。保留完整 100 格合同，调查每批工作量和冷开临界点 |
| 仓库 `warehouse_panel.gd:358` `open_panel()`、后台 grid 初始化 | 同样先建可见 30 格、每批 10 格；最终两组各 100 格 | 提前打开时同步补齐两组格子并填充；首开与后续打开的工作量不同 |
| `ui_item_texture_cache.gd:28` `texture_at_path()` | 已缓存则复用；threaded 已完成则直接取得；`:48` 可主动请求资源 | 未缓存且 threaded 尚未完成时，`:42` 仍执行同步 `load(path)` 并增加 `sync_miss_count`。需要比较冷开/热开前后的计数与耗时 |
| `ui_runtime_layout_overrides.gd:301` `apply_profile()` | token 使旧申请失效；缓存合同；几何父子顺序排序 | 两轮几何各等待一次 `process_frame`，字体/可见性后再等待一次，总计 **3 次跨帧** 后才能到最终几何/ready。可见前是否已预热完成会影响中间帧是否暴露 |
| `ui_runtime_layout_overrides.gd:522` `_load_contract()` | `_loaded` 避免重复读；校验合同哈希和 schema | 第一次读取包含同步 SHA256 和 JSON 文件读取；本次未测量其大小与耗时，不能据此断言主瓶颈 |

真实 GameRoot 在 `game_root.gd:3645` 的非 test_mode 流程启动后台预热。纹理缓存 `ui_item_texture_cache.gd:102` 另有 headless 串行预取分支，所以 headless 测试结果不能替代 Android/图形环境首次打开的响应测量。

## 5. 隐藏面板与重复刷新

| 面板 | 已确认路径 | 调查结论 |
| --- | --- | --- |
| 背包 | `on_inventory_data_changed():446`、装备变化 `:459`：隐藏时标 pending；`:515/524` 将可见刷新合并。另有 `profile_changed` 在 `:136` 直接连接 `_refresh_character_stats():580` | 主列表隐藏刷新已保护；**角色属性文字路径未检查 visible**，仍生成 RichText、更新帮助和 `:597` 属性布局。这是尚未被主 refresh 计数覆盖的隐藏工作候选 |
| 仓库 | `:373,382,387` 标记数据/银行 dirty；`:1435/1445` 合并可见刷新；`_refresh_bank_state():753` 隐藏返回 | 已有隐藏保护和银行快照复用；真实 pending 事务避免重复快照读取。不应泛称隐藏仓库每次都重建 |
| 商店 | `profile_changed` 直接更新 `_refresh_gold():1212`；装备变化 `:1459` 后只在可见 buy 模式刷新修理预览；`:1129/1165` 合并可见卖出列表 | 隐藏金钱标签仍会写入，但这与昂贵修理计划不同；修理预览已有可见保护。金钱标签成本尚未测量 |
| 技能 | `:460` 隐藏数据变化只标 pending；`refresh():476`、`_rebuild_skill_cards():544`；`open_for():430` 在 show 前刷新 | 打开时刷新技能列表、分配和详情；卡片控件主要复用，并非每次全部重新分配。需要测量刷新总量，不应误报成全卡片重建 |
| 任务 | `:283` 隐藏标 pending、可见合并；`open_for():252` 每次打开 refresh；`_rebuild_quest_cards():323` 移除旧卡并重新创建按钮/文字 | 每次打开和执行所触发的实际 rebuild 是候选，应按任务数量记录构建耗时；不改变任务内容、位置或已接受的样式 |
| 地图 | `open_panel():412` 重用 presentation snapshot；`refresh():442` 仅在结构变化时重建 | 已存在缓存/结构差异保护；本次未发现类似隐藏常驻重建入口 |
| 系统菜单/确认/复活 | 以显式 open、请求或结果更新为主 | 本次未找到持续隐藏重建循环；仍需真实输入验证 busy/transition 首个可见帧 |

## 6. 现有测试与覆盖空白

以下只读核对了测试内容，本次均为 `NOT_RUN`；不继承旧报告中的 PASS 来证明当前生产版本。

| 现有测试 | 已覆盖内容 | 不能由此证明的内容 |
| --- | --- | --- |
| `tests/button_feedback_alignment_test.gd`、`tests/gothic_theme_component_test.gd` | 样式边距/字体不跳动、预热反馈样式复用、禁用状态和分层遮罩等 | 触摸到首个反馈像素的毫秒数、主线程尖峰 |
| `tests/hud_background_prewarm_test.gd` | 实际 GameRoot；提前开背包仍为 100 格；面板可见时后续预热阶段暂停、隐藏后恢复；最终仓库两组 100 格、图标和脚本状态 | 每个构建阶段的设备帧预算；冷开时是否出现一帧长阻塞 |
| `tests/hidden_inventory_refresh_test.gd` | 隐藏列表主 refresh 不增加；显示后刷新一次；同帧多信号合并 | 背包 `_refresh_character_stats()` 的隐藏 profile 更新，因为其未计入所检查的主 refresh 次数 |
| `tests/ui_l1/hidden_views_test.gd` | 真实 super 路径的隐藏银行、修理预览、角色预览调用次数和一次恢复 | 背包属性 RichText 重排耗时；所有隐藏 UI 总耗时 |
| `tests/hud_authority_integration_test.gd` | 预热后首开不增加多余刷新、pending 恢复 | 不同设备的反馈帧延迟 |
| `tests/shop_gothic_ui_test.gd` | busy 当帧、结果次帧；购买短锁；长按首延迟、停用停止和加速 | 输入事件到真实显示的延迟分布；60/30 FPS 下的比较 |
| `tests/warehouse_gothic_ui_test.gd` | 存取/整理 busy 与结果、结果自动清除、pending 时阻止重复事务 | 真实储存介质慢提交与视觉反馈之间的关系 |
| `tests/quest_gothic_ui_test.gd` | 任务动作 busy 后次帧 success 等状态 | 卡片重建的主线程时间 |
| `tests/gothic_confirmation_ui_test.gd` | 确认后 busy 元数据 | 确认框已同步隐藏时，busy 是否曾呈现在屏幕上 |
| `tests/death_revival_touch_input_test.gd` | 复活真实触摸链与 Loading 前 transition | 动画流畅性和 Loading 首个可见帧的设备数据 |

## 7. 交给主控验证的候选顺序

1. **反馈开始时点不一致**：先对比技能分配/清除与整理/购买。记录真实输入时间、业务处理器进入/返回、busy 设置、首个绘制帧。技能 busy 在同步消费者之后是确定事实，是否形成用户可感知延迟需测量。
2. **冷开路径与预热竞争**：同一按钮分别在预热前、进行中、完成后打开；记录 `_ensure_*`、格子补齐、`sync_miss_count` 差值、profile ready 的时间。保证格子数量、图片和几何不变。
3. **跨帧反馈与布局**：分别记录结果状态的一帧等待、layout 三次跨帧、用户首个可见像素；低帧率下“一帧”更长，不能仅凭 0.25/0.45/1.0 秒数字调整所有按钮。
4. **隐藏属性文字与任务卡片重建**：在主控确定其实际频率后，统计隐藏 profile 更新次数和总耗时、任务数量与重建时间；已有银行/修理/地图缓存保护应保留。
5. **重复点击/关闭/重开**：使用连续真实输入验证 serial 和请求锁；统计存活的短期 Timer 回调峰值、旧节点销毁后回调行为、交易是否重复。没有 Tween 队列证据，不以“杀 Tween”作为预设方案。

建议输出每个操作的冷/热状态、输入方式、业务同步耗时、首个反馈绘制延迟、最大帧时间、资源同步 miss 差值和回调数量。设备测试当前为 `NOT_RUN`。最终根因、是否调整反馈顺序/预热粒度，由主控结合这些数据裁决。

## 8. 扫描快照

本报告使用当前文件内容，不执行 Git 写入或 Godot。下面的 SHA256 固定本次静态观察对象；主控有并行施工，后续行号或哈希变化需以新内容复核。

| 文件（项目相对路径） | SHA256 |
| --- | --- |
| `scripts/gothic_ui_theme.gd` | `A180D02E304B2203F7DECAC7C70459D4951E34D927A0069401F75F43BB6A190A` |
| `scripts/adaptive_button_style_box.gd` | `93976B470A6B5EFB9CF795AB1283E8FCE8948C02916D61DB51063AB229021ADA` |
| `scripts/circular_touch_button.gd` | `C1E47F3532070233B5A53B6688B1F0DDA343869585FD286022AF6529E6DCF93E` |
| `scripts/gothic_modal_layout.gd` | `3ED57955107F0AA981AE5E1AE345977A691E2B735C7C7577218904A05F27B3DF` |
| `scripts/ui_runtime_layout_overrides.gd` | `3DC9F92BA9A21AFABC36F49BEAAC71882A009879EC7A9051462EE5161A2AAF4F` |
| `scripts/ui_item_texture_cache.gd` | `BF1B8EDE2787845B98E3C35E471E27F3337CABC0F3AE17CA7CEB1BA3DD00DA80` |
| `scripts/ui_error_feedback.gd` | `18CB0FD6217B044E94AA693EFB0EACB20D478431E597785F78948C6C7A1AE7B8` |
| `scripts/hud.gd` | `B2B7ABCBC9921B6E7AEBE0A23CA0951E46A8E9322A7506B101D910636578C585` |
| `scripts/death_revival_panel.gd` | `1C17D43FEDFD2278EB7A5ECE120836A9EA833A6703BBF7BE770578378EF3D4A9` |
| `scripts/gothic_confirmation_panel.gd` | `0B56FA88316301109A4E03519DB2385B02D4CFCB71FA5F0B67AB0DC7D0B5F008` |
| `scripts/inventory_panel.gd` | `22E9889E003A72428293BFBA05718B034B141062D59E6AE35A7FCEDE8D70EF6C` |
| `scripts/map_panel.gd` | `128B152BBA66FFEB8A4D5FD1740EDB6CB51CC8D22A2CBD9D1EC29F3AC6AE7B2D` |
| `scripts/quest_panel.gd` | `0025BBEF7A1FAEBC4F7478E83EE1681771751285B7B616B27A0F5F9380F4A981` |
| `scripts/shop_panel.gd` | `B0E58839D86E4CE94AB1EC9A229658B6C75550BB66B2C9C05D59CF51DD9571CD` |
| `scripts/skill_panel.gd` | `43435D5CBE9584F21E8CFAFE1C4F9C4D24FDF5E7B76FCEE260436CFBD0203EC4` |
| `scripts/system_menu_panel.gd` | `EA11C196A821C6CD6A28D5E006F96E1A9155240AADD5494CEBAD599D0C31E8D8` |
| `scripts/warehouse_panel.gd` | `D92E04ED120BD832314FE087360DCD39E39D34415D2CBFF1F7B38DED51DB1F75` |

复核搜索形式：对上述明确文件列表执行 `rg -n 'Tween|create_tween|tween_property|AnimationPlayer|animation_finished'`，再定位本文列出的函数并读取直接调用点。没有全仓扫描二进制、缓存或美术生成物。
