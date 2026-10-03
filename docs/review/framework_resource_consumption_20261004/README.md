# 资源消费、接受资格与取消终态专项

父审查提交：`6aab18ff1588b879e1fad659fba4b71fff6f6c75`。第三树施工 HEAD 仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`；审查提交通过独立 index 固定受测内容，不表示干净 checkout 实跑或主树集成。

本轮最终运行内容指纹：`ad9681fc02a35ae84ed6d432aa979cad632f5f05b0ee3efd356961147ca529eb`，3683 个源码集合文件，31 个增量路径。最终采用两组同内容运行：`resource_consumption_final_direct_corrected_063818_196835` 的43场景，以及 `resource_consumption_final_world_corrected_063525_374644` 的8场景。合计51个唯一场景、50份完整框架回执、1281项检查；131次原生尝试中10次失败原始记录全部保留，不把较早内容的通过结果并入最终通过。

## 行为与反例

- 取消终态：服务在通知任何 waiter 前先移除所有已终结请求，避免取消回调改写另一个已就绪结果；排队应用被直接取消后，仅释放同一 producer 的发布锁。原生反例分别34检查/2 FAIL和14检查/4 FAIL，修复与最终相关回归通过。
- 真实消费：可信 cue ID 关联既有主源 fire_sword/ice_storm 音频，实际 CanvasItem 和既有 AudioRuntimeService 消费接受时持有的 AudioStream；复用既有音效偏好、池和事件映射，不增加声音缓存或重抽随机 variant。刷新不重复起声，结束只停止同一序号的请求。
- 同步通知退休：实际播放通知清除 runtime 后，原返回音频请求不得晚注册并继续播放。21检查/2 FAIL反例保留；修复后实际播放器和句柄都收尾。
- 接受资格：null 或合法但空的资源租约不能接受声明 required cue 的 action，也不能先领取 batch 的唯一票据。24检查/8 FAIL反例保留；修复在领取前验证完整资源，合法原票据随后仍可使用。
- 自然战斗与冷启动：资源开启变体通过正式注册/准备路径，保留真实移动、输入、伤害、周期与截止门槛。最终141项 live、10项 cold通过；30个指定目标各3来源，峰90状态和90实际 cue；126次起声均使用持有的确切 stream，939次周期投递，最大实际消费迟到33333us，XP512一致。测试process回调的墙钟帧间隔 P50/P95/P99/max为6754/14736/18351/34176us，并非CPU执行耗时。该样本不证明 Android/GPU、无限耐久或所有战斗的性能。

自然变体与旧场景原共用角色名，被生产同名守卫拒绝后夹具未及时结束，造成第一轮最终world的两个FAIL。隔离角色索引证实该原因；变体改为明显不同的“资源协同战斗”，建角失败立即终止。旧场景名字、生产守卫、攻击次数与业务断言不变。原失败 producer 的 cold 正确拒绝；失败原始记录不删除。

## 证据与保护

`RUN_INDEX.json`列出原命令、场景、run/invocation、内容、完整回执、原生退出和最终采用状态。`NATIVE_MANIFEST.json`、`NATIVE_EVIDENCE.zip`保存原始记录；`SOURCE_MANIFEST.json`、`SOURCE_DELTA.json`、`TESTED_SOURCE.zip`保存受测字节。`PRIMARY_RESOURCES.json`单列媒体原字节，Git与测试换行差异由`GIT_TESTED_SOURCE_MAP.json`明确区分。

主树与第二树分支、HEAD、dirty清单和index原指纹保持，冻结 MonsterStreaming保持。第三树历史index预期66c505与实际df5a01不一致，历史字节连续性为FAIL、旧原字节备份MISSING，原因未建立；记录在`INDEX_CONTINUITY_BOUNDARY.json`。观察到的index及暂存条目已保留，后续核对绑定实际df5a01和staged entries58f820；没有restore/reset或向真实index暂存。不能将本次保护通过改写为历史index一直未变。

父6aab Pro与小可爱完整报告已实际读取并保存于`audit_parent_6aab18ff/`。其意见不自动验收本轮新增字节。

## 尚未完成

本轮仅关闭上述受测范围。旧失败注入supervisor的归档路径解析、锁覆盖窗口、强制恢复和实际目标一致性仍需修复；在修复之前不再运行旧破坏性注入脚本。GPU/设备声音与可读性、Task4异构组合和死亡子连锁、Task5模板/生成式组合/完整P6R3仍未完成。原v97 B输入MISSING，APK/Android交付NOT_RUN。整套框架与资源任务的完整验收仍NOT_RUN。
