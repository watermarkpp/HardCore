# HardCore v115 续工交接：未完成游戏交付

最后冻结：2026-10-18T04:09:53（本机时间）。实时额度98%已用/2%剩余，按用户先前要求在此完成交接后停止。不是完成115，不关机。默认单人施工，禁止子代理。所有进程已结束，没有后台构建或测试待接管。不要 reset/clean/stash/整树覆盖，不动主树、真实存档、仓库、签名。Pro旧建议只作待核验资料。

## 1. 唯一实际施工现场

- R：`C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore`，detached HEAD `45170d0eaf4d2c642d4a03de392f64fa2b1e25bf`。
- M：`C:/Users/Administrator/Documents/HardCore`，`codex/integration`同HEAD，本轮没有施工到M。
- E：`C:/Users/Administrator/Documents/HardCore-engine-v115/godot`，引擎HEAD `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`，保留全部dirty/untracked。
- 真索引：`M/.git/worktrees/HardCore1/index`，SHA256 `3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22`。所有已结束专项/World保护均保持相同。
- O：`R/outputs/v115_multicore/codex_resume_20261015_182255`；D：`O/codex_return_20261017_01`；全部实际测试在 `R/outputs/v115_multicore/invocations`。
- 先完整读当前AGENTS及本报告，再读D/CURRENT_STATE_20261018.json、D/CONTINUATION.md；它们包含实际最新断点。不要从旧HEAD重新搭建。当前不是旧10月15日断点。

## 2. 当前最重要的两个未闭合问题

### A. Native不可变前缀优化的Packed资格缺口（必须修）

已经定位到Main数据准备/提交重复工作：World39 native_acquire累计19,377,893us，Native ACK15,590,475us，inspect6,643,193us；actor_visual_projection约993,250us。旧prefix_wire多次遍历、整包两遍编码、逐事件编码，acquire又深copy。同一已接受数据反复转换。

已在R/E两个匹配文件实现真实FIFO快照复用：`native/hardcore_simulation/simulation_host.h`、`simulation_host_original_primitives.cpp`。Main保存真实已接受Wire与其深只读Dictionary；严格Dictionary.id/保留引用/bridge generation匹配才复用；外来/可变副本走原完整校验；delta事件仍独立thaw可变，原Native claim/ACK/Source退役没有绕过。普通嵌套Dictionary/Array专项实际31/0，六场景6/6PASS。

**但037候选有安全缺口，不能发布：Packed数组的Variant别名共享PackedArrayRef，父Dictionary只读并不能冻结它。** Pro对照实际引擎实现发现，已用真正Native组件复现。`codex_packed_retiring_RED_20261018_01`的Packed场景实际30项/3失败、native1、无ScriptErrors、源/索引保护true。别名修改空/非空Packed后，同顶层id的重复inspect被污染。

下一步最小修复：先遍历整棵已解码树（key/value及所有嵌套Array），出现任一种Packed数组就**只取消此prefix的缓存资格**，保留原独立decode、原prefix_wire验证。不拒绝plain中的Packed，不改类型，不复制一次后继续共享，不部分seal后交给fallback。包括空Packed也拒绝缓存。非Packed继续当前优化。不要在命中时重新全树扫描。实际10种Packed枚举在E/core/variant/variant.h:134–143。

测试：`tests/framework/publication_prefix_packed_20261018.gd/.tscn`及helper已写入并实际RED；普通不可变31项场景也保留。继续补独立delta修改不污染快照、旧快照/下一前缀、合法等值副本和外来Host等对应边界。原完整验收不得弱化。

### B. 完整退出到最终free，真实ServiceRegistry查询缺失

World38先定位到原关闭SERVICE早于Root子树exit，错误调用严格port得到`actual_original_actor_exit_before_Node_retirement`，失败被缓存后bool接口又永久压成PENDING。已修正实际producer及唯一consumer：Lifecycle只在同一原actor scope.exit_callbacks_complete后调用严格port；返回Dictionary，真实INVALID上报，READY才置位。严格canonical/回调/NodeAbsent/资产检查未改，真实failure不清除。Pro已实际只读复核通过这两处顺序迁移。

**World40实际验证了这条修复前进：82/82首次显示、全部Renderer真实READY、通过Root第16步并进入原final-free。** 然后在`world_simulation_core.gd::_free_original_service_at_checkpoint`调用缺失的 `service_registry.resolve_original_retiring_service(id)` 报错，所以World40整体FAIL，不能称正常退出完成。

下一步实现真正查询：`scripts/gameplay/foundation/service_registry.gd`同一owner、同一`_handles`映射里的真实手动Object ServiceHandle，仅已begin_retirement/is_retiring的句柄可返回；active/queued-only/非法/已final-free返回null。原resolve_service拒绝retiring用于新任务，必须保持。不得创建影子句柄或空接口；不提前free或清任务。`service_handle.gd::begin_retirement`只改registered/retiring，不删除句柄，final_free_service才从真实表移除并free。

已增强 `tests/framework/multicore_service_registry_core_20261014.gd` 的真实驱动/调度器生命周期断言。但旧Main场景`multicore_service_registry_20261014.gd`在到达Core前即失败：_ready里for_tree/add_child时parent busy；Native start配置缺当前必需整数字段。该组件目前**BLOCKED（新查询断言NOT_RUN）**，不是已取得纯查询RED。修其生产一致的开场/配置后再验；不要把这些错误混作业务失败。World40的真实missing-method报错独立证明生产缺口。

## 3. 真实证据与限制

- `codex_immutable_prefix_native_20261018_01`：6/6PASS，Native0/no engine errors/source-index preserved。包含不可变31/0、语义336/0、Main原借用协议、三项实际namespace/symbol/fold capture。**不覆盖Packed安全，不是游戏完成。**
- `codex_full_world_immutable_prefix_20261018_40`：FAIL，82/82、Renderer READY、Root16之后final-free missing method。所有原始日志/receipt/保护完整保留。
- `codex_packed_retiring_RED_20261018_01`：Packed实际30/3；旧service场景启动失败，缺有效framework receipt。两者分类见上，整个invocation Native1/源索引保护true。
- World35/36/39首因明确为原`initial_bootstrap_timeout`，不是waiter丢失；后来的generation无效是取消结果。原60000ms游戏保护未改。新的Native优化在World40明显缩短Main确认，示例ACK由旧15ms到13us，但不要据不同进度总量宣称严格百分比，也不是手机流畅性证据。
- 完整World正常退出：FAIL；六阶段旧档仓库：0/6、NOT_RUN；fixed release对象：NOT_RUN；APK115：不存在；设备验收：NOT_RUN。
- 未批准的首次绑定前死亡尾部、经验/掉落时序仍BLOCKED，未改。保留Binding FIFO有限两次尝试、Player原combat_epoch=0、构造值codec、Main写门、物理租约及继承回调修复。

## 4. 037引擎与工具（构建成功≠安全交付）

- 当前Native `037be686708445d86cc4abc6bd6b13072f3de9e67ebeb6b32051d45434415cfb`；`O/SOURCE_MANIFEST.immutable_prefix_cache_20261018.json` SHA256 `422f0773560e1a3cc07c1d92ea8b86b13a3445204e05662cb78063dfd322c06c`，171输入、五GDS封印。
- Windows：`O/windows_immutable_prefix_cache_20261018_build/BUILD_RECEIPT.json`实际PASS；Main PE SHA `f26c17c00fb11f1a2dcb07d3b079d744554bf0355a2e3e2642bb15ed55a6d373`，实际console SHA见receipt。
- Android：`O/android_immutable_prefix_cache_20261018_build/ANDROID_TEMPLATE_RECEIPT.json`实际PASS，四JNI/Gradle/pre-post。**这是带已知Packed缺口的037模板，修Native后必须重新封印并重建。**
- 新真实capture后通过正式producer生成的 `scripts/features/generated/internal_code_preparation_catalog_data.gd` SHA `4af4b5c303dcd49ab8920261c1952535a717716f9e0a14d236c75f036251ed21`；receipt在`O/immutable_prefix_code_catalogue_20261018`。后续新PE也须用新的真实capture/正式生成链重生成。
- 当前World wrapper：`D/run_full_world_immutable_prefix_20261018.ps1`；调用Label必须唯一。Native变更后派生新文件/新hash/新引擎路径，不能篡改037旧证据。180秒例外只覆盖完整World冷启动→正常退出；30普通/60重场景，六旧档每阶段180另有用户授权。游戏60秒时限与攻击时序不变。
- 已准备（仅AST/help/绑定，没有执行snapshot）：`R/outputs/v115_multicore/source_save_runtime_immutable_prefix180_20261018`，以及 `fixed_release_snapshot_immutable_prefix_20261018`，D/delivery_config.037_pending_world_20261018.json。三runner guard+fixture原字节保持，private Git API复用原41/0证据。Native改后须按新seal/PE/模板重绑；不降低真实World PASS/native0/no leaks/source/index条件。
- 构建工具：`tools/build_hardcore_android_templates.py --help`；本机SDK `M/tools/android-build/sdk`，JDK `M/tools/android-build/jdk/jdk-17.0.20+8`，SCons `R/outputs/v115_multicore/build_prep/venv/Scripts/scons.exe`，Java临时目录`D:/Android/v115_java_tmp`。Windows builder为O/build_windows_immutable_prefix_cache_20261018.py，只能派生新封印版本，勿覆盖已完成产物。

## 5. 最短续工顺序

1. 确认本冻结身份和全部dirty/untracked，完成AGENTS预检。没有运行任务、没有代理。
2. 修Packed缓存资格和真实retiring查询；恢复旧service测试的当前生产启动合同。复用已有不受影响证据；所有新增路径做对应验证。
3. Native改动R/E精确镜像、生成新171输入/五封印，构建匹配Windows与Android；保留旧037/fc43全部文件。
4. 新引擎跑普通不可变、Packed、真实service生命周期及相关Native/语义回归；新PE真实namespace/symbol/fold capture后正式生成目录。
5. 新固定候选跑180秒完整World到真实正常退出/九owner解绑/无泄漏。不要停在组件PASS。
6. 按真实World PASS创建隔离snapshot，warrior/wizard/taoist各deposit→withdraw共六阶段180s，保留等级/技能/全装备属性UID/钱/背包/仓库往返；失败继续分类修复。
7. private Git固定源码并审差异，匹配新模板、原包名`com.personal.mafaoffline`、原签名、版本115及选人版本文字。真实APK内容/SHA/签名校验，再隔离安装/设备验证。不得卸载清数据或改debug key绕覆盖。

## 6. 数据与交接位置

真实PC数据 `C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/HardCore` 未用于测试写入。所有测试使用正式runner隔离APPDATA。原始只读备份仍在 `C:/Users/Administrator/Documents/HardCore-progress-backups/v115-pretest-pc-saves-20261015-114316/ORIGINAL_PC_USERDATA_READONLY_COPY.zip`，1062419字节，SHA `d32b185ad5752ea240f310c01e61e93d0a0761fc738b26be3f8c6cd6656245ef`。

旧档只读corpus在 `R/outputs/v115_multicore/source_save_roundtrip_parallel_20261017`（13 profiles/325 files）。不要覆盖真实人工数据。114基线仍是桌面 `HardCore-v114-optimized-debug.apk`，SHA `bb2568b940df66576b6b98bb9864634d4faa58f6941245e8270c7063c5571552`。

Pro正确官方会话为“继续施工项目”：`https://chatgpt.com/g/g-p-6a489c5ed68481919473c4a1128c4a54-you-xi-zhi-zuo-xiang-mu/c/6ad33df3-0220-83ea-af31-a08cbdb27f8c`。Chrome browser3/tab1062888678。AX可能陈旧，实际可见DOM与截图才是本轮；两个最终审查的末段已抽取在本交接reviews目录。不要动用户Tripo页面。Pro本轮只获只读建议，未发施工/测试授权；由用户启动后续RDC施工。

本交接`engine_delta/`是已封印的有限源码补充集，不是整棵本地引擎或工具链。`continuation_tools/`只是原路径脚本的归档，不可直接从新深度执行；先核对原D/O路径和哈希。一些producer是一次性已应用，不能重跑覆盖当前进度。

远端将新增专用handoff分支 `codex/v115-rdc-handoff-20261018`，以17日handoff `b9ec04fb90ca4b6430f0dde365523ec443b6056b` 为父提交，保存当前R源码与本补充证据。不会移动R HEAD、真索引或主树分支，不合并、不强推、不删除。最终远端commit与验证回执写入桌面报告末尾及D/HANDOFF_REMOTE_RECEIPT_20261018.json。此处不伪造尚未发布的commit。
