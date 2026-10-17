# 当前群怪多核架构研究

日期：2026-10-13（Asia/Shanghai）。本文件记录本轮范围，不覆盖旧报告。

## 115 施工授权与当前阶段

用户最新授权：持续完成本次多核大改并交付115 APK，优先继续原包名/签名/存档；兼容冲突过多时可另起并装测试系列。此前“先设计、暂不施工”现已更新为：先完成设计封口，再按门施工和执行必要验证，不能以未闭合框架凑新包。

物理补充报告已完整从DOM回读并下载，原文 `PRO_PHYSICS_CLOSURE_FINAL.md`（34632 bytes，SHA256 34fd442d05e09b15c782d70803dba8f05ce37a3a5d3ed5be9360cedc10418dfd）。选择B：唯一同源Godot后端移交S驱动，Main停止游戏物理step，non-Node同源运动控制器，原query/callback/transform相位，自编模板。第四轮clock报告已完整回读并下载：`PRO_CLOCK_CLOSURE_FINAL.md`（21719 bytes，SHA256 1a7a1f32912cc7c9018c03e3a8eeb6a5d6110340c97db6b1d7c19d6a6d1f3bc4）。H/P/U相位、timer扫描、暂停receipt与正ObjectID身份方案已定，原始报告保持原文。

施工隔离树由原生工具建立并附着：`C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore`，detached HEAD45170d0。官方引擎基线 `C:/Users/Administrator/Documents/HardCore-engine-v115/godot`，4.7-stable commit5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88，项目只维护自有patch/module/build scripts，不提交vendor引擎。已委派物理owner适配、构建依赖/封装准备、纯数据batch/presentation与源码时钟映射。尚未编译、尚未切生产writer、尚无115 APK。

原生worktree默认为detached，旧bootstrap在branch为空时`.Trim()`失败，报告保留FAIL，不修改门禁规避；等价保护核对HEAD、关键生产字节、dirty、index、worktree与root规则继续记录。3项关键生产SHA与主树一致。当前出现的loot compiler JSON dirty为checkout已有内容，保留。

## 当前任务

用户要求把多核架构作为继续开发前必须解决的事项，优先与官方 Pro 讨论支持安卓的 Survival／幸存者类密集群怪游戏。排除暗黑1作为主参照，回合制不算，塔防仅作为辅助。研究阶段暂停的施工现已获最新115交付授权；继续保留设计前置和必要验证，不运行无关重复微实验。没有授权降低怪物数量、移动速度、战斗节拍或改变碰撞与立即攻击规则。

主树 `codex/integration` HEAD `45170d0eaf4d2c642d4a03de392f64fa2b1e25bf`；114固定发布源码 `10daa4d20e3be0dac1161f45b6be94e44a0bfc50`。113冻结树保持只读。运行包名继续为 `com.personal.mafaoffline`。

用户进一步明确：画面线程按统一调度安排读取结果并呈现，主要计算由其他线程分块承担。300ms只是原来为了减少计算量设置的参数，不是工程架构约束或可行性依据；本轮不再围绕它反复论证。

用户最后给出的设计参考：从每帧需要什么数据及何时需要出发，后台任务在规定时间内产出；单个工作线程来不及时，继续拆分其可独立部分。设计应据此列输入/输出、依赖、发布、截止和生效约定，不保证靠无限细分即可消除所有顺序依赖。

## 已有手机事实

荣耀REA-AN00，114，黑暗地带地图913203，不需要火墙即可复现。地图总58怪，33–34 engaged时相邻快照差值约8.8–10.7次process更新/秒；46 engaged时约5.8–6.3。此指标不是GPU呈现帧率。

Perfetto环形缓冲最终有效窗口约29.88秒，GLThread 66（pid966/tid1203）实际Running约29.500秒，约98.7%；全部核心sched忙碌占比约33.9%。窗口不能外推到完整90秒。该线程包括脚本、物理和画面准备/driver，不能直接称为纯AI。FrameOnly关闭的微计时零值不能排除对应工作；GPU时间MISSING。

原始证据：`outputs/phone_crowd_v114_20261013/capture_214613/`。

## Pro 实际派发

线程：https://chatgpt.com/c/6acddd90-6e4c-83e9-86f0-a3932a895d6c 。模型菜单实际显示Pro。第一轮及Survival补充已实际发送，正式报告已完整回读（页面显示思考14m10s）；最初AX读值仅返回到4.4，后续完整正文已另存，不能以最初partial当最终报告。第二轮已实际发送统一时钟、模拟权威、工作线程期限/过载及成熟模式复用质询，正式六部分设计已完整回读并下载。派发与回读PASS不等于生产架构验收。

派发记录：`outputs/multicore_v114_20261013/pro_reference/ROUND1_REQUEST.md`、`ROUND1_DISPATCH.json`、`ROUND1_RUNNING.png`。

首轮完整回读：`ROUND1_RESPONSE_COMPLETE_AX.txt`；第二轮请求和派发：`ROUND2_REQUEST.md`、`ROUND2_DISPATCH.json`、`ROUND2_DISPATCH_AX.txt`（均在上述目录）。第二轮实际消息还包含优先借鉴成熟方案的追加要求。

首轮Pro裁决：整段群怪运动数值化/原生批处理、原顺序提交与依赖局部修复为主路线，配套批量表现准备；独立模拟所有者+只读表现快照为更大迁移路线。不能把整Enemy回调同时扔进4/8worker；不能把已有小静态kernel重复实验当推进方向。此裁决是设计建议，不是已实现或设备性能PASS。

第二轮收束：推荐画面主线程＋独立常驻唯一权威模拟线程＋批量工作池。原序提交应保留，但没有理由继续放在画面线程。主控复核后的决策与施工边界见`ARCHITECTURE_DECISION.md`；Pro原始Markdown见`PRO_ROUND2_DESIGN.md`（27849 bytes，SHA256 d9c07d84a3e3f286572563895421cb575792a812d4bf543003bc17c65abb6076）。本轮未修改游戏生产逻辑、未执行新增native/手机实验。

## 主控核验到的主要参照

《Deep Rock Galactic: Survivor》有正式安卓版本。Unity于2026-09-18发布移植团队访谈，明确记录1000敌人追向玩家、500敌人加武器持续战斗的负载；敌人移动采用10–15层依赖的Burst Job链，并在常规物理系统外执行。这个数字是任务依赖层数，不是线程数量。团队同时调整了导航、空间查询与呈现，不能把成功归因于单独开启线程。官方资料没有披露全部线程数量、逻辑频率或完整源码，这些保持未知。

- 主要开发访谈：https://web-prd.hexagon.unity.com/blog/optimizing-deep-rock-galactic-survivor-for-mobile
- 同一访谈入口：https://unity.com/blog/optimizing-deep-rock-galactic-survivor-for-mobile
- 安卓发布：https://play.google.com/store/apps/details?id=com.ghostshippublishing.deeprockgalacticsurvivor

## 本轮改动与验证边界

用户叫停额外实验之前，已完成可选loopback RemoteDebugger接入（runner、crowd wrapper、test sample markers）及参数化离线解析。仅测试工具和fixture变更，游戏生产逻辑没有改动。静态contract PASS；本轮native NOT_RUN，设备 NOT_RUN，生产worker NOT_RUN。不以这些工具改动冒称多核改造完成。

接入证据：`outputs/multicore_v114_20261013/profile_hook/PROFILE_HOOK_EVIDENCE.json`。

## 下一轮需要问清的架构边界

1. 参照游戏是否改变了计算组织、数据表示、数学算法或游戏语义？哪些是官方已证，哪些仍未知？不能把Burst等同于多线程，更不能把依赖链长度等同于CPU核心数。
2. 同一tick快照并行计划如何保留我们目前前一个actor移动后、下一个actor读取实时位置的顺序？需要哪些实际读集合与冲突规则？仅检查bucket membership revision不能证明同bucket内位置不变。
3. 独立模拟线程可以让显示更独立，但怎样保证模拟本身不积压、输入/攻击不延迟？它独自仍可能满载，不能称为已经充分多核。
4. 若完整live验证等于重算热路径，必须扩大唯一数据所有者与批量计算边界，而不是另建第二份HP/移动权威。指出具体迁移接口和无需用户改变玩法的步骤。
5. 4/8线程的计划必须列依赖关键路径、数据准备与提交成本、迟到处理和队列上界。手机大小核不等速，不保证CPU总利用率或固定60fps。
