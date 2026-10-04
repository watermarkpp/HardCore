# 有限链身份与真实 HP 提交边界

父固定版本 e22fe0951f28c55620399b453f116cb09120af4b。本增量为原 RFC Task4 的接入基础，不是完整死亡子连锁、Task4、P6/R3、整个框架或 APK 完成证明。

## 改动与权威边界

- DamageBatch 捕获有限 root/parent/release/generation 身份，拥有不可变原始 credit；已有空链 direct 语义保留。此基础端口使用 root-scoped skill，不宣称独立 child descriptor 已接入 planner。
- Enemy 原 HP 写入之前，经当前地图正式投影取得提交位置；HP 写入之后、死亡/受击观察者之前冻结 actual_loss、生命身份和位置。后续通知立即移动/治疗，不能修改既有事实。仍是唯一 HP 权威。
- CombatRuntime 新增受控 periodic-chain/child 端口，共用原 MAC、周期免疫和零值语义。无效类别/投影在 RNG/HP 前拒绝，不消费、不污染合法批次。
- 原 Enemy.take_feature_periodic_damage 四参数及 CombatRuntime.apply_feature_periodic_damage 五参数完全保留，链端口另行命名。周期/子伤害死亡仍由原 _mark_death_pending 立即撤销碰撞。
- 纯 DeathBurst handler 增加根事实 skill_id 核对；缺失/错误根身份拒绝，后代不同技能 ID 允许。handler 仍不在正式可发布目录，Root/runtime 尚不执行它。

## 反例和修复

原始记录在 native/ 与 RUN_INDEX.json；四个失败均保留为 FAIL，详细分类见 FAILURE_CLASSIFICATION.json。

| 范围 | 原实现/中间失败 | 最终验证 |
|---|---|---|
| 链身份与提交几何 | child_commit_red：1/1 FAIL | feature_chain_commit：56检查 PASS |
| 错误回调抢占合法资格 | callback_red：37检查/14 FAIL | 错误类别先拒绝，随后合法提交恰好一次 |
| 旧周期公共接口 | boundaries：原生解析失败，无合法本轮回执 | 恢复原签名，原边界及周期生产回归 PASS |
| 纯 handler 根技能身份 | child_root_identity_red：31检查/2 FAIL | 31检查 PASS，后代不同身份正例 PASS |

上述真实 HP 端口测试是受控生产 API 测试。它没有走 Root 子技能 planner、自然用户输入、完整接受前容量预留或完整子链退休；不能以此报告整条生产链已完成。

## 最终同内容证据

SCOPED_EVIDENCE.json、SOURCE_MANIFEST.json、GIT_TESTED_SOURCE_MAP.json 和 RUN_INDEX.json 共同绑定最终内容。最终 28 唯一场景、28 完整 framework receipt、885 检查 PASS；DIRECT20/30秒及 WORLD8/60秒，原生退出0、无超时、各组运行源码不变。57 原生尝试中 53 PASS、4 FAIL 全部保留。中间版本不能并入最终通过。

FINAL_RUN_ASSOCIATION.json 与两个 launch.json 记录两组不同的测试拥有 APPDATA、实际 native 用户目录、项目、PID、run/invocation。WORLD含既有组合/安全退出/自然效果/资源 live-cold；这些冷启动验证原业务，不是新死亡子链的冷启动证明。

引擎 4.7.stable.official.5b4e0cb0f，console/child 二进制哈希见 SCOPED_EVIDENCE.json。原生 ObjectDB 警告按原日志保留，不声称零泄漏或无限耐久。源码与原生 ZIP 已逐成员复核大小/哈希；所有受测源映射 Git 原字节或 CRLF-only，不用同 HEAD 冒充同字节。

## 保护与未完成项

主树 v97 与第二树 HEAD/index/dirty 指纹保持；真实第三树 HEAD/index 保持，审查提交仅使用本轮专属 shadow index。历史 index 连续性 FAIL、原历史字节 MISSING 继续保留；当前已观察备份不回填历史。父 e22 两份完整独立报告正文、消息身份及实际读取时间见 audit_parent_e22fe095/。

仍未完成：Root唯一planner的可信子描述与释放、完整动态/per-target接受前承诺、周期及异步生产者退休、防自激与生成组合、Task3实际cue/子资源消费与渲染、Task5模板和完整自然P6/R3。原v97 B MISSING、破坏式故障监督器安全、设备/Android/GPU、APK分别开放。保持原怪物规模、周期、伤害、几何、HP/planner/writer及真实存档保护；不启用半成品玩法。
