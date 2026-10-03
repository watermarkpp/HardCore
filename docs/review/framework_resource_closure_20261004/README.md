# 第三树：真实资源准备与发布增量

本轮父审查提交为 `e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9`。真实施工树仍保留原 HEAD `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` 及用户 index；审查提交采用另一个临时 index 固定内容。本轮不是完整 RFC、主树集成或 APK 完成证明。

受测内容指纹：`52beda6709b0a16e9f62877f4d610042aea85751909d903602939b0611e6abfb`，3653 个源码、场景与数据文件。相对父提交只有 38 个源码、测试或作者数据增量。标准源码指纹不含 PNG；引用的既有主源疗伤药纹理另存于 `PRIMARY_RESOURCES.json`，并进入原字节源码 ZIP。没有新增或修改图像像素。

## 修改与反例

1. 正常 I/O 的失败建角遗漏旧角色未到期药效来源。实际主源药效反例 23 检查、3 FAIL；快照和恢复补药效表、revision 后 23 PASS。合法 `kind=skill` 的数值或数组 ID 原实现已拒绝，41 检查通过；只补覆盖，没有为该候选修改生产绑定逻辑。e9c3 两份审计完整正文、来源身份及读取时间保存在 `audit_e9c3`。
2. 增加精确主源资源声明、真实异步准备、typed 就绪租约和原子发布。无准备凭据仍拒绝；原同步空资源路径保留。入口缺失 2/1 FAIL，非空准备缺口 5/2 FAIL；最终就绪专项 14 PASS，发布专项 5 PASS。
3. 资源强持有沿 loadout → ActionConfigLease → DamageBatch → 已消费队列 entry → until-expired state 交接，不进入 plain graph、存档或伤害事实。源正式死亡、未来来源停用后，旧票据的四次周期结算继续兑现。精确反例 26/3 FAIL → 26 PASS。批次消费移交 typed entry，单独保留只读纯事实；封闭生产者及时放下自己的资源持有。
4. 就绪验证、人物候选与应用原先未进入共享预算，14/1 FAIL → 14 PASS。现在应用作为既有共享 FrameBudget 的普通工作执行，1200us 总额度不变；同步通知包含在 scope 内，完成信号与 await 续体在 scope 关闭后发生。
5. 与外部真实 ResourceLoader 请求共享任务时，旧准备器会领走外部调用者的 get 权。固定 8/2 FAIL → 8 PASS。缓存 miss 始终先领取自己的一次 request 权，利用引擎共用任务，再只领取自己的 get；外部请求仍能独立取得同一个资源。没有第二永久纹理缓存。
6. 活动世界非空模块增加异步启用。仅 READY 边界开始，准备期间旧配置保留，最终重新核验原边界和同一世界／玩家代次。身份来自已有 WorldContext、Root 动作身份和 PlayerState 世界登记，没有第二世界或生命计数器。入口 2/1 FAIL；首版边界 27/5 FAIL；最终 29 PASS，含重新 READY 的旧生命拒绝、世界退出拒绝和输入中途锁定。移除模块同步保留同目录、原启用集合内的资源子集；子集不能授权新模块。
7. 32 个共享请求原先同帧集中完成，12/1 FAIL。现在每个量子只交付一个参与者，物理请求/get 各一次；最终 25 PASS，包含四轮各 32 请求后所有租约、队列与 recurring work 收尾。四轮观测 objects 均 1679、resources 均 131；这只是有限轮次计数，不是总 bytes 或无限耐久证明。
8. 真实引擎请求开始后的取消 13 PASS：实际观察状态为 IN_PROGRESS；取消让原发布者立即失败，仍保留已开始工作的所有权，之后领取并释放自己的 terminal 结果。不是在启动前取消，也没有声称取消了引擎线程。

## 最终同源码验证

只采用 `feature_resource_closure_final_direct_041715_710740` 与 `feature_resource_closure_final_world_042341_438630` 两次调用，受测前后文件表均与最终指纹一致。

- 30 个直接／相关场景 PASS，其中 29 份完整框架回执、609 检查；另一个是普通新角色启动包场景。
- 六个组合效果、合法退出、自然战斗 live/cold 场景 PASS，243 检查；每组 cold 关联本轮成功 producer 和同源码。
- 共 36 唯一场景、35 份完整框架回执、852 检查；原生均确认退出 0，无 timeout，零引擎日志错误。
- 归档 114 次原生尝试，14 次原始 FAIL 保留。早期阶段通过不计入当前最终集合；有效退出与实际退出观测字段分开记录。
- 既有 ObjectDB 退出告警保留；本轮不宣称零泄漏或完整系统内存收口。

实际 wrapper 命令、场景、run/invocation、完整回执、原生退出观测及失败原因见 `RUN_INDEX.json` 和 `native/`。Godot console 文件 hash 为 d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c；child exe 的 hash 只作文件声明，不补称逐调用已加载二进制证明。

## 尚未关闭

Task3 整体仍 `NOT_RUN`：本轮声明类型仅 Texture2D、首条既有主源图标；引擎真正 terminal FAILED 的权利清理负例、更完整的表现／声音／子效果依赖、非空资源开启下的自然混合负载及 GPU 首次绘制和设备指标继续施工。现有自然链回归保留原场景载荷，不能外推为以上新组合全部通过。

Task4 异构机制和来源、Task5 模板／生成组合／整体性能与交付继续开放。原 v97 B 输入仍 MISSING；有限强杀点不等于掉电全矩阵。没有合主树、改版本、打包或 Android 验收。

`PROTECTION.json` 已复核主树、第二树原 dirty 清单和冻结 MonsterStreaming 指纹，真实第三树 index hash 未变。ZIP 每个成员均按原始 size/hash 校验；完整集合与包 hash 见 `SCOPED_EVIDENCE.json`。645 个归档文件按原始字节入审查 index，保留原始换行和报告／日志；源码 Git 文本与受测原字节的 8 个纯换行差异另列 `SOURCE_GIT_BINDINGS.json`，受测原字节以源码 ZIP 和 SOURCE_MANIFEST 为准，不声称干净 checkout 实跑。审查固定 SHA 以本轮实际 push 后交付消息为准。
