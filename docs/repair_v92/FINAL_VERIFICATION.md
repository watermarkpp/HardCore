# v92 最终验证与交付记录

2026-09-22。本记录区分完整回归、失败修复、最后改动的影响回归、性能采样及 APK 实物验证。设备由用户手工验收；DEVICE TEST: NOT_RUN。构建身份与远端身份在打包完成后补齐。

19:50追加的独立渲染12次对照见 [RENDER_CONTROL_TEST.md](RENDER_CONTROL_TEST.md)。蜈蚣洞环境精灵约减少60%，赤月图集纹理减少；headless CPU p95未统一改善。性能调查继续，不能把下文历史动作完成当作群怪性能目标完成。

20:39追加密度独立调查见 [MONSTER_DENSITY_INVESTIGATION.md](MONSTER_DENSITY_INVESTIGATION.md)。13次有效测试PASS，区分固定12参战时的近/远闲置与隔墙追击，以及三张正式地图和v91对应源码的真实普查。正式地图静止采样未复现寻路积压，AI休眠与视觉驻留有不同边界；手机与整体性能仍未通过验收。此前原生退出崩溃没有因本组成功而关闭。

21:16追加闲置怪CPU修复见 [IDLE_MONSTER_CPU_REPAIR.md](IDLE_MONSTER_CPU_REPAIR.md)：范围优先过滤后，再按用户要求降低真正停驻待机的唤醒频率；11项影响回归、6次固定工作量/正式火墙采样PASS。此次生产源码SHA与前阶段不同，各自证据分开归档。后台调用削减不能当作整帧同比提升，正式移动与手机归因继续。

## 完整回归与失败闭环

`tools/run_godot_tests.ps1 -Suite critical -TimeoutSeconds 30` 原始结果为 **459 PASS / 4 FAIL，共463项**，5条实际错误。原始 JSON 为 `evidence/runners/runner_results_critical_20260922_191536_629_3972.json`，完整控制台为 `evidence/critical_20260922_191536_console.log`。不把后续分批通过改写成原始463/463。

运行开始记录15435个源码/资源/工具/测试哈希。结束时仅非本套消费者的 Python 分类预期发生变化；Godot生产文件和所选场景保持一致。证据为 `critical_source_snapshot.json.gz` 与 `critical_source_drift_check.json`。

| 原始失败 | 分类、证据与改动 |
| --- | --- |
| bich_undead_client_art_test | fixture 生命周期污染。真实0.35秒观察从 `physics=false/sleeping=true/idle` 变成 `physics=true/sleeping=false/attack`：后台唤醒子计时器不受仅关闭物理更新的影响。资源/手动动画测试改为角色子树PROCESS_MODE_DISABLED；所有11怪五动作/八方向/尺寸锚点断言保留，生产AI未改。 |
| monster_special_delivery_runtime_test | fixture 随机输入未固定。实际玩家有基础魔法闪避，旧断言把合法闪避视为未命中结算；失败后遗留玩家又污染下一项触龙神冻结集合。测试仅固定随机输入，仍调用真实PlayerCharacter完整闪避/MAC/HP链；新增roll0闪避和roll9命中双边界，触龙神冻结目标/独占边界保留。 |
| game_root_r3x6_targeting_broadphase_test | 旧预期。地狱火不消费generic targets。将原顺序证明转至真正消费者抗拒火环，另断言地狱火目标数组为空且索引查询数不增加；保留召唤占位索引证明。 |
| dpv2_drop_runtime_policy_test | 用户衣服单槽变更后的旧预期。ID76由85槽变84，精确删除一条重复灵魂战衣output126。改数量及日志；实际每槽解析/RNG/overflow/15件守恒断言全部保留。 |

四项加火墙新增专项最终 **5/5 PASS，engine_log_errors=0**：`runner_results_adhoc_20260922_191933_474_22628.json`。原始失败和可复现RED均归档，没有扩错误白名单或删断言。

## 最后火墙生产改动

正式施法已经创建并注册一个FireWallFieldController，但以前公共执行结果返回空数组。现在统一返回新建或刷新复用的真实owner，并归入spawned_ground_effect_ids；九个纯视觉格不单独记作伤害/副作用所有者。一般ground effect工厂也返回实际节点，继续由既有manager管理。没有第二套registry、额外tick或新伤害入口。

专项通过正式施法验证：release/snapshot一致、一个owner、九视觉格、同中心复用、第九场淘汰最旧、旧视觉释放，以及真实910001→910007转图后registry和lease无残留。owner和旧宠成长合同已加入critical；suite registration PASS。最后影响回归在下方记录。

## 保留边界与数据身份

`evidence/frozen_scope_check.json`：人工地图/编辑器文档、美术地图、装备主表、canonical怪物目录与两类分类、UI素材、project.godot、export_presets.cfg共10个范围相对b961cedf无Git差异。地面manifest只按发布provenance精确固定检出换行；其Git blob和JSON语义未改变。初始23个未知UID保留，不提交不清理。

正式authority共6042槽，SHA-256 `9F6E27418C742C9338CE4B60D752202E50549B48BBC2E066D91C760E6EF43B56`。完整回归重新导出的正式地图掉落快照SHA-256仍为 `ABB474E32D2D5F37BBBF1932BE976208EAD7D577B95863A18C325E08E2BA66D5`，与桌面Excel输入完全一致。

桌面Excel `HardCore_当前地图怪物真实掉率_20260922_衣服单槽修正版.xlsx`，680723 bytes，SHA-256 `0B3140886CDF24BC298663CF8F512B33110A0315AED4471F36D8DAD2AC6F5826`。67图/2645刷新点/120怪/121表/10423分数字符串；主列为15件上限、保护、优先级及并列筛选后的精确实际概率。原生Excel交互NOT_RUN，OOXML/类型/文本格式/数学/全表渲染PASS。

## 性能解释与设备边界

正式三图对比见 `PERFORMANCE_AND_SKILL_CLOSURE.md`。同样保留62/71/54怪及8场九格火墙；generic技能候选数组、视觉回调与长帧重复提交已经实测减少。整体headless p95改善较小，部分八次施放样本波动变差如实保留；不是手机FPS验收。该组baseline已经启用修复后的优化墙体渲染，所以它衡量后续context/batch改动，不代表完整v91→v92收益。

原始m30三场景/六火墙最终采样、最后影响回归、自审、构建SHA、APK签名版本与远端推送仍需在本记录追加实际结果。用户苍月岛原现场和罕见Boss刷新存档现场未精确复现，正式路径及反例通过不冒充用户设备复现。没有清档或重装作为修复步骤。

## 最后影响回归与原始基准补测

最后技能影响回归16/16 PASS（runner `20260922_192252_764_5996`），安全区默认值消除逐查询字典分配后3/3 PASS（`20260922_192715_193_16744`），均0运行错误。中间试用null作为get_meta默认值会在缺键时报引擎错误，负例已抓住并归档；最终使用false标量且保留原类型分流，未放宽测试。

原始m30固定30怪、seed20260909、45预热帧、320采样帧，三种布局及六火墙布局均匹配签名。最终采样2/2 PASS只证明运行和行为证据产生，不等于性能目标PASS。

| 场景 | 原始p95 ms | 最终p95 ms | 差异 | 每次enemy physics微秒：原始→最终 |
| --- | ---: | ---: | ---: | --- |
| crowd / open_pursuit | 15.983 | 16.357 | +2.34% | 264.88→276.99 |
| crowd / sustained_close_attacks | 18.851 | 19.398 | +2.90% | 295.92→306.80 |
| crowd / dense_crowd | 18.961 | 18.927 | -0.18% | 285.09→298.89 |
| aoe / sustained_close_attacks | 18.867 | 20.249 | +7.32% | 294.80→308.39 |

该原始fixture没有正式safe_zone_context，只提供旧safe_zones元数据；因此不覆盖正式地下城已编译空安全区快速返回的收益。全链测量中还有诊断子类开销和真实墙钟节拍。最终攻击开始/伤害次数分别1/36/29和六火墙36，均与原始一致；移动路径细节与采样末尾physics tick有差别。没有把未取得的整体收益归为噪声后删除。**跨所有采样场景统一改善：FAIL；手机流畅度：NOT_RUN。** 原始、第一次复测和最终复测均保留，详见 `m30_before_null_default_comparison.json`、`m30_final_comparison.json` 与profiles目录。该局限随安装包交付，不能宣称全部性能问题已消失。

## 22:20 打包前最后追加

用户明确要求当前优化后打包，加入必要监测，交由手机验证。闲置/查询最新源码与四次真实时间反例见IDLE_MONSTER_CPU_REPAIR；M30最后8次功能PASS，但两组严格可比性失败保留为BLOCKED，不声明统一60帧。Windows一次原生退出崩溃仍为历史FAIL，证据强烈指向Godot4.7上游退出清理UAF；没有改引擎，也未证明Android同样发生，见NATIVE_EXIT_INVESTIGATION。最后全部相关Godot测试完整退出通过，不忽略返回码。

新增三职业成长审计见CHARACTER_GROWTH_REVIEW：13005字段独立核对、177次真实升级、六保存失败回滚、正式施法主属性及AC/MAC真实扣血、升级前后负重接收边界PASS。

新增Debug设置页两种30秒本地记录，复用DeviceLab唯一采样owner与4096帧有界ring。暂停不计入窗口，结束先停计时再序列化；世界退出会保存未完成记录并关闭计时。报告包含build_info、补丁身份、设备、地图、物理更新/深度休眠/参战怪、火墙、每秒引擎粗采样和已有CPU计数。GPU真实帧时间仍标为不可用，Godot缓存process监测不冒充逐帧耗时；frame_only和full分开。

新记录专项首次因测试调用了不存在的方法产生3条解析错误，修正测试API后PASS；生产未用绕过处理。设置页、菜单触摸/暂停、帧记录与模式4项PASS；最后人物/本地记录/DeviceLab/空安全区/索敌预算/闲置频率6/6 PASS，0引擎错误，runner 20260922_221819_640_1460。所有原始runner含失败已归档evidence/delivery_close。suite registration PASS，ADB当前无设备，DEVICE TEST: NOT_RUN。

## 22:49 v92 安装包交付

APK 构建源码 `abbb5efbaba3b4d3f539f674b52b27ca2dc9f16e` 已推送并核对 origin/codex/integration。桌面包 `HardCore-v92-20260922-abbb5ef-debug.apk`，versionCode92，同 v91 包名与证书，480221108 bytes，SHA256 `3A7E3D8CAF00743CCE27C82072C05792A3FEF72D1E53FCFEB0C287DAF0800A3F`。身份、启动主题、67图地面闭包、60墙体plan真实包内哈希、807贴图导入、48新增墙体贴图、34修改脚本编译变化、6042槽掉落及测试工具排除均 PASS。

固定源码六项复验6/6 PASS、零引擎错误、进程正常退出，runner `20260922_224703_880_19644` 的 git_head 即 abbb5ef；后续只增加交付核验工具与文档。原始全量459/463及其四项后续修复仍按前文记录，不改写历史。

构建第一次 JDK PipeImpl/UnixDomainSockets 回环连接 FAIL，进程级 unixdomain 临时目录参数验证后同一 staging 重导出 PASS。八个初次导入报错仅为既有 BOM 测试夹具，包内排除已验证。首次额外 ZIP 核验误解未标 UTF-8 的目录元数据，明确 UTF-8 解码后全断言 PASS，未改变 APK。证据及哈希见 `evidence/apk_v92/manifest.json`，安装和监测步骤见 `APK_HANDOFF.md`。

保留状态：手机性能/操作/采集 NOT_RUN；所有场景统一性能改善 FAIL；两组 M30 严格可比性 BLOCKED；一次历史 Windows Godot 原生退出故障 FAIL、引擎修复 NOT_RUN。功能修复和包内验证不替代用户实机验收。
