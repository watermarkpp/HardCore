# 子动作正式规划入口与伤害入口分类增量

父固定提交：`5b8288f773d0659b2d1e45538f93fc9a2556dfba`。施工仍在第三树；原工作树 HEAD 和真实 index 不切换。本轮内容指纹 `bad34a5317297c53c3f827dd208efdc482f2b35a868c4efa2fee0e3a0ca2e673`。

## 实现范围

- 登记 `hc.child.death_burst.v1` 的可信描述和独立版本，不将其伪装成原33个玩家技能之一。ChildActionLease 冻结纯命令、根/父/子身份、历史 credit、提交位置和有限代次；它不负责 gameplay 接受或容量。
- 子输入经过原 SkillRuntimeRouter.build_canonical_plan 和原 snapshot builder，生成绝对映射的 STRICT_V2 circle。已有唯一 planner、资源/冷却合同和原技能表保持；计划 hash 包含子命令和来源，不另建 planner。
- 小可爱对父提交发现的 P2：正确 periodic/child batch 被错误投递到 Enemy.take_damage，匹配的调用方 label 能掩盖直接 STRUCK 入口。原生68检查中8项失败；在原入口、HP前拒绝非 direct chain，最终68通过。同一合法 batch 在错误入口及错误投影拒绝后，仍可经 Combat 正确端口提交一次，不丢资格、不改变错误回调的HP/RNG/攻击计时。
- Pro 父报告的 Combat 投影恢复补证已纳入同一68项测试，保持周期公开签名及立即死亡碰撞消失。

## 原生反例与最终证据

`RUN_INDEX.json` 保存56次原生尝试：50 PASS、6 FAIL，未删除失败。最终同源码直接26场景及世界8场景均原生退出0，无超时；34唯一场景中29份框架回执937项检查，其余5个普通场景依 runner/原生退出验证。两组隔离 APPDATA、native PID、run/invocation/source、producer/cold 身份见 `FINAL_RUN_ASSOCIATION.json`。场景和实际命令见 `FINAL_TEST_GROUPS.json`、`RUN_INDEX.json`。

保留的6个失败：

1. `child_planner_red_122807_529063`：fixture 将实例方法作为静态方法调用，解析失败，无有效框架回执；不充作有效功能 RED。
2. `child_planner_entry_red_122915_169984`：1检查/1 FAIL，旧正式 router 缺少注册子输入工厂。
3. `child_planner_green_123208_702616`、`child_planner_diagnostic_123342_686363`：各5检查/1 FAIL，STRICT_V2 校验上下文缺位置 converter，已最小修复；诊断不修改生产几何。
4. `child_planner_related_123641_364370`：9场景中的 canonical_snapshot_identity_production 在等待 READY 阶段失败。两规划文件精确旧字节对照及新实现重试均通过，归因未证实，保留原 FAIL，不称已证明既有基线或新增回归。对照不是完整父 checkout；恢复关联见 `BASELINE_PLANNER_ASSOCIATION.json`。
5. `child_planner_entry_class_red_124108_522428`：68检查/8 FAIL，错误入口改变HP并生成事实，其余是连带检查；不称8个独立生产缺陷。

子输入44检查覆盖实际 child ID、唯一 envelope/snapshot、确定性独立 seed、禁止篡改/缺 owner、非法代次/映射/parent fact/world、原33技能不变。它是纯规划测试，未证明 Root 已执行 child、已接受整链容量或整链退休。

## 字节与保护

`SOURCE_MANIFEST.json` 3728文件，`SOURCE_DELTA.json` 8增量；`GIT_TESTED_SOURCE_MAP.json` 对受测原字节与提交字节逐文件区分 exact/CRLF-only。`TESTED_SOURCE.zip`、`NATIVE_EVIDENCE.zip` 和逐成员清单可远端重算。引擎版本/两exe hash见 `SCOPED_EVIDENCE.json`。

`PROTECTION.json` 核验主树、第二树 HEAD/index/dirty 清单及第三树观察到的真实 index 保持。历史第三树 index 连续性仍 FAIL，历史原始备份 MISSING；现有观测备份单独保留，不能冒充历史原件。冻结 MonsterStreaming、原媒体及 RFC 原文未变。源文件 diff-check PASS；原日志/审计正文的空白失败依 `DIFF_CHECK_BOUNDARY.json` 保留。

父两份完整报告及来源身份在 `audit_parent_5b8288f7`。Pro 未逐文件重算父3724或解压 ZIP；小可爱报告独立重算其声明的父证据，但未本地运行 Godot。二者不等于本轮已审。

## 未关闭范围

Root 实际子动作执行、整链动态/逐目标容量、状态与全部生产者退休、防自激、生成式组合、Task3实际表现/子资源消费、Task5模板及完整自然 P6/R3、设备/GPU、原 v97 B 输入、APK均未完成。死亡处理、奖励和存档仍采用原权威；本轮不启用正式死亡连锁玩法，不合并主树，不构建已知未闭合架构的APK。
