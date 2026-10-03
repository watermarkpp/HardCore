# 第一条异构命令与同步派发退休

本增量以 `87400315b1accc87dc0592b091dbfcef876453d5` 为父审查版本。施工仍在第三树；不合入主树、不改变第二树，不操作真实存档。整套 RFC 架构升级、完整 Task4/Task5、Android/GPU 与 APK 均 `NOT_RUN`。

## 修改范围

- 新增受控 `hc.lifesteal.v1`：只消费直接伤害已经提交的实际 HP 损失，通过原 CombatRuntimeService → Player.restore_health 恢复同世界、同生命的存活来源。致死目标的有效已提交事实仍可恢复来源；周期伤害不重入该直接命中链。原装备吸血公式不变。
- trusted handler registry 声明权限、命令成本、持续状态成本和生命周期。即时恢复预留回执，不占持续状态槽；燃烧保留原周期、伤害和状态容量。验证包默认关闭，正式目录不启用新玩法。
- 同步回血/音频通知可能退休 runtime。派发代次使旧栈在下一 binding 写回执或生成命令前结束；未退休的票据意外丢失仍显式失败。既有唯一 HP、planner、writer 与模拟钟不变。

## 可证伪反例

1. 原 authority/compiler 不认识新恢复权限和 handler：`heterogeneous_lifesteal_red_070316_459227`，2 检查/2 FAIL。
2. 两个即时恢复来源，在首次通知中 clear 同一 runtime，无票据旧事实仍继续第二次恢复：`heterogeneous_lifesteal_reentry_red_071241_973140`，78 检查/1 FAIL；最终同场景 78 PASS。
3. 使用父版本 effect_runtime 原始字节，正式 rule/item/skill 三来源、真实 Root 冰咆哮、非空票据，首次 AudioRuntimeService 通知 clear：`resource_multi_audio_retirement_red_072012_398623`，23 检查/1 FAIL，并真实产生缺失 reservation 的 SCRIPT ERROR。恢复候选字节后原反例通过，最终增加预算 scope 关闭检查为 24 PASS。临时替换与恢复均核对文件哈希，未修改真实 index。

早期不存在 fixture 方法、无正式生命 epoch、错误公开属性以及私改最大 HP 引起的失败均保留原始记录，并在工作日志中分别分类；不能把这些记录改成 PASS。它们不证明自然 UI 故障。

## 最终同源码

内容指纹 `86b48f605b4de129b528dd8bc5649ce85233c2503b2503d573ad7cf304310c91`，3692 个源码/配置文件，相对父版本 15 个增量路径。

- `heterogeneous_final_direct_072506_992668`：46 场景，原生退出 0，无超时，运行期间源码不变。
- `heterogeneous_final_world_serial_073647_883931`：8 场景，原生退出 0，无超时，运行期间源码不变。
- 两组共 54 个唯一采用场景、53 份完整 framework receipt、1409 项检查。每份采用回执匹配实际 invocation、run ID 和 source hash。包括组合 live/cold、安全登出 live/cold、自然生命周期 live/cold、真实资源自然 live/cold。
- 73 次原生场景尝试中保留 8 条失败；另一次 world wrapper 在原生场景启动前被 mutex 拒绝，单列 `WRAPPER_REJECTIONS.json`，不是 8 个原生场景失败，也不计为通过。拒绝后等待直接回归明确终态，再串行重跑。

命令、退出状态、完整原始日志与回执见 `RUN_INDEX.json`、`NATIVE_MANIFEST.json` 和 `native/`。`TESTED_SOURCE.zip` 与 `NATIVE_EVIDENCE.zip` 已逐文件重读核对，大小和 SHA256 见 `SCOPED_EVIDENCE.json`。Godot 4.7.stable.official.5b4e0cb0f 的 console/child 引擎指纹也在该文件中。

## 保护及证据边界

`PROTECTION.json` 核对主树/第二树 HEAD、分支、index 和 dirty 状态；冻结 MonsterStreaming 字节不变。第三树当前 index SHA256 为 `df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb`，完整 staged-entry 输出 SHA256 为 `58f820e21ad45db9ee7606bcf143de644314f2b70b7551548475756dfd0f7733`。本轮当前原字节与完整条目输出额外备份在 `outputs/framework_v2/heterogeneous_20261004`；备份验证见 `INDEX_OBSERVATION.json`。

历史原 index `66c505…` 的字节连续性仍 FAIL，原备份 MISSING，原因未确证；不能用本轮未变覆盖历史缺口。原始审计正文、失败日志与 patch 保留原字节；若完整 diff-check 因这些证据空白失败，应与生产源码检查分别报告，详见 `DIFF_CHECK_BOUNDARY.json`。

父版本 Pro/小可爱完整报告及实际读取身份保存在 `audit_parent_87400315/`。本次尚未完成独立双审计；上述原生结果不替代审计，也不证明完整异构组合、所有恢复故障、设备表现或 APK。

## 继续施工

词缀、已嵌宝石和符文的正式来源组合、死亡子连锁及生成式组合仍开放；零损失及更广混合容量排列需要对应下一轮证明。旧破坏性故障 supervisor 安全复用、完整 P6/R3、原 v97 B 输入 MISSING 和 Android/GPU/APK 分项保留。
