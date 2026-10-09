# B02_followup · 冗余与兼容性核查

**只读源：** `ed2d87121de80c84caaa3f096c3a5acb71d4946f`。所有候选不经用户/主控独立授权不得删除。此前B02旧`REDUNDANCY.md`保留原样。

## 可由当前源码确认的真正不可达分支

**RD-B02-01 — `scripts/caster_skill_animation_player.gd::configure()`，约251–293行。**

连续两个`elif`的条件完全相同：

```gdscript
elif _desired_axis_extent > 0.0 and not _fit_axis_world.is_zero_approx():
    # 每帧可见轴与宽度校准
    ...
elif _desired_axis_extent > 0.0 and not _fit_axis_world.is_zero_approx():
    # 用源序列bounds计算后备缩放
    ...
```

第一分支满足条件时必被执行，因此第二分支恒不可达；该处可被认为确证冗余，而非另一个备用战斗算法。`_axis_cross_fit_active`可仍在第一分支处理实际变换。**只登记，不在B02报告提交中编辑代码。** 若主控决定删除，需核对动画视觉的source-axis/native-fallback接线，而非只做静态lint。

## 不得误删的正式/兼容/测试边界

- **`SkillRuntimeRouter._plan()`与`build_canonical_plan()`：不是两个竞争planner。** 后者调用前者产生纯技能领域effect，再由PlanContract冻结schemaV2。删除前者会破坏正式链。
- **`SkillExecutionPlan.gd`：** 只作旧接口到唯一`SkillExecutionPlanContract`的转发和最终result构造，正式GameRoot仍调用它；不是第二planner。
- **`CasterSkillBehavior.gd`、`LegacySkillAdapter.gd`：** 历史技能显示/兼容读入适配与测试存在；无直接生产HP写入，不以缺少GameRoot直接调用就判可删；仍需跨批验证动态反射。
- **`SkillSpatialProjectionContract.gd`：** 33技能机器可读历史关系矩阵；虽然存在B02-010过期尺寸描述，但这是资料漂移，不是“完全无用即可删除”。
- **`PlayerGroundRuntimeDiagnosticOverlay.gd`：** `enabled_for_runtime`固定false，只供有条件诊断；不是常驻第二移动/投影权威，属于仪表保留候选。
- **`AoeEngagementWindow.gd`：** Debug一段式非因果观察，明确只记录FireWall施法后的首次ANY death，不能删除用于排障的证据口，也不能推断伤害来源。
- **`GroundSkillVisualCell`和`CasterSkillAnimationBatch`：** 一份Controller时钟服务9个视觉格；没有按怪物逐个分配HP处理，不属于重复火墙伤害。
- **`CasterSkillVisualRegistry`和`AnimationPlayer`：** 前者唯一纹理缓存/序列lease，后者每节点播放cursor；拆除任何一方不能仅凭名字重叠而声称优化性能。

**未提供同工作量CPU或Android帧时间证据，本批不批准任何因“看起来重复”而删除的优化。**
