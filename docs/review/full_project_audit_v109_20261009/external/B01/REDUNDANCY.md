# REDUNDANCY · B01 只读候选，**不删除**

没有发现能安全删除且可证不影响运行时的正式代码。候选与判据：

1. `scripts/monster_source_frames.gd`与`monster_visual_streaming_coordinator.gd`都加载怪物图像，但前者是**特殊攻击overlay**，后者是**五动作本体atlas**，资源所有权/时间窗口不同。**非重复**；绝不合并缓存或强删。
2. `WorldBootstrapCoordinator`正式地图阶段预取、`FeatureResourcePreparation`功能模块资源lease、`StartupLoading`场景/代码预热各有独立的请求权和失败边界，不能因为都调用ResourceLoader就判无用；本批发现的是**请求结算不对称**，不是冗余。
3. `FrameBudget`的process epoch/necessary与`PausedReceiptPump`的pause收据回收各有正式消费者。必要收据可超过optional预算是已有合同，不能当做多余分支删除。
4. `MonsterVisualStreamingCoordinator.request_client_profile`和`_poll_admitted`分别临时`MonsterVisual.new()`后`free()`读取映射/外壳方法；可以静态评估未来纯静态方法是否更简单，但无速度证据、无生产删改授权。候选风险：改动既有Client映射、注册和视觉初始化副作用；判定`UNPROVEN`。
5. 人物同process多次`movement_performed`触发空间查询：经过source检查确实可能重复工作，但由于坐标和空间索引会变化，不能按frame简单去重以丢失刚进入6/9/12的怪物。仅留后续有约束的证据调查，不作为本轮删减项。
6. `RuntimeServices`和`DomainRuntime`均为autoload，但分别是存档/内容状态facade和地图/技能分域桥；查得到真实公开消费者才能裁剪。仅静态模块名相似不得删除。

其他17模块、本地37个未上传路径与退役grid实验均未纳入冗余删除判断。
