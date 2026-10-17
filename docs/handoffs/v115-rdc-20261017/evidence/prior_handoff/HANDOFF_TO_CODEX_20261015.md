# HardCore v115：RDC → Codex 续建交接报告

**交接日期：2026-10-15。现场时间采用 Windows 机器的 UTC+08:00。**

**性质：未完成工程的续建交接，不是发布说明、完成证明或 APK 验收报告。**

本报告依据本会话的实际施工记录，以及交接时对 Windows 工作区、源码、历史 invocation 的原生结果、Git index 和备份回执的重新读取。没有在写报告时重跑游戏测试，也没有继续修改生产代码。本轮新增的是交接核验记录、备份和本文。

## 0. 给接手 Codex 的首要指令

继续现有 HardCore v115 多线程候选工程。不要从旧 HEAD 重新搭建，不要整文件覆盖当前 Core/Session，不要重新讨论已确定的 M + S + W 架构，不要把旧单线程版本换成“115”交付。

当前最直接的断点是：`main_original_process_scope.gd` 刚写入、尚未测试；S 中持久 Profile 的原 P 更新、同一 scope 复用和原全局回调顺序尚未接完。先核验并闭合这个断点，再贯通真实 Main 启动生产者、唯一 SourceSession、完整世界、资源与退出链。最终交付目标是经过存档/仓库验证、使用原包名与原签名的 v115 游戏 APK，而不是组件测试合集。

本报告不发起关机，不扩大合并/发布/删除权限。早先附件中的“2% 剩余额度后冻结并关机”属于此前一次会话；不能仅因读到那段历史就关闭本次续建。当前新指令是让 Codex 接手施工。

## 1. 不可丢失的现场

### 1.1 工作区与基线

| 对象 | 交接时核验结果 |
|---|---|
| 主工作树 | `C:/Users/Administrator/Documents/HardCore` |
| 主树分支 | `codex/integration` |
| 实际施工候选树 R | `C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore` |
| 候选状态 | detached、dirty；本轮读取为 95 个 tracked 修改、605 个 untracked 文件，不含被忽略的全部输出 |
| 主树与候选共同 HEAD | `45170d0eaf4d2c642d4a03de392f64fa2b1e25bf` |
| 引擎树 E | `C:/Users/Administrator/Documents/HardCore-engine-v115/godot` |
| 引擎 HEAD | `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` |
| RDC 设备 | `WIN-20250403ZFA`；设备 ID `6f38de8f-305f-44fe-a46b-9af8080f6003` |
| 当前候选真实 Git index SHA256 | `3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22` |

**HEAD 不代表当前施工源码。大量有效实现位于 dirty/untracked 文件以及引擎修改中，只拉取远端同一 SHA 会丢失这些成果。**

交接时另有 Android staging worktree：
`C:/Users/Administrator/Documents/HardCore-android-staging/10daa4d20e3b-20261013-203857-af7db70f`，detached `10daa4d20e3be0dac1161f45b6be94e44a0bfc50`。不是本次主施工树，不得顺手删除或用它替换候选。

17:43 的相关进程检查未发现本任务的 Godot/scons/编译/测试进程；不要沿用历史 PID 杀进程。常驻服务不是遗留施工任务。接手时需重新检查。

### 1.2 证据目录别名

以下均相对于 R：

- **B（最新施工断点）**：`outputs/v115_multicore/rdc_boot_20261015_1318`
- **F（此前完整世界集成阶段）**：`outputs/v115_multicore/rdc_fullworld_20261015-1123`
- **Q1（预算继续资格）**：`outputs/v115_multicore/rdc_resume_20261015-094816`
- **Q2（Binding FIFO）**：`outputs/v115_multicore/rdc_resume_20261015-102913`
- **I（不可变测试调用）**：`outputs/v115_multicore/invocations`
- **旧 Root 集成证据**：`outputs/v115_multicore/root_integration_20261014`

本次机器核验记录为 `B/CODEX_HANDOFF_CAPTURE_20261015.json`，SHA256：
`83ef8a5b594ca79437d7922cab8d41b708ef8814e3ea4ffc47f101a643cb9f9e`。
它记录关键源码指纹、worktree 和 rdc124–153 中选定调用的原生结果，不是重新执行测试的回执。

## 2. 用户要求与工程边界

维持既定分工：M/Main 负责输入、UI、渲染和实际资源原语；S 是唯一 world/physics/HP/RNG/Profile 所有者；W 只执行受限的不可变纯数值/几何工作。不建立第二套世界、生命值、存档、技能规划或计时权威，不让 Main 等待 Source。

保留原战斗节拍、移动、碰撞、攻击即时性、伤害顺序、经验掉落与存档合同。不靠少怪、低频碰撞、截断 AOE、假 READY、猜 final-art 或增加任意延迟来让测试通过。300ms 规划窗口不能被解释为攻击/伤害/碰撞也每 300ms 才生效。

只在授权候选树续建。主树生产文件、原始存档、仓库装备、人工数据、素材、签名和凭据保持保护。不得 `reset --hard`、`git clean`、整树 restore、强推或为测试改动真实 index。合并、commit/push、版本发布和清理按用户授权及当前仓库规则执行；本次交接没有执行这些动作。

当前 `AGENTS.md` 明确弃用旧 GLM、dots/小可爱、旧 Harness 和队列流程。接手者按当前 AGENTS 使用 Codex 自身可用工具；直接本地读写或 RDC 均可，不要求用户搬运源码。模型/子代理分工也以当前 AGENTS 和实际可用配置为准，不把旧对话中的模型设置当成当前事实。

## 3. 当前状态：不要把局部通过升级成整游通过

| 交付层级 | 当前状态 |
|---|---|
| 多项 Native、原语、预算、FIFO、构造与 Main 接口专项 | 有各自固定来源的 PASS，见第4节 |
| 最新 Main 回调继承专项 | rdc152：58 checks，原生结果 PASS |
| 新增 Main process scope 采集模块 | 已写入；写入后语义/运行验证 NOT_RUN |
| S 持久 Profile P 更新及全局回调资格复用 | MISSING，正在施工的断点 |
| 真实 selected Profile → SourceSession → 完整 World 启动 | MISSING |
| 全资源绑定、首怪完整显示与退役、换图/退出闭环 | MISSING |
| 用户旧存档/所有角色/仓库往返 | NOT_RUN |
| Android 引擎模板 | 曾在较早 Native 指纹下构建 PASS；对当前源码不再是最新模板 |
| v115 正式游戏 APK | NOT_RUN，未生成可交付游戏包 |
| REA-AN00 手机验收 | NOT_RUN |

`B/progress.md` 与 `B/CURRENT_PROGRESS.json` 的部分描述早于最新改动。特别是直接收集 `*.result.json` 的汇总，不能取代 `native_result.json`、runner 与 PROTECTION 的最终裁决。本文说明的证据边界优先于旧描述，实际文件又优先于本文。

## 4. 已完成并必须保留的施工与证据

下列 PASS 均指对应 invocation 当时的固定源码/引擎/输入。交接时读取了正式原生结果；没有因为接手而重新运行。相关依赖变化后，仅按影响范围补做必要验证，不能累计为“当前整游总通过数”。

| 调用目录（I 下） | 已记录的结果 | 范围 |
|---|---|---|
| `rdc106_budget_scope_regression_20261015` | 预算35 checks、语义220 checks，均 PASS | 同一预算账本的继续资格与当时语义 |
| `rdc112_binding_fifo_green_20261015` | 266 checks，PASS | 同 FIFO 的有限继续处理专项 |
| `rdc113_binding_fifo_regression_20261015` | FIFO场景354 checks PASS；同调用另一语义场景 FAIL，整体退出1 | 必须分别保留，不能将 invocation 整体写成 PASS |
| `rdc115_fifo_reviewed_semantic_20261015` | 224 checks，PASS | 后续固定来源语义复核 |
| `rdc118_actual_boot_preparation_20261015` | 26 checks，PASS | Main 启动准备及阻断/清理边界，不是完整启动 |
| `rdc121_published_delivery_green_utf8_20261015` | 26 checks，PASS | 实际已发布 prefix 交付专项 |
| `rdc122_current_world_sources_20261015` | 229 checks，PASS | 当时源码语义，不覆盖其后全部改动 |
| `rdc124_premap_context_green_20261015` | 30 checks，PASS | 原始 pre-map context 的 Native/registry 合同 |
| `rdc126_main_capture_and_context_regression_20261015` | Main capture19、Main boot26、normal/cold92、LIVE17，均 PASS | 真实隔离角色创建/选择后的构造采集与相关协议 |
| `rdc130_runtime_name_keys_green_20261015` | 新专项17、已有graph14，均 PASS | runtime StringName key，严格JSON边界不变 |
| `rdc133_player_zero_life_final_20261015` | 34 checks，PASS | 真实Player/Native出生时的原 combat_epoch=0 |
| `rdc137_environment_actual_capture_20261015` | 26 checks，PASS | 正式初始环境的 pre-map 采集 |
| `rdc143_constructor_actual_values_20261015` | 148 checks，PASS | Root构造值、原sentinel与空typed数组表示 |
| `rdc145_profile_writer_gate_green_20261015` | 26 checks，PASS | Main旧Profile写入门，不是完整S接管 |
| `rdc147_lease_owner_green_20261015` | 22 checks，PASS | 完整真实物理租约集合的Main owner移交与退役 |
| `rdc149_main_physical_admission_green_20261015` | 16 checks，PASS | 7类admission接口和拒绝路径，不是正向全启动 |
| `rdc152_receiver_inheritance_20261015` | 58 checks，PASS | 17脚本回调记录、真实锻造面板继承创建/退出 |
| `rdc153_process_scope_red_20261015` | 1 check、1 failure，FAIL | 新scope文件写入前的真实 RED；写入后尚未跑 |

重要失败：`rdc132_player_zero_life_green_20261015` 虽有34个布尔检查和场景PASS，但原生结果是 FAIL，包含两处引擎断言错误；最终采用 rdc133。rdc151 名称含 green 也不代表通过，实际暴露 EnhancementPanel 继承字段冲突。失败目录、旧源码及日志均不得删除。

### 4.1 Binding FIFO：旧“NOT_IMPLEMENTED”已经过时

当前 `scripts/gameplay/enemy/enemy_owner_streaming_coordinator.gd::_live_poll_bindings` 已有最多两次尝试：先处理旧 COMMITTED 并执行原 completion，再经真实继续资格核对，最多尝试下一笔。未完成、背压、缺首绑定事实均返回，不等待、不自旋；新提交仍在原预算 scope 结束后由原 flush 发出。

已存在 `EnemyOwnerFrameBudget.capture_continuation_scope()`、`continuation_scope_decision()` 与 `SourceSession.capture_live_resource_continuation_context()`。保持同一FIFO、同一全局binding在途、同一P去重和预算公平策略。不得使用旧冻结文件把这段覆盖回单次尝试，也不得把它描述为手机FPS实测。

证据入口：Q1/Q2 的 `WORKLOG.md`、`ACTUAL_PROGRESS_RECEIPT.json`、patch/preimages，以及 rdc106/112/113/115。

### 4.2 pre-map、Player出生和构造值

原始 Root 初始 `runtime_map_id=-1/world_epoch=0` 已作为受限结构状态接入，不是伪造的活动地图。真实到图仍走原 map transaction；其他负值、任意正epoch的负map不能顺带放行。

Player原始 `combat_epoch=0` 得以保留；仅规范的初始pre-map Player可采用该出生边界。有效战斗 ActorRef 仍要求正生命期。结构scope life不能代替角色combat_epoch。读取尚未绑定的Player runtime ID已改为构造字段，而非调用会assert的绑定后getter。

`main_world_source_fields_capture.gd` 从实际原Root对象及已安装消费者字段获取构造数据；明确区分晚绑定owner对象。`source_constructor_value_codec.gd` 在精确字段边界保留原INF sentinel及空typed actor数组，不对全局JSON/存档验证放宽。

新鲜Enemy共享状态走真实原构造；已有非空Main共享状态不得被重置成“初始”。源码、字节和阶段记录在B各 `*_preimages`、`*_RECEIPT.json` 与 patch。

### 4.3 Main写入门、物理租约和admission

`PlayerState` 已安装 `_source_domain_gate`；MAIN行为保留，PREPARED/S阻止旧Main写入口。原424个方法主体经生成/组合时比对保留。普通 `_process`、暂停receipt child、三类suspend通知有针对性边界处理，不能恢复旧Main与S双写。

`FeatureResourceLease` 增加真实物理lease弱索引和完整集合owner移交。索引本身不是第二个缓存、资源owner或调度器；同一Texture、原签名、subset和PREDELETE义务保持。

既有7个 Native source-admission 操作已有Main dispatch和provider binding；ContentLayers切换必须匹配实际事务证明。相关文件：`feature_resource_main_primitives.gd`、`main_source_admission.gd`、`content_layer_registry.gd`、`main_root_checkpoint_ports.gd`。已移交物理所有权后，不得将失败路径恢复成旧Main写者。

仍需真实正向 selected-profile adoption；接口存在/拒绝测试通过不提供这一证明。还有一处确定的Native固定源码指纹陈旧，详见第8节。

### 4.4 17份Main脚本的回调账本

目标：startup_loading、character_select、game_data、content_layer_registry、game_mode_service、domain_runtime_services、runtime_service_facade、equipment_character_preview、device_lab_runtime、hud、inventory_panel、enhancement_panel、item_detail_presenter、quest_panel、shop_panel、skill_panel、warehouse_panel。

170个原方法加入进入/返回深度记录，await期间保留在途记录。最终保留方法名带脚本限定，如 `_original_source_game_data_item_usage_summary`，避免基类wrapper动态分派回派生实现造成递归。

EnhancementPanel的账本继承InventoryPanel，不再重复声明。rdc152实际创建基类/派生面板、生成9个forge slots、refresh并退出。

**实际生效manifest是** `scripts/gameplay/source/main_original_receiver_manifest.json`，SHA256：
`1cf99c8245eae4f96b532443924c527886d146233f7c0c26411905125893a070`。

`B/receiver_tracking/MANIFEST.json` 的 `af719e...` 是继承修复前阶段文件，不能当当前manifest。`INHERITANCE_FIX.json` 中生成时的NOT_RUN由后续rdc152限定范围运行结果补充，不能直接改旧回执冒充重新验证。

相关生成/修复脚本大多是精确preimage的一次性脚本；读取用来理解差异，不要原样重跑覆盖当前文件。

## 5. 精确停笔位置：先完成这里

### 5.1 刚写入、尚未测试的文件

`R/scripts/gameplay/source/main_original_process_scope.gd`

SHA256：`5e4bfe4eb6a6292c31fc97770e6cad09bbddbc69589047222e7880af4ee4f57f`，3005 bytes。

提供 `capture_existing(node)`：采集实际Main节点的父级、源路径、P/H开关与优先级、继承后的process mode、脚本指纹和Engine帧；拒绝离树、queued-for-deletion及不合法来源。该文件当前没有生产消费者，不能因为写入就宣称完成scope接管。

需审查其范围：structural life来自原Scope初生默认，不能当作观察到的角色生命期；`source_entry`、没有脚本的Node、继承模式、internal child索引必须与实际消费合同相符。测试通过也只能证明该采集组件，不是整条Profile接管。

现有测试：`tests/framework/main_process_scope_capture_20261015.gd/.tscn`。运行器：`B/run_process_scope.ps1`。rdc153的失败发生在文件不存在时；现在应运行写入后的新调用，不要修改/覆盖rdc153。

### 5.2 S里漏接原Profile P更新

原 `PlayerState._process(delta)` 顺序是先 `_model.service_receipts()`，再 `_model.step_process(delta)`。`ProfileModel.step_process` 内推进临时物品buff、耐久、relic proc与自动保存时间。

交接源码中，Session已创建 `_profile_scope`，但World仍按boot再创建 `player_state` scope，且实际原Profile P回调未完整注册。持久Feature/PlayerState又被放进Root局部源树绑定，不能正确表达它们在真实SceneTree中的持久位置与跨world寿命。

检查入口：
`source_session.gd`、`world_simulation_core.gd`、`world_root_phase_adapter.gd`、`source_persistent_path_tree.gd`、`world_temporal_scope.gd`、`player_state.gd`、`paused_receipt_pump.gd`。

接手实现的验收语义：复用同一Session持久Profile及scope；在原P位置执行一次原更新；保留P signal服务与Node `_process` 的区别，避免receipt漏泵或双泵；按真实优先级和全局source path合并顺序；普通world退出不销毁持久Profile/Feature；暂停、无world阶段和最终session退出各按既有合同处理。不能以“多调用一次step_process”代替接线完整性。

`B/check_persistent_process_wiring.py` 已产生 `persistent_process_red.json`：8个静态检查中7个失败。里面预期的 `original_profile_process_scope`、`original_persistent_callback_order` 是待接线名称，不是已经存在的接口。

**此脚本只是源码接线提示，不是唯一实现规格，更不是运行验收。** 不得只添加同名空方法或改变字符串以拿PASS。补实际Native/S回调、顺序、暂停、跨world和退役验证。

### 5.3 采集时序不可颠倒

Main source admission的PREPARED阶段会禁用原节点processing并断开旧catalog callback。原scope应在这一关闭动作之前采集，或从同一已验证的原flags回执交接；不能把关闭后的false误当原合法P开关。

`main_world_source_fields_capture.capture_original_constructor_fields` 要求原Root尚未入树；而后续world provider要求guarded Root已入树。必须安排正确的前采集、后挂载/装配顺序，不能简单删掉两边校验让它们“兼容”。RNG仅按原Source ready初始化一次，不在准备失败/重试中重复消耗。

## 6. 断点之后仍需完成的集成链

建议按下面依赖顺序逐项闭合。具体实现继续从当前源码和已交付模块取，不重新搭第二套框架。

### A. 持久scope与coordinator原状态交接

完成第5节；同时核对 `main_source_admission.capture_original_resource_idle_state` 已生成的原coordinator游标/计数是否真正由S采用。当前Session/Coordinator中未找到 `configure_original_idle_handoff` 的实际接入。

可参考冻结donor `outputs/v115_multicore/main_source_admission_20261014/coordinator_idle_handoff.gd.append`，但只能在当前Coordinator上按差异组合，保留已接的LIVE/issued-claim/retirement逻辑。不能将已接受队列清空后声称idle。改动Coordinator会影响Native的固定SOURCE_SHA，必须联动复核和重建。

### B. Main启动生产者与checkpoint

`main_boot_application.gd` 的 `capture_actual_original_world_loading_assembly`、`capture_actual_original_selected_session_fields`、完整world pin检查/释放仍存在明确BLOCKED返回。已有pre-map、环境和constructor leaf没有自动形成完整装配。

需贯通实际launchLoading/rootTransport、真实selected loaded Profile、原source scopes/树位置、时钟与容量policy、catalog、完整view/actor/resource闭包。不得手写session ID、节点ID、假scope或READY。

当前 `main_root_checkpoint_router` 的 `_valid_world` 仍要求非负map，而初始原Root是受限pre-map -1；`verify_original_loading_source_site` 返回source_site但尚无Source所需的 `loading_scope`。这是需要按已确定初始合同贯通的具体边界，不是放宽所有world/Loading校验的许可。

Main receiver账本已存在，但实际router/manifest安装、launch stack关闭、IO终态和源树发布仍须正向验证。不要把“17文件有账本”直接记为“所有旧回调已安全停止”。

### C. 唯一SourceSession安装与epoch0 Core出生

重新核验的实际链：
`source_session_runtime.gd::_init` → `Installation.create_original_session_services(host,boot)` → `create_original_session_services_with_actual_bindings(host,boot,{})`。

默认仍传空actual bindings。真实 `directory`、`feature_retirement`、`main_io`、`WorldViewTransport`、`WorldAudioProjection`、`WorldUiLoading`、`WorldMapLoadingAdmission` 等外部owner必须接入。对照当前 `SourceSessionFactory.PROVIDER_ABI` 与 Installation.required，不得用has_method空壳、空字典或always-ready覆盖缺口。

已有 `source_application_providers.gd` 也不能仅凭接口当作完整实现；其Native方法/能力、真实结果来源须逐项验证。

启动顺序保持：Main真实选择/载入角色 → 合法PREPARED → 同一Native epoch0内唯一S adoption及Core构造。不能先建无角色Session再造第二次接管路径。换同角色地图保留Session/Profile/持久寻路；换角色须旧world/session/Host终态完成后才能由Main载入下一角色。

### D. 完整Main表现/资产/输入/地图

保留实际 `ACTOR_HEADER`、`VISUAL_HEADER`、同一Native prefix、空Node2D shell及后续复用。空结构头不是BodySprite/Texture/完整资产就绪。不能提前制造service ID、BindingFact、final_art或首帧snapshot。

`actor_main_asset_port.gd` 要求真实完整pin；Caster sequence lease不证明所有player/enemy/map资源都已持有。补实际vault生产者、renderer登记、source overlay roots、代码lease、map IO/pin、完整publication与物理/GPU退役。

补Player真实Visual child P、signals、first full snapshot/overhead的合法时机、life/map rebind。Source Player没有原 `_process`，不能再注册不存在的Player P；真实Visual child P不能用PUBLISH冒充。

Main普通prefix/primitive pump、HUD有序输入、原Root通知及ui_cancel都要接实际消费者。原 `GameRoot._notification` 与Profile suspend notification不是同一回调，不能互相冒名代替。

MapLoading严格沿既有reserve/append/register-prefix/accept、真实Loading scope、RETAINED与IO终态及动态到图提交，不新建平行队列或简单更改world_epoch冒充map generation。

### E. 关闭与回收

关输入准入不等于抹掉已提交输入。旧Core/Session保留，直到已接受journal、UI命令、caster、ResourceLoader claim、writer、renderer和实际pin均终态。继续用实际Main process-frame → Native closing Signal/Service；worker完成只是唤醒，不生成P/H或模拟时间。

同一预算结束后原flush；真实STOP/highwater/ACK完成后才最终释放/join。队列为空、模型退出或Native ack单独都不是全部物理资源/存档完成证明。也不能用强杀进程作为通过的退出测试。

## 7. 尚待用户决定的产品边界

截至本次能取得的用户记录，没有找到批准“首次真实binding前，单角色死亡尾部等待binding”的明确答复。

原死亡8218附近依赖 `uses_final_art`；后续 `died`、经验和掉落通知位于其后。不能猜true/false，不能把过期事实当当前，不能不经批准改变死亡/尸体/退役/XP/drop时序，也不能为等待该事实挂起整个S。

旧Pro摘要位于 Root 集成目录的 `PRO_ENEMY_BIRTH_RULING_20261015.md`、`PRO_ENEMY_BIRTH_LIFECYCLE_RULING_20261015.md`。它们是技术讨论摘要，不是用户产品批准或当前完整源码审计。先完成不依赖该选择的技术工作；此选择继续明确BLOCKED，不能悄悄采用方案。

历史buff/debuff公共平台讨论是另一研究范围，不能因本交接顺带改DOT周期、新技能系数、状态上限或建设新的通用job图。

## 8. Native源码封印与构建：当前有确定陈旧项

### 8.1 Windows组件运行器

当前近期专项使用：
`B/windows_runtime_names_build/Godot_v115-stable_win64_console.exe`

同目录主exe必须一起保留。该次BUILD_WINDOWS_ONLY_PASS的源码汇总SHA：
`d7de5e202dfc2d29e7a19ed5c54d9f0ce3318899fb51d4fc051a62b3ffa834a5`。

console SHA256：`8e09cc453f0b1514305fdf571839ab86551510a97a0356dce816b5ddeeb293a2`

主exe SHA256：`0b026597463c1b8f08a314c3e9b901a441df57f053f58adf239e862f38b3965e`

它支持已构建的pre-map/runtime-name Native组件，不代表后来修改的所有GD与Native固定绑定匹配。

### 8.2 必须修复的固定指纹

当前Main Feature GD实际SHA：
`4949264472dbf69363ba09142fa7afab5537a8278af2c26767d5e39e9331e289`

但 `native/hardcore_simulation/feature_live_source_seal.h` 的 `FEATURE_LIVE_SOURCE_SHA` 与 `simulation_host_issued_claims.cpp` 的 `FEATURE_SHA` 仍为旧：
`8ba682d8213ad51853a663ca9fe227a49ed91a8efdd5bfdf50812544e8854768`。

因此当前实际正向绑定存在阻断。必须先审阅当前GD，再按真实 `Script.get_source_code().sha256_text()` 与文件字节/换行的既有规则更新对应封印、同步E的module镜像、生成新的输入manifest并重建。**禁止删除或绕过源码身份校验。**

Coordinator当前SHA与Native `SOURCE_SHA` 仍同为：
`34b776edb609e887be1fbd83b2236ba6f89a0c86eb1acacc06e8acc16eeea3e6`。
这不代表未来加idle handoff后仍匹配；修改后必须重新检查。同理审查Warm、Map及其他被固定封印的依赖，不能只机械替换一个字符串。

### 8.3 Android模板不是游戏包

`F/android_current_native/BUILD_RECEIPT.json` 记录早期arm64 debug/release模板及Gradle生成通过，来源SHA：
`a501f5b0ebceb442bc4fd13f06a32b06186dca41b1b327beab4b94179feafe00`。

目录中的 `android_debug.apk`、`android_release.apk` 是引擎模板，不是包含当前游戏内容的115交付包；该目录名中的“current”只是当时命名，不能推断它现在仍是最新。它们早于后续pre-map/runtime-name和新的封印变更。完整源码固定后重新构建/校验匹配的Android模板，再导出游戏。

交接时R无 `override.cfg`，`project.godot` 未显式启用external_owner_mode；不得把fixture的临时override作为正式开关发布。最终必须证实实际游戏在已集成的多线程路径运行，而非靠保持旧串行路径掩盖缺口。

## 9. 接手执行与测试命令

### 9.1 开工只读预检

先读 `AGENTS.md`，运行bootstrap，读 `PROJECT_CURRENT_STATUS.md`、`PROJECT_INDEX.md`、`docs/WORKSPACE_CURRENT_STATUS.md`、`PROJECT_CORE_CONTRACTS.md`。旧文档只用于定位；当前字节和当前规则优先。

```powershell
$R = 'C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore'
$E = 'C:/Users/Administrator/Documents/HardCore-engine-v115/godot'
$B = Join-Path $R 'outputs/v115_multicore/rdc_boot_20261015_1318'
$env:GIT_OPTIONAL_LOCKS = '0'
Set-Location $R
Get-Content AGENTS.md -Encoding UTF8
& .\tools\agent_bootstrap.ps1 -Compact
git rev-parse HEAD
git status --short --untracked-files=all
git worktree list --porcelain
$Index = (git rev-parse --path-format=absolute --git-path index).Trim()
Get-FileHash -LiteralPath $Index -Algorithm SHA256
git -C $E rev-parse HEAD
```

此前bootstrap在detached分支触发过Null.Trim错误；若重现，记录该原因并完成等价Git/index/进程保护预检，不修改门禁规避。接手前后原index不同须先查明，不覆盖用户新改动。

### 9.2 第一个实际测试

以下命令是供Codex接手后执行，**本次报告未执行**。使用新的唯一Label：

```powershell
Set-Location $R
$Label = 'codex_process_scope_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
& (Join-Path $B 'run_process_scope.ps1') -Label $Label
```

先查看结果再继续。失败按实际解析/断言/生命周期原因修复，保持RED证据。成功只记“Main scope采集专项PASS”，不要记Profile P wiring或fullworld PASS。

后续可在完成接线后另跑静态提示脚本（不是运行验收）：

```powershell
$Py = 'C:/Users/Administrator/AppData/Local/Programs/Python/Python312/python.exe'
$Name = 'persistent_process_after_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
& $Py (Join-Path $B 'check_persistent_process_wiring.py') $Name
```

gdtoolkit冻结parser_runtime中的regex扩展为cp311，不能拿默认Python312硬跑；可用已发现的解释器：
`C:/Users/Administrator/AppData/Roaming/uv/python/cpython-3.11.15-windows-x86_64-none/python.exe`。
仅需该冻结解析环境时使用，不盲目升级全局依赖或重装工具。

### 9.3 证据链要求

优先使用 `tools/run_multicore_v115_tests.ps1`，它包裹正式runner并使用私有测试index、隔离APPDATA和不可变invocation目录。Label不复用；普通场景30秒，已登记重场景60秒。原生运行期间冻结被测源码、engine、binary和相关输入。

每次结论至少核对本次 `PROTECTION.json`、`SOURCE_BINDING.json`、`SOURCE_MANIFEST.json`、`logs/runner_results_*.json`、对应 `native/<run>/native_result.json` 与匹配scene/run/invocation的场景receipt。不能读 `outputs/test_logs/framework` 的旧文件替代本次结果。

修改17个已登记Main脚本后要更新/校验实际manifest来源；修改固定Script SHA后要同步Native构建。不要更新expected hash却不审查差异，也不要保留旧expected让必然失败被误判为运行根因。

## 10. 存档、APK、设备与最终里程碑

PC原始用户数据只读备份入口：`F/PC_SAVE_BACKUP_POINTER.json`。
实际备份：
`C:/Users/Administrator/Documents/HardCore-progress-backups/v115-pretest-pc-saves-20261015-114316/ORIGINAL_PC_USERDATA_READONLY_COPY.zip`

SHA256：`d32b185ad5752ea240f310c01e61e93d0a0761fc738b26be3f8c6cd6656245ef`。
这是PC数据，不是Android当前存档证明。交接归档再次对325个既有PC数据文件逐项核对未变；“未修改”与“新架构读取/保存兼容性通过”是两回事。

先在隔离副本做：所有角色枚举/选择/进入/退出/再载入；等级、职业、技能、装备、金币、仓库与物品实例身份保持；装备/卸装、背包与仓库双向转移、保存/重启、多角色切换、失败回滚和已接受writer完成。销毁验证仅在隔离副本进行。不得用真实存档做破坏性验收，不改坏档校验来吞数据。

然后审查当前相关diff、固定构建源码与引擎指纹，按既有流程处理Git集成。导出时保持 `com.personal.mafaoffline` 和原签名，versionCode合法递增；游戏/人物选择版本显示同步115。记录APK绝对路径、大小、SHA256、包名、版本和签名证书校验结果。不能用卸载清数据、换debug签名或降级绕过兼容性问题。

REA-AN00再验同蜈蚣洞20–30只密集怪物，并覆盖约30–40只设计峰值。攻击和当前接触保持即时；分别记录完成工作量、Main/S/W CPU、队列与实际服务延迟、P50/P95/P99/最大帧间隔、内存和持续运行表现。PC组件微秒值或条件FIFO槽位公式不等于手机流畅保证。

只有完整启动、战斗/换图/关闭、存档仓库、匹配源码APK和独立设备验收达到各自标准，才能宣布最终里程碑。清理工作树和占用空间安排在验收及授权之后，先保存独有提交/dirty/untracked/源码证据/引擎修改；不要现在清理115候选来“整理环境”。

## 11. 最新备份与恢复

本次交接已运行现有 `B/preserve_current.py`，生成新的源码/证据备份，覆盖到rdc153之后刚写入的scope模块。

```
C:/Users/Administrator/Documents/HardCore-progress-backups/v115-rdc-boot-20261015-174530/SOURCE_AND_EVIDENCE_DELTA.zip
```

- 大小：45,315,330 bytes；文件数：3,189。
- SHA256：`e08173e776aa007d217b2532116cf528089a3343699309d92ab9778f6a6469b7`。
- 回执记录ZIP CRC、逐文件SHA及归档期间源文件一致性核验成功。
- 同时核对325个原PC用户数据文件未变。
- 精确回执在同目录 `PRESERVATION_RECEIPT.json`，指针为 `B/PRESERVATION_POINTER.json`。

父级包：
`C:/Users/Administrator/Documents/HardCore-progress-backups/v115-rdc-world-template-20261015-130840/SOURCE_AND_EVIDENCE_DELTA.zip`

父包SHA256：`a0ce520172a2ad9d352985beb11f9a5c1903b018b6a942bbb072b2d97a8dbec6`。

更早Binding阶段包：
`C:/Users/Administrator/Documents/HardCore-progress-backups/v115-rdc-binding-20261015-111834/RDC_SOURCE_AND_EVIDENCE_DELTA.zip`

历史记录SHA256：`974a6570b0e1ed217739a67918e0667332107093316116aedaa4d01423ad5a2f`；需要恢复时按其实际回执再核验，不能仅凭本文替代校验。

保留更早base/delta/incremental及Frozen交付；按各manifest和parent指针组合恢复，不整树覆盖较新工作区。新包是源码和证据增量，不是含全部大素材、完整Git历史、完整引擎和编译产物的独立工程镜像。Windows/Android编译产物留原工作区，重建或复用前另核验。

本报告在上述ZIP之后生成，作为单独交接文件交付；不要宣称该ZIP已经包含最终报告文本。归档helper的 `CURRENT_PROGRESS.json` 含raw场景状态汇总，仍需第9节正式结果链裁决，特别rdc132/113/151。

## 12. 关键接手文件指纹

以下为本次现场读取值，用来发现漂移，不是让接手者强制恢复旧内容。存在新改动先查来源，再组合。

| 相对R的文件 | SHA256 |
|---|---|
| `scripts/player_state.gd` | `ca7c2cd98938bc52240ba7b5412d93cdb2587935c03ef42eccee1669ceb4a4e3` |
| `scripts/features/contracts/feature_resource_lease.gd` | `39aca468c3d729e14fc51a6f9367ffe8e5d4e72b276de0f687cde592ac6bf7c1` |
| `scripts/features/runtime/feature_resource_main_primitives.gd` | `4949264472dbf69363ba09142fa7afab5537a8278af2c26767d5e39e9331e289` |
| `scripts/features/runtime/feature_resource_owner_coordinator.gd` | `34b776edb609e887be1fbd83b2236ba6f89a0c86eb1acacc06e8acc16eeea3e6` |
| `scripts/gameplay/source/main_source_admission.gd` | `7ce0554e27180b8fe1e4e54d39fc27b8b7af3b33d42fafdae50437ab80f8e2c4` |
| `scripts/gameplay/source/source_session.gd` | `6a39007423459149f30065fa95b046c797802e33fd373c667645f9c1017b3a75` |
| `scripts/gameplay/world/world_simulation_core.gd` | `ed8c48e0b5ce92bb18e47944fad51d35eda310504aaef4a1e4c1b5fb52882b47` |
| `scripts/gameplay/world/world_root_phase_adapter.gd` | `743afafc983f0e45ddbe735da82469f12110c8df6f9d22ee66bdd4422d3844be` |
| `scripts/gameplay/source/main_original_receiver_manifest.json` | `1cf99c8245eae4f96b532443924c527886d146233f7c0c26411905125893a070` |
| `scripts/gameplay/source/main_original_process_scope.gd` | `5e4bfe4eb6a6292c31fc97770e6cad09bbddbc69589047222e7880af4ee4f57f` |

## 13. 避免重复施工的最终提醒

先完成新scope专项和持久Profile原P接线，不回头重写已验证的FIFO、Player零生命期或constructor codec。变更跨多个冻结包重叠文件时，依据当前preimage逐段组合，保留Main/Map/Feature/Caster/Close/Path已经接入的全部义务。

阶段汇报只陈述：实际修改、固定来源、完成的验证、仍MISSING/BLOCKED/NOT_RUN的项和下一处具体生产断点。需要持续施工时继续推进，不把局部PASS当停止条件；遇到产品选择只冻结受影响路径，其余已授权技术工作继续。

交接结束状态仍是：**完整世界MISSING；最新scope模块写入后NOT_RUN；旧档仓库往返NOT_RUN；115游戏APK NOT_RUN；设备NOT_RUN。已保留的源码、历史证据和最新备份足以继续排查与集成，但不构成游戏已完成的证明。**
