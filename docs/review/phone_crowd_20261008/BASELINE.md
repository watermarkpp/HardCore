# v106 手机群怪复现基线

核验时间：2026-10-08，Asia/Shanghai。仅记录该次用户复现，不宣布修复完成。

手机 REA-AN00 / Android15，序列 AADMVB3602042319，包 com.personal.mafaoffline，versionCode106。用户确认此前口称v105为记错。安装APK SHA256：895f9fe37cfb28e13570423dcb341fa4307dcc1a61ee5ec070a437f19e247c4a，与已交付v106一致；构建源码78d0775b4b22f40ad1f54426639d867310dae41a，运行改动提交c8477058a0c2f67f7a9e39f3523f4ea7693bd5cd。宿主当前integration HEAD215f0b2f651a51e6855ee813ddd99221690311a1混合dirty；手机不含此后音频、拾取、特装、HUD和局部包围选择器改动。

用户反馈：所有地图均出现，进入战斗的怪越多越严重；本次只有引到较多怪才明显卡顿。画面持续掉帧，但技能和吃药体感响应仍然低延迟，不像失控停顿。本次未测量输入、技能或药品服务延迟，不能把体感写成量化延迟证明。

## 实际采集与原失败

只有一个设备诊断窗口window_id1，最终window_elapsed_ms64570，2130个真实process回调帧间隔，无重开或重新复现。最初reset成功，宿主collector误按RPC envelope解析扁平diagnostics返回，留下FAIL；修正collector后read续采同一窗口，没有再次reset。FAIL原记录保留，错误是宿主解析，不是应用拒绝。stop receipt确认diagnostics_enabled=false、timing_enabled=false，监测已关闭。没有安装、暂停、输入、存档或游戏状态修改。

实际命令和每次调用时间/退出值：outputs/phone_crowd_20261008/repro_091628/receipt.json（原FAIL）及repro_091656/receipt.json（续采PASS）。完整输入、SHA和相邻增量：outputs/phone_crowd_20261008/ANALYSIS.json。分析脚本不连接设备，避免重复检测。

## 相邻区间结果

| 区间 | 时长ms | process帧间隔个数 | 回调速率/s | 结束时总怪/入战/移动 | 怪物物理CPU ms/墙钟秒 |
|---|---:|---:|---:|---|---:|
| start→sample10 | 11536 | 297 | 25.7 | 46/13/10 | 652.9 |
| sample10→sample20 | 9840 | 493 | 50.1 | 35/2/2 | 325.5 |
| sample20→sample30 | 10063 | 517 | 51.4 | 34/18/19 | 354.8 |
| sample30→stop | 4876 | 55 | 11.3 | 34/27/27 | 803.8 |

怪物数为快照时点，不代表整个前置区间恒定数量。地图总怪随死亡变化，因此不是同总量的受控实验；用户认为数量驱动得到本次现象支持，但不能排除地图总量贡献。

最后4876ms：enemy_physics_usec3919148，movement_strategy1676593，crowd_goal435791，retarget516341，motion_clear457292，move_and_slide417326（精确数值以ANALYSIS.json为准）。对应每墙钟秒CPU：怪物物理803.8ms，追击移动343.8ms，包围选点89.4ms，换目标检查105.9ms，移动可行性93.8ms，原生移动85.6ms。计数：foreground6885，enemy physics9112，movement6553，crowd goal6706，retarget6960，motion6757，bodychecks29895。terrain_path_calls及expansions增量0。该段55个帧间隔中48个超过33.33ms，36个超过50ms，23个超过100ms，最后慢帧连续约140~203ms。

这些timing为嵌套inclusive，不能相加；process_ms和physics_process_ms只是GameRoot局部代码段，不能解释为引擎全局总耗时。GPU时间MISSING。full诊断有观察开销，11.3是诊断开启的回调速率，不能冒充关闭诊断时屏幕呈现FPS。

## 调用链审查与后续边界

正式入口EnemyActor._physics_process_internal→_retarget及_hc_tick_melee→_hc_crowd_position_goal→移动短腿/实时身体与环境检查。continuous pursuit自身没有重新调用crowd/retarget；每物理tick重算选点发生在_hc_tick_melee。物理调用量不能直接当昂贵换目标扫描量，retarget内部已有cadence。

v106还使用peer snapshot/choose_with_snapshot；当前dirty源码已改为局部八方向选择，取消目标范围peer snapshot，但仍每tick调用选点。旧手机数值不能证明新dirty实现也有相同成本，不能重复覆盖之前修改或宣布新实现已解决。

下一步应按已有短腿的真实决策边界检查重复选点和重复几何，不增加随意计时器、不减少入战怪数、碰撞、攻击、AOE或物理时钟频率。保留实时移动和攻击实际碰撞。必要功能验证绑定实际新改动；已验证且依赖不变的音频/拾取/特戒证据复用。最终同等怪数、布局、入战活动与诊断模式下热路径耗时必须下降，并由用户体感验收；不能仅用PC/headless PASS结案。

采集PASS；用户流畅度验收FAIL（仍明显卡顿）；修复后设备验收NOT_RUN。完整架构其他未解决项保持原记录。
