# HardCore v115 → Pro / RDC 施工交接（2026-10-17）

## 0. 接手结论：继续现有施工，不重新搭建

用户明确要求在合适节点停下、桌面交接，并同步远端。这是主动交接，不是115完成，也不是额度耗尽。游戏逻辑已冻结；主控和唯一获准的 Sol6.1 high 子代理均停止新增施工。不要从旧HEAD重新搭建，不要把本报告的组件PASS解释成游戏可玩或可打包。

**当前真实状态：完整世界启动 FAIL；正常退出 NOT_RUN；真实Source旧存档/仓库六阶段 NOT_RUN；115游戏APK NOT_RUN；设备验收 NOT_RUN。** 已保留全部dirty/untracked、引擎修改、历史实验、真实存档、原签名与失败证据。

本轮已跨过此前地图回复卡死，最新实际测试完成62个地图加载请求（prepare→资源→环境→56个build_item→finish_visual），约80.6秒时进入怪物生成与后续Root更新。接下来的准确断点是第3节两个真实接线错误，不应重做架构研究。

## 1. 实际位置和冻结身份

- **施工 R**：`C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore`
- **本机主树，仅备份，不能覆盖或擅自集成**：`C:/Users/Administrator/Documents/HardCore`
- **引擎 E**：`C:/Users/Administrator/Documents/HardCore-engine-v115/godot`
- **连续施工证据 O**：`R/outputs/v115_multicore/codex_resume_20261015_182255`
- R detached HEAD：`45170d0eaf4d2c642d4a03de392f64fa2b1e25bf`。主树codex/integration也在此HEAD，但dirty内容不同；HEAD相同绝不表示进度相同。
- 引擎 HEAD：`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`
- 真正受保护索引：`C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore1/index`
- 索引SHA256：`3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22`
- 交接前439条默认status行；展开后872个dirty/untracked文件。准确清单在`O/handoff_to_pro_20261017/DIRTY_INPUTS.json`，报告/远端证据新增文件不包含在这个较早清单中。
- 原存档：`C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/HardCore`，2026-10-17 17:06核验325文件的完整相对路径集和每个字节SHA，与只读原备份全部一致。见`O/handoff_to_pro_20261017/FINAL_PROTECTION.json`。
- `git diff --check`当前退出0；status/stat/check/worktree记录及索引字节副本均在同一目录。没有reset/clean/stash/整树恢复/移动HEAD。

先读当前R的`AGENTS.md`、`PROJECT_CURRENT_STATUS.md`、`PROJECT_INDEX.md`、`docs/WORKSPACE_CURRENT_STATUS.md`及涉及的`PROJECT_CORE_CONTRACTS.md`。bootstrap旧分支白名单故障已记录并做等价预检，不能修改门禁绕过。当前文件和Git身份优先于旧状态文档。

原始详细交接仍保留：`R/outputs/v115_multicore/rdc_boot_20261015_1318/HANDOFF_TO_CODEX_20261015.md`。之后进度以本报告及`O/CONTINUATION_CURRENT_20261016.md`为准，原报告第5节断点已经推进很多，不要倒退重做。

## 2. 远端与本地交接边界

现有origin：`git@github-hardcore:watermarkpp/HardCore.git`。本次独立交接分支：**`codex/v115-rdc-handoff-20261017`**。远端README/本报告位置：`docs/handoffs/v115-rdc-20261017/HANDOFF_TO_PRO_20261017.md`。

此分支是用户授权的**在建源码交接**，保留已知FAIL，绝不是release、验收通过或可直接交付的115。桌面同名报告旁的`HardCore_v115_Pro_RDC_REMOTE_20261017.json`将记录实际推送提交和远端读回校验。只有该收据PASS才算同步成功。

RDC接手首选直接使用现有R/E和O，避免重新clone丢掉本机导入缓存、引擎构建、真实存档和完整实验。远端额外携带95份引擎变更文件原始字节、关键工具/证据副本与定位表；引擎完整本地checkout、工具链、签名密钥、真实存档、APK和大型二进制不进Git。远端不能代替同机RDC现场。

同步采用完整私有Git目录和私有索引，父提交45170，追加对象和新远端ref；不移动主树/施工树HEAD，不修改真实索引、不force push、不自动merge。正式115固定源码对象仍需之后的真实World/存档验收，不能把交接提交充作已通过的构建输入。

## 3. 准确续接点（优先处理）

### A. 已复现、尚未修复：Source怪物出生计划漏缓存

生产文件：`scripts/features/adapters/world_target_bound.gd`。

`_capture_inputs(monster_id)`在Main分支保存`_inputs[monster_id]`，但Source分支仅`return _owner_inputs.get(monster_id)`，没有将同一输入写进当前出生计划的`_inputs`。随后`_closure()`能证明闭包，`declare_base()`第41行却读取`_inputs[monster_id]`，因此完整启动生成18/19/21/24等怪物时Dictionary越界。

**生产文件尚未改。** 父在停工前新建并完成真实RED专项：

- scene：`tests/framework/source_monster_birth_inputs_20261017.tscn`（对应.gd一起保留）
- invocation：`R/outputs/v115_multicore/invocations/codex_monster_birth_cache_red_20261017`
- 实际Main调用原`PublishedMonsterInputs.capture`取得18、19和原Enemy策略；真实Native值图捕获；实际另一个Thread创建正式WorldTargetBound，测试两轮world切换、lookup/declare/seal/admit及未知ID。
- 实际receipt：**FAIL，23检查/8失败**；原生退出1，engine errors0，正常进程退出，没有RID/ObjectDB泄漏；源码和真实索引保护true。
- 失败明确是同一published输入未存入出生计划，不是需要新生成怪物配置、降低负载或放宽身份。最小修复应将已发布的Source owner输入安装进同一个`_inputs`缓存，保留未知ID拒绝和sync_world清理；先实际GREEN此专项，再集成。

直接续跑（只在修复后用新Label）：

```powershell
$r = 'C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore'
$engine = "$r/outputs/v115_multicore/codex_resume_20261015_182255/windows_map_reply_observation_20261017_build/Godot_v115-stable_win64_console.exe"
& "$r/tools/run_multicore_v115_tests.ps1" -Label pro_monster_birth_cache_green_20261017_01 -TestPaths tests/framework/source_monster_birth_inputs_20261017.tscn -GodotExecutable $engine -TimeoutSeconds 30
if ($LASTEXITCODE -ne 0) { throw 'Preserve FAIL and diagnose' }
```

### B. 已定位、未实施：首次切图的视口publication仍绑定boot身份

- `world_visual_viewport_port.gd::root_viewport_snapshot()`要求`_publication.world_identity == core.current_world_identity()`。
- 启动时实际Main视口publication绑定boot身份`runtime_map_id=-1/world_epoch=0`。
- `world_simulation_core.gd::commit_original_source_map_arrival_context()`完成真实Native CAS并将Core/Registry/SourceSession/transport切到到达后身份。Source在同个P继续原Root流程，Main的下一份viewport尚未交回。
- 实际Root `_process → _update_world_camera_constraint → root_viewport_snapshot`因此报`actual_viewport_Root_scope_missing`，随后取空Dictionary.visible_rect出错；错误退出又触发次生`actual_native_closing_process_frame_required`。不要把次生关闭故障当作唯一根因。
- Main `world_main_views.gd::_apply_actual_original_map_arrival()`及`service_actual_Main_overlay_demands()`已存在到达提交和真实视口采样。应把这一条身份迁移链闭合，保留同Root、同Profile、严格epoch/退场保护；可研究用已被Native验证的map-arrival transaction移交同一物理视口的已有测量。**不能简单删identity校验、伪造Main测量、加延时、重试或建第二个camera。** 这是待实现建议，不是已完成设计或已PASS修复。
- 子代理曾收到后续任务，但因用户停工，**没有开始此块，没有候选patch**。父也没有改这些文件。

### 最新真实完整启动FAIL证据

`R/outputs/v115_multicore/invocations/codex_map_trace_actual_world_20261017/`

- stdout含62条完成的`HC_SOURCE_MAP_EXCHANGE`；request62=`finish_visual`实际READY；随后上述真实出生/视口错误。
- runner：`logs/runner_results_adhoc_20261017_170027_110_8872.json`
- framework：`native/60eb6141-53c3-40df-bead-06ae187c8a06/character_source_full_world_20261016.result.json`，FAIL20/1。
- runner FAIL，原生有效退出1，engine errors89；本次是早期脚本/Source故障，进程由runner收尾强制终止，**不是120秒timeout**；不能声称正常退出。
- `PROTECTION.json`源码unchanged=true、indexpreserved=true。
- 同批上游`codex_map_trace_semantic_20261017`实际PASS310/0、native0、engine0；这不能抵消World失败。

完整启动复测使用`O/run_map_reply_observation_full_world_20261017.ps1 -Label pro_full_world_after_birth_viewport_20261017_01`。只覆盖`character_source_full_world_20261016.tscn`、用户授权外部120秒、无physics override。新改动先解析/直接专项，再World，测试前更新语义输入表中确实变化文件的SHA，不可拿旧输入表冒充当前源。

## 4. 已完成并保留的关键改进（勿回退）

以下均已集成，但各自证据只限其明确范围：

1. Main原process scope捕获、Source持久Profile的同一scope复用和原P更新/真实回调继承、Profile/Main写入门、构造值codec、Player原combat_epoch=0、Binding FIFO有限两次尝试、物理租约移交。
2. 唯一SourceSession/实际Main启动生产者、Root/Player/资源/输入/地图/退出生产路径已大量接线；仍以World结果为准，不可说整合已完成。
3. Native published-prefix 32槽READY/PENDING/INVALID、Main真实ACK→SourceJournal消费、事件先reserve/register再固定可发布prefix，避免32槽满时再要第33槽；已有prefix覆盖同事件时复用真实注册prefix。
4. Journal重叠ACK严格修剪已确认历史前缀，只保留真正未ACK尾部；Native LIVE ACK推进后保留未ACK债务，避免重复/漏处理。
5. Streaming Texture escrow：已接受GET但Source尚未take不可提前关闭；实际Root ACK后才release，终态零债务；RED44/5→GREEN56/0保留。
6. 正式环境别名：home910001的真实GameData记录含legacyRuntimeMapId4；Main环境publication补发这个真实别名对应profile/theme/resource facts，Source未知ID依旧拒绝。RED19/4→GREEN19/0保留。
7. Native事件回复mailbox普通`poll()`遗漏已观察的received_usec/s_poll_epoch，导致Map结果虽然实际READY但settle/retire不一致。只修两处READY分支复制已有字段，普通poll仍不读clock、不变成首次observe。真实专项RED163/24→GREEN163/0，已重建所有平台引擎/模板。
8. 当前`project.godot`已正式声明`[physics] 2d/external_owner_mode=true`，不能只靠测试override；真实无override相关专项已PASS。
9. 角色返回/退出17信号、RNG移交/原Main恢复、9owner unbind等实现和组件证据保留，但当前完整World未过，六阶段尚未实际覆盖。
10. 已有移动碰撞约5.9%优化和历次可比实测均保留，不能靠减怪、降频、少碰撞或截断AOE制造多线程提升。

具体所有中间断点/证据：`O/CONTINUATION_CURRENT_20261016.md`（追加日志，不覆盖旧失败）、`O/CURRENT_PROGRESS.json`（其continuing字段会被本次交接终态补充）。

## 5. 当前Native/PC/Android模板严格配对（已重建，不能用旧模板）

- Native169输入聚合SHA：`58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8`
- manifest：`O/SOURCE_MANIFEST.map_reply_observation_20261017.json`
- manifest SHA：`0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178`
- 169=74 project module_inputs +95 engine changed_files；另5个reviewed GDS seals。镜像需一致，Native/E或sealed依赖变更必须重新封印并重建配套引擎/模板。
- PC receipt：`O/windows_map_reply_observation_20261017_build/BUILD_RECEIPT.json`，BUILD_WINDOWS_ONLY_PASS、native build0/prepost169。
- PC main：175887872B / SHA `7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de`
- PC console：298496B / SHA `1b69c0d26f54df88301791e5f3dbd43f7e20aad30a727addfff3287ea9d11c91`
- Android receipt：`O/android_map_reply_observation_20261017_build/ANDROID_TEMPLATE_RECEIPT.json` / SHA `45fb0e05a52ab6587529ff6742a4d46c45544f86fd4bc00dd3fd80a6ef6b7145`
- Android四份实际JNI：debug/release × arm64-v8a/x86_64；新Gradle/sourceZip/AAR/ELF/ZIPJNI一致性、Native169/seals均PASS。
- debug template67916607B / SHA `6d5f02175605c775ee0a2bd9d7e41ca60d9bd98768389a53ba7eb7d525e0f754`
- release template56908267B / SHA `1d6db066707012e53766a27fc3ebc444db9926b4898f7c9faea85babd46626dd`
- 新PC coldcapture：`codex_map_reply_observation_cold_capture_20261017`实际4场景PASS，正式code catalogue已生成：`scripts/features/generated/internal_code_preparation_catalog_data.gd` SHA `ea092df6cddf378d8b914d31b214cd400d7bb90bde2f88e84b6df54ac41dc885`。若相关编译依赖/Native/PE未变，不因接手重复。

五个sealed角色路径/SHA以manifest.reviewed_gd_seals为准。不要随意碰feature_resource_main_primitives、main_source_closing_io_producer、feature_resource_owner_coordinator、world_caster_warm_main、world_caster_warm_port导致全套重建。

## 6. 临时诊断及不能混用的证据

- 当前`world_map_loading_transport.gd`有临时可选Source Map聚合trace，默认false，仅诊断override开启。当前SHA `ce29e83170efa896cb6ca47aec28efb67afbbf71ed3ebb38a79477e99e3af037`；原255行源SHA `3d3eee21b41983fbabd309433556838b604ef16d03223607f986d2a79497f959`。
- 原字节备份`O/world_map_loading_transport.before_bounded_trace_20261017.gd`；精确集成收据`O/MAP_TRANSPORT_THROUGHPUT_TRACE_INTEGRATION_20261017.json`；冻结候选和29项静态/6mutation negatives在`R/outputs/v115_multicore/map_loading_throughput_parallel_20261017`。
- 初次git apply --check确实FAIL（core.autocrlf=false下CRLF工作文件与LF patch上下文）；随后通过原SHA/备份/候选SHA护栏做精确字节copy。原和候选均保留CRLF。不要把失败写PASS。
- trace elapsed_stage包含await/相邻调用间隔，不是独占CPU；request_variant_bytes不是Native wire大小；Main CPU观测精度较粗。此前与Android编译并行的慢启动不是可比性能数据。
- 全World fixture `tests/framework/character_source_full_world_20261016.gd` SHA `38d5060edf557fbe7e1696860438142c4db8f1265ac03a67715b7d083cdc52ca`，有实际Main reply成本和5秒progress；测试fixture允许保留。临时生产trace最终交付前按实际需要收敛，清理后源变更必须对应验证。
- 之后跨地图时，Main预发布仅home的环境是否完全覆盖后续异步切图，是待实际验证的风险；没有证据不要猜测改策略。

## 7. World正常启动/退出后，真实旧存档与仓库六阶段

当前可用包：`R/outputs/v115_multicore/source_save_runtime_observation180_20261017`。

- `SIX_STAGE_COMMANDS.md`给出完整实际命令、严格上游门、每阶段职责与失败处理；Native58a/manifest0f3/实际PC7f54+1b69已绑定。
- CANDIDATE_BINDING SHA `632fd320c0c9bb48d39e3ddcabccc473cead94fa2ee4f6d6d8e96b28d4137e09`
- DELIVERY SHA `09009248dabcadc7fac68daa62da8c243fabb7cf812b130bc0231613445bcd80`
- 六阶段：warrior deposit/withdraw、wizard deposit/withdraw、taoist deposit/withdraw；当前0/6，**全部NOT_RUN**。
- 用户已明确批准：**本场景每阶段外部诊断180秒，共六阶段**。这只影响功能测试外部上限，不改游戏时钟/技能/碰撞/追击；普通30/重场景60/另一个World120范围不扩大。
- 新建同一物理Source快照前必须提供真正World+正常退出PASS的framework receipt、同次runner_results、SOURCE_MANIFEST，以及终态PROTECTION；不能换进当前FAIL作为上游。
- 每阶段实际旧档进入→原交易存取→原SystemMenu返回选人→真实Root/hall退场、9owner unbind/RNG移交→新Host/Session/Profile读最新磁盘→正常QUIT；全部真实正式路径。
- 保留等级/XP/金币/技能熟练度、装备完整属性/实例UID/数量、背包及仓库所有权往返。法师原超重失败保留，只用原交易先存药腾负重，不能改属性、抹物品或改要求来过测。
- 真实档只读原包325文件，完整13profile原语料已冻结在`source_save_roundtrip_parallel_20261017`；不传远端，不给测试写真实APPDATA。

## 8. 固定源码工具与出包最后步骤

唯一子代理最新完整交付：`R/outputs/v115_multicore/fixed_release_snapshot_parallel_20261017`，已冻结且停止。

- `test_fixed_release_objects.py`真实私有Git专项**41/0/0NOT_RUN，原生退出0**。证明LF/CRLF/PNG/scene/project原字节archive、删除/新增、漂移、越界、真实symlink、toy二对象库追加/重复/拒绝覆盖损坏对象。
- 底层`fixed_release_objects.py` SHA `f1e1bf4f89468b161a3dd505e6d305d7228a4127c1ef00812e2e29050b733f0f`
- 正式`fixed_release_snapshot.py` SHA `d61f49943d199c3720283a5136ec6ad139c97a62c6a66a346534f5a4980e2759`
- FINAL_RESULT SHA `eb6fd4db60d9c12875a2d801b1713393f4f519cef9cfaf611c292466c10484e1`
- DELIVERY_SHA256 SHA `f9ecf1ff993c99ed50a28b091a9a298d6fb91718260bc336f60534886f62578e`
- 正式CLI保留真实World三证据门，不能加force/mock跳过；**生产release snapshot/正式CLI运行仍NOT_RUN**。交接远端使用单独非release流程，不改变这些门。
- 父级`O/delivery_current_source_binding_20261017.py`有已发现待补缺口：verify_release_sources只包括`assets/data/`，应覆盖所有已测`assets/`并增加实际PNG变更拒绝测试；原3/0+minimal actualGit证据保留，不能冒充已覆盖全部assets。**尚未修改。**
- pending配置`O/delivery_config.current58a_pending_world_20261017.json`正确绑定当前Native/模板，但world_gate={}、fixed_release_commit=""，EXPORT明确BLOCKED；不是可直接运行的成功配置。

出包顺序：真实World/正常退出PASS→Source六阶段PASS→差异审阅/临时诊断收敛→固定源码SHA和匹配Native169/5seal→正式两遍导出、封印、原签名→核验包名/版本/签名/内容SHA→兼容覆盖安装与设备验证。

正式工具：`tools/build_android_isolated.ps1`、`tools/android_seal/bridge/android_two_pass_export_hook.ps1`、`inject_sources_resign.ps1`、`tools/build_hardcore_android_templates.py`。正式隔离构建按fixed commit，不用脏HEAD代替。KeepStage保留现场。Android Java子进程TEMP/TMP用`D:/Android/v115_java_tmp`，此前DOS短TEMP触发JDK AF_UNIX Invalid argument；不要改全局环境。

- 包名必须`com.personal.mafaoffline`、品牌HardCore、原签名、原数据目录；version115，选人版本说明用正式生成build_info更新，不能debug另签/卸载/清数据/降低versionCode绕过覆盖。
- 114基线：桌面`HardCore-v114-optimized-debug.apk`，500337593B，SHA `bb2568b940df66576b6b98bb9864634d4faa58f6941245e8270c7063c5571552`。
- 目标115：`C:/Users/Administrator/Desktop/HardCore-v115-upgrade-debug.apk`，当前不存在。
- AVD本机`HONOR_REA_AN00_Clone`，`D:/Android/avd`、API35/google_apis/x86_64、6vCPU/4GB、1200×2664@520/60Hz；目前停止。模拟器不是荣耀REA-AN00实机性能验收。DEVICE TEST仍NOT_RUN。

## 9. 必须保留的合同与BLOCKED

- 首次绑定前死亡尾部及经验/掉落时序，用户尚未批准改产品语义，相关路径保持BLOCKED；其余授权技术工作继续，不要以此停掉所有整合。
- 潜在Source Feature enable/reload/retain_subset ABI MISSING/BLOCKED，需要实际Maincontext/grant；暂无外部基础游戏调用路径。不能造空接口通过静态检查。
- sort=true picking尚BLOCKED，当前默认false保留。
- 多线程目标是保持负载/玩法/攻击及时响应下减少主线程热路径和等待；不能把300ms硬当业务deadline，不得把“有后台线程”当流畅性证明。
- 子代理默认禁止；本轮明确只允许1个Sol6.1 high已收口，Pro续接需遵守用户最新协作要求。
- 正常测试保持本树隔离user data/console/headless、真实原生退出、完整receipt/producer关联。新场景使用既有runner精确登记，不能手绕tracked-path门。

## 10. 防丢备份与索引安全

最近完整核验备份：
`C:/Users/Administrator/Documents/HardCore-progress-backups/v115-codex-solo-20261017-164934/SOURCE_AND_EVIDENCE_DELTA.zip`
390978995B /11090文件，SHA `1fc797139897b340db4659710b97ded3d99570820a32654616e807cb67239df5`；CRC和每文件SHA真，325原档不变。包含Native58a/E差异/Windows和Android构建收据/新目录/主要历史证据；**早于当前SourceMap trace和最后两个失败专项**。新增交接补充在`O/handoff_to_pro_20261017`及本次远端分支保留，不能恢复老ZIP覆盖当前R。

原存档只读ZIP：
`C:/Users/Administrator/Documents/HardCore-progress-backups/v115-pretest-pc-saves-20261015-114316/ORIGINAL_PC_USERDATA_READONLY_COPY.zip`
1062419B，SHA `d32b185ad5752ea240f310c01e61e93d0a0761fc738b26be3f8c6cd6656245ef`。

此前子代理不完整private.git曾使git上溯误写真实index；已经按精确字节恢复3180，原错误和恢复证据在`O/index_incident_20261017/EXACT_RECOVERY_RECEIPT.json`。之后每个私有Git必须先有完整HEAD/config/objects/refs/marker，固定GIT_DIR/WORK_TREE/INDEX/CEILING并核验实际路径；不能在缺失目录裸跑read-tree/init/update-index。交接时索引再次精确SHA通过。

## 11. Pro第一轮最有效的工作清单

1. 在R/E核验本报告、真实索引3180与Native58a；读两个新FAIL及PROTECTION，不重跑已闭合无变更组件。
2. 修Source怪物输入缓存，跑现成23检查RED→GREEN专项。
3. 补同物理Root视口在真实map-arrival中的严格身份移交，建立拒绝foreign/stale/retired条件的直接测试，然后真实World+正常退出。
4. World通过后运行同源旧档仓库六阶段180秒，保留全部完整装备属性和稳定UID。
5. 补delivery所有assets校验，固定最终源/封印/模板后真正打115，核验原签名和兼容覆盖安装，再让用户实机测群怪。

用户已叫停本轮，只做交接/远端同步，不在交接过程中继续修逻辑、不关机。后续由Pro通过RDC从此断点接着做。
