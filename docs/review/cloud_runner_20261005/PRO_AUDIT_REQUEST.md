# Consultation for the original Pro conversation

Delivery status: NOT_RUN. This is prepared text, not a claim of a sent message or
an independent Pro opinion. Use the original 游戏稳定性设计 conversation:
https://chatgpt.com/g/g-p-6a489c5ed68481919473c4a1128c4a54/c/6abbcea3-5fb4-83ea-8732-0cf95e1c4583

请审查固定候选43167c51f6ee31cc3fe08647397c0c4ff9c997a6，基线
9f2ffc25b62ad27914b1ee5cae9bbba0229fdd99。本轮代码范围仅C0 Linux正式验证
入口；C1新世界/DOT合同另有文档，不能把本次视为C2–C6或APK整体验收。

源码入口：
https://github.com/watermarkpp/HardCore/tree/43167c51f6ee31cc3fe08647397c0c4ff9c997a6

证据入口在接续分支 docs/review/cloud_runner_20261005/README.md，
EVIDENCE_MANIFEST.json、VALIDATION_SUMMARY.json与NATIVE_EVIDENCE.zip。
报告明确绑定上述候选及source
d758bb3a1a3b2fc764a817fc19e587f5859c7f0bfd41a419b0aeba368f3d411e，
证据文档后置提交不会改变受测源码。请实际读取相关源码/receipt/原生反例，
列出读取范围与未读取输入，不把原规划答复当本轮审计。

已复现并修正的最小调用链：Python source driver→结构化JSON请求→唯一PS
suite/timeout/receipt owner→setsid exec实际Godot PID→全部三日志和完整receipt→
runner签发本轮成功producer→同invocation真实cold。11项Python自检通过；
其中含13次原生正反例，另有独立peer engine及3次真实journal live/cold/restart。

旧失败反例是symlink用户目录被误判PASS、原生parent退出0但子进程持有管道
导致47.677秒才完成，以及杀detached shell后新收养sleep导致无结构化终证。
现在physical ancestry在启动前拒绝；group/session加subreaper保留真实所有权；
清理按一个固定期限重扫代际，输出排空有界，失败仍保留receipt/result/log。
真实peer engine未被误杀，失败/repeated producer不保留旧资格。

请明确回答：

1. 新Linux transport是否仍保持Windows原门禁以及source/native/receipt/
   producer/cold原权威？请给具体失效路径，不以PASS文本代替终证。
2. 所有权、代际清理、物理userdata限定及每次attempt证据是否还有本轮材料
   可复现的问题？Windows/GPU/Android未运行不能外推为通过。
3. 下一步C2按原完整accepted base queue封口，加原SummonQueue job当前ordinal
   一次factory claim，guard前置于descriptor/counter/actor副作用，是否符合原
   RFC而不引入第二grant表？如何用原发布内容冻结正常respawn与child配置，
   避免EnemyActor.setup重新读已更换的全局catalog破坏“重新发布后生效”？
4. C3拟以编译认证species+frozen layer确定逻辑槽，incarnation独立持有heap/
   cue/root/loan；同种成功施加从当前simulation时间建立全新damage/period/
   full duration/source credit，先准备required cue再替换。旧已提交周期branch/
   accepted child按旧root排空，old returning stack不能动新incarnation。请指出
   same-root loan转移或同步cue回调的遗漏，并区分真实问题与未来可选扩展。

保留当前natural持续真实FAIL：第二轮35秒24/30，6fail；不能减30目标/HP/
负载、延长35秒、恢复旧DOT相位或反复挑绿。Linux世界存档deadline精确比较
也保留真实FAIL；JSON序列化精度只是尚待验证的假说。

目标仍是完成架构优化、必要同候选验证、实际Pro审查，制作并校验兼容APK
交用户本人检测。旧签名及v97真实versionCode/证书仍缺，不以新debugkey或
preset82冒称覆盖兼容，不无限扩展所有未来机制作为本次交付前置。
