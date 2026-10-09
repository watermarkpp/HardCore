# VALIDATION_GAPS · B01

## 优先必要验证（本批没有运行）

**V-B01-01 · 超时旧任务权属**：注入一个可控晚到的真实预取，使initial bootstrap先FAILED，然后旧resource加载完成；记录`generation`、active transition和`background`构建副作用数。若无法制造长延迟，可以在测试钩子注入超时条件，不修改60秒正式规则。旧任务不许改变新地图。

**V-B01-02 · 怪物五动作图集accepted-token平衡**：同profile的前2动作已接受，第3动作请求失败；或第4动作load FAILED；generation切换。在每路径请求/终态get/状态/内存和同资源后续请求中证明配对，禁止战斗帧阻塞。状态FAIL仍保留原记录。

**V-B01-03 · 地图预取失败与代际切换**：一个必需、一个optional的资源分别FAILED；转图时仍IN_PROGRESS；证明旧请求只被回收不被新map消费，失败分类和世界READY合同保持。

**V-B01-04 · StartupLoading/overlay失败**：真实无效角色选择scene或部分失效overlay Texture，验证失败提示、重试、取消与ResourceLoader请求引用平衡；区分`OK`和`ERR_BUSY`，不能乱get其他owner的token。

**V-B01-05 · 测试退出泄漏归属**：只修复当前`LootRuntimeScript.new()`缺少free的夹具；单项重新运行并附Godot `--verbose`对象名称/ID、脚本路径、资源类型的stdout/stderr。保留当前13/3、旧8/3和直接09的1对象泄漏，不把engine runner汇总`engine_log_errors:0`等同于stderr干净。

## 尚缺真实设备和跨模块证据

- 直接06十次movement callback约13847us/最高2113us只证明这个probe下必要event同步查询仍能完成，不等价一次手机渲染帧。需要process期总physics补步+GPU/CPU采样，不得据此降6/9/12或恢复8候选分页。
- 正式投影失败后站立重试30/30、有效既有target保留、stale拒绝、无optional唤醒现有单项已被主控报告/原receipt证明自己的范围，**未变的合同不必重复重跑**；但新的缓存优化或中途错误修复需要定向回归。
- 源`export_presets.cfg` version/code=82，109 build尚`NOT_RUN`；实际build脚本可能覆盖，故只是包前门禁。最终需APK包名`com.personal.mafaoffline`、签名、版本号、真实存档与地图数据兼容。
- 审查已阅读的`WorldBootstrapCoordinator`失败/取消与Godot底层ResourceLoader令牌关系尚缺具体失败场景原生receipt；不要把生命周期静态缺陷错写成当前DeviceLab资源告警的唯一根因。
- 37个`local_only_not_uploaded_not_covered`路径未上传审阅分支；包括grid退役试验，**不可**给`SOURCE_REVIEWED`或加入运行时。
- 其它17 manifest模块`NOT_RUN`，尤其角色/战斗、地图、掉落、存档、HUD/音频/Android；B01阅读跨接口不等于对这些模块做完审计。

## 分类

`SOURCE_PROVEN`是静态机制或控制流确认；`RUNTIME_UNVERIFIED`代表未实际证实故障重现或影响量。`PASS`仅保留原专项自己的证据范围。本批全部源码改动、Godot构建、APK和设备测试均`NOT_RUN`。
