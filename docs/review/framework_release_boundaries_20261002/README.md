# 释放审计覆盖补强

父提交 `de02ced5df4c71b2fe6a41c2b0baab8e73389a57`。只修改4个测试/夹具文件，生产代码与父提交完全相同。
Pro对4f65支持关闭两项原释放缺陷，本增量只覆盖其指出的两条尚未直接触达的测试分支，不声称发现新的生产缺陷。

1. 真正非空近战票据，外层领取后producer明确未关闭：错误内部ID拒绝、正确内部规划第一次成功、第二次拒绝，外层重入拒绝；最后关闭并归还容量。原蓄火/半月/刺杀全部业务断言保留。
2. 明确隔离fixture让实际batch工厂返回null。原Player延迟回调到达该分支，Root返回feature_batch_unavailable；没有进入唯一规划主体或请求canonical seed，无额外MP、目标HP、Root和目标EnemyActor RNG变化；真实Player回调尾部关闭producer，容量和工作归零。不声称覆盖所有随机源，也不要求退还已接受冷却。

同源码3原生PASS，完整检查61项，native exit0，零引擎错误。逐项计数 `{"feature_batch_failure_test.result": 12, "feature_melee_ticket_paths_test.result": 38, "feature_release_identity_test.result": 11}`。
内容 `d1a98f38a0c1e9566ac870ab45ab9ad26a5e7b8f3f45126952be088f90fdeff4`，3526源码文件；引擎SHA `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。
原字节增量与原始日志见NATIVE_DELTA_AND_LOGS.zip，完整源码可由父快照FINAL_NATIVE_SOURCE.zip加这4个增量重建；完整manifest及Git tree逐blob核对。父23场景journal验收属于其原固定指纹，不伪称在本次新增测试字节运行。

完整P6/R3自然移动、战斗、持续恢复继续施工；v97原B MISSING，Android/GPU和设备NOT_RUN，无主树集成/APK。
