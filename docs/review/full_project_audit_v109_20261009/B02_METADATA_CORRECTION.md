# B02-010 空间规格描述修正

状态：PASS（静态描述一致性）；本次没有改变技能几何、伤害、时序、source authoring 或生成资料。

`skill_spatial_projection_contract.gd` 的规格标签及 `spatial_projection_relationship_matrix.md` 仍记载旧火墙 2×2、刺杀 2.5 GU 和半月 1.5 GU。当前 `skills_source_of_truth_v1.json` 的火墙正式定义为 3×3；当前 `WarriorMeleeGeometry.BASE_REACH_GU` 明确标注用户授权的普通攻击/半月 2 GU、刺杀 3 GU，半月方向集合为 `[7, 0, 1]`。因此只将对应描述改成已运行的规格；刺杀前段仍为 1.5 GU，后段至 3 GU，宽度仍为 1 GU。

旧内容保留在审计基线 `4e77c619249450b7c33e833c2bb3531f3f120bfc` 及原始 `external/B02_followup/` 报告。原始报告不回写成新结果。B02_GEOMETRY_METADATA_FINAL_DISPOSITION.md 是修改前分诊，包含其修改前指纹；本文件记录后续处置。

`SkillSpatialProjectionContract` 的描述字段作为规格/诊断数据，不作为运行时几何尺寸输入。直接查阅 `SkillGeometryService`、`WizardSkillRuntime`、`WarriorMeleeGeometry` 和 `WarriorCombatMath`，以及精确旧标签的消费者检索，未发现根据这些标签计算伤害范围的路径。此次静态校验绑定修改后文件指纹，未重跑既有伤害与帧率测试；没有新的原生、性能、Android 或设备结论。

B02-009 的 `(0,0)` 协议歧义仍缺正式地图可达性证明，保持 BLOCKED，不擅自改变默认目标语义。
