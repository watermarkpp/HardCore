# v108 真机反馈修复记录

2026-10-09。当前在完整 `codex/integration` 主树修复，HEAD `215f0b2f651a51e6855ee813ddd99221690311a1` 和原暂存区保持。原 v108 构建来源 `92c6eeb93af9546b891ea0a1a15dd4f8c600502b`；首轮只读咨询快照 `b88de0d0d3580d60b9f6029005804ed986de10a3`。这里记录后续修复，不能拿旧 APK 静态 PASS 替代本次游戏验收。

## 修复及边界

1. **引怪与火墙唤醒。** 冷怪的正式目标获取原来需要通过 optional 查询、每帧八候选和 300ms AI owner 排队。密集场景中，HP 已下降但 target 仍为空，怪物继续等待。现在人物真实移动事件同步服务附近空间候选；正式身份、地图、代际、生命、范围、安全区和静态地形直线 LOS 通过后，使用原 target setter 同步激活。实际正伤害也直接给无目标冷怪建立合法 Player/Summon 目标。已有目标不会被抢换，不将静态 LOS 冒充 rich observation。追击、绕路和 Boss 非急维护继续使用原 300ms 及 optional 帧预算，攻击/伤害/真实碰撞仍走原正式链。动态怪物不遮挡这个静态引怪信号。
2. **零掉落。** 真实异步死亡存档返回成功后，原队列仍停在 `PERSISTING`，FrameBudget 将其判为不可运行；XP 已提交，但没有进入掉落 planning/materialization。成功回执现在进入 `SETTLING`，失败重试、代际取消、非活动角色和幂等保存门禁保持。
3. **批量掉落等待。** 一个很小的掉率行 quantum 原先消耗一个完整死亡任务名额。32 死亡在原 240 帧截止时只完成 17，剩余 15 仍 SETTLING，没有概率资料错误或重试。现在在原 slice 的 wall-clock 预算内连续推进单行 quantum，预算耗尽即保留游标；不扩大预算，不改变概率、RNG 顺序、6/9/12 输出上限及保护。相同 32 死亡变为 53 个工作帧全部完成，32 次 roll，RNG 和物品/坐标顺序与 eager 对照一致，最多 4 death jobs / 1 node 每帧（原测试上限分别 4 / 8）。这不是整机 FPS 测量。
4. **保存并退出。** 未完成死亡链会阻止安全退出，因此零掉落缺陷也能造成退出拒绝。修复死亡链后真实异步死亡可以生成物品并保存退出。失败时，原 HUD 提示被暂停菜单 CanvasLayer 200 遮住；新增菜单层内提示，保留失败诊断和已有存档，不绕过安全退出。错误提示显示时隐藏原 Footer，清除后恢复，避免文字重叠。
5. **启动静音。** 没有有效 v2 主/备份配置时，旧初始化把临时 AudioServer mute 状态当作玩家选择，生成内存 volume=0。现在用明确默认值 1.0，有效保存的 0 仍保持静音，等值设置也重新应用总线/服务状态。音效服务和音乐所有者不变。

生产只修改 `scripts/enemy.gd`、`scripts/game_root.gd`、`scripts/audio_preferences.gd`、`scripts/system_menu_panel.gd`。全部原 v107/v108 音频、拾取、特殊装备、价格概率、HUD/触控、Loading、受击与 300ms 架构工作保留；没有重做已搁置的加权掉落设计、人物/怪物格子玩法或 Android 环境方案。

## 验证账本

命令入口均为 `tools/run_godot_tests.ps1 -TestPaths ... -TimeoutSeconds 30`，console/headless；每阶段独立 `HARDCORE_AUDIT_LOG_ROOT`、`HARDCORE_AUDIT_RUNTIME_APPDATA`，新场景仅加入 `outputs/wake_drop_v108_repair_20261009/test.index` 私有索引，未改变真实暂存。实际路径、原生退出、invocation、源码/输入指纹均在下列 receipts 和 fingerprint 文件中。生产在原生运行期间冻结。

| 范围 | 当前状态 | 证据与解释 |
|---|---|---|
| 冷启动音量、真实音效服务、有效零值/非零值、等值重绑 | PASS | `outputs/wake_drop_v108_repair_20261009/audio_after/runner_results_adhoc_20261009_194226_819_22648.json`；修复前 FAIL 保留 |
| 严格主/备份配置及无效版本默认 | PASS | `evidence/runner_results_adhoc_20261009_200912_703_7524.json` 中 audio strict 项；之后相关音频源码未变化，复用 |
| 30 冷怪自然 movement callback 与真实 canonical firewall tick | PASS | `evidence/dense30_related_after.json`；同调用 30/30 目标，wake callback 1949us；此后仅同 root 的掉落函数改动，唤醒相关函数未变，复用该范围证据，不宣称新的全局性能成绩 |
| 零 optional allowance 下 immediate activation、近身攻击、Player/Summon 隐身 | PASS | `evidence/runner_results_adhoc_20261009_201327_044_24492.json` 中 owner 项；丰富规划仍预算限制 |
| 光环外物理、法术、ground/DOT 正伤害获取冷目标 | PASS | 同 related runner 中 passive damage 项；正式 Player parent 地图/代际匹配；不是玩家全部施法投射链重测 |
| 墙体、地图/代际、死亡、安全区等拒绝门 | PASS | `evidence/runner_results_adhoc_20261009_202908_991_4984.json`；正式 Home 身份/安全区、墙体拒绝、同地图动态 Enemy 不遮挡、可见 Summon 立即激活、隐身 Summon 拒绝、正伤害不抢已有目标、零伤害及跨地图拒绝；新 fixture 的原 parse/probe FAIL 保留，最后修复仅 fixture 旧 Rect2 条件及硬编码旧 map 4 |
| 真实 paused 菜单 signal → root save/exit 的 Home/save 失败 | PASS | related runner 中 `safe_logout_exit_guard_test`，可见非空失败文字、原存档保持、Continue 解除暂停；之后 Footer 显隐小改由下一项验证 |
| 菜单 Footer 与失败提示互斥 | PASS | `evidence/runner_results_adhoc_20261009_201814_754_6680.json` 中 menu 项；同 runner 的其他 FAIL 不当作整组 PASS |
| 异步死亡 prepared receipt | PASS | related runner 中 `f03_async_death_receipt_test`；PlayerState/JsonPersistence 生产未改，复用 |
| 正式 test_mode=false 自然死亡 → HP/died → durable receipt → 实物 → safe logout | PASS | `evidence/death_natural_after.json` 与 `evidence/runner_results_adhoc_20261009_202316_370_8332.json`，12 节点、XP2500、337.936ms、logout 保存成功；原 PERSISTING 卡死 FAIL 保留 |
| 32 实际死亡、240帧期限、RNG/物品/位置/幂等及每帧上限 | PASS | `evidence/death_batch_after.json` 和同 drop_batch runner；此前 17/32 FAIL 在 `evidence/death_batch_before.json` |
| durable receipt / generation cancellation / root teardown / reload | PASS | 同 drop_batch runner 中 F03 native；旧 `free()` 应 roll1 的断言与已批准的延后掉落合同不符，现严格要求 teardown 不新增 roll，同时保留所有 XP、respawn、receipt 幂等、pending0 和 reload 断言。完整掉落单次由前两项覆盖；旧失败保留，未在 `_exit_tree` 新建地面物品 |
| 新 APK 构建/安装/设备验收 | NOT_RUN | 这次只完成源码修复，没有修改桌面原 v108 APK，也没有手机当前连接证据；DEVICE TEST: NOT_RUN |
| 本轮 Pro 外部分析 | BLOCKED | 已在用户指定的“项目助手工作线程”派发并实际读取回复，本轮返回模型使用限额，没有分析内容；旧 Pro 报告不能当本轮审计 |

各阶段根目录为 `outputs/wake_drop_v108_repair_20261009/`。`*_fingerprint.json` 记录执行理由和实际受测源码/input SHA256；failure 结果不删除，不合并不同源码阶段为一次全项目 PASS。新增加的源码/输入、失败修复及缺失分支才复测；未变的旧业务与已验证 Android Java TEMP/TMP 回环修复不重复执行。

## 交付限制

这份记录只支持相应本地源码和原生专项结论。未验证修复后的 Android 画面、声音实际输出、手机 FPS、APK 内容或用户手感。远端分支为 `codex/v108-runtime-bug-review-20261009`，固定提交身份由推送收据另列；不能使用 MAIN 旧 HEAD 冒称包含本轮 dirty 修复。
