# 2026-09-09 两包整合施工记录

状态：施工中，未验收，未产出本阶段 APK。

## 授权与基线

- 用户要求完成 V3/R3 收尾报告与 24 项施工包，整合后准备下一阶段 APK。
- 初始主树 `codex/integration`：`cf1d2718befdef7e6cc2fb274fd91ce0759d105f`，初始工作区干净，bootstrap PASS。
- 附件审计基线 `275eef8b9455c7f3ef63daaf59dfff3c06e26069` 到当前主树仅爆率验收文档/工具变化；不得回退这部分。
- V3 独立树保留原暂存候选；未经本轮有效验收不当作已通过。
- 附件为需求与待核验技术建议。旧文档中的暂停提交状态不替代用户本次整合授权；未运行的验收不能因获得授权而记为 PASS。

## 最新人工验收关口

用户补充：装备/物品属性面板修改完成后放进校准器，由用户检查合格后再继续。

因此属性面板候选允许实施和校准预览，但必须等人工确认再集成及纳入最终 APK。其他互不依赖的施工继续。不得把自动测试或截图生成等同用户接受。

## 统一范围

- 原问题编号保留为 1/3/4/5/7/8/9/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27，共 24 项。
- V3 REV01–08 与 W1/W2 共享攻击、WORLD、路径和性能验收，避免建立第二套 owner。
- 新请求中的怪物动态不穿透是明确行为变更；旧性能基线的无怪物碰撞条件不可据此否定新需求。保留速度、节拍、数量、静态地图和正式空间索引。
- 爆率概率/槽位/保留政策及用户已完成数据保持冻结；完整实例传递、合法地面落点与显示属于本次指定边界，不改爆率抽样。
- 近战 2 GU 起手、1.5 GU preferred 基准、0.25 GU delayed tolerance、特殊投递排除、Canonical Skill Runtime、Snapshot V2、投影和既有批准视觉保持。
- 普通测试 30 秒，重场景最多 60 秒。保留失败原始日志，最后同一候选 Critical 一次；设备/实际渲染缺口单列。

## 当前包

| 包 | 状态 | 所有权/验收 |
|---|---|---|
| V3 复审与 W1/W2 接口 | 复审核验完成，返工待接；WORLD 选中/雷电已接入 | V3 staged 候选、REV01–08；禁止拿旧弱夹具当通过 |
| W4 音频 | 隔离树施工中 | audio service 与 Enemy 音频区域；独立缓存 |
| W5 属性面板 | 隔离树实现与校准预览中 | 用户校准验收前不集成 |
| W3 Loading/升级、W7 事务 | 核心首段已提交，银行高风险复审返工中 | 延迟敌人攻击 epoch 接线仍待完成 |

## 分段证据（不是全包验收）

- `2ceb73b0`：Loading 首次 await 前的伤害隔离、死亡入口优先级、成功升级补满资源、实例身份与指定空格卸装事务接口。Loading/死亡失败、换装/升级专项均有通过记录；最终提交后 Loading 单项 1/1、引擎错误 0。
- `7468943c`：法术锁定 10 GU、玩家目标 WORLD 过滤、雷电正式起手/释放/伤害 LOS、MC/SC 消费既有幸运公式。`world_cast_stage_b` 保存正式施法与既有输入 2/2 PASS、引擎错误 0 的 runner 和原始日志；此证据运行于提交前候选，银行当时存在未提交变更，不能称干净 HEAD 全包证据。
- 银行已覆盖 100000 转账、上限、旧余额保留迁移、故障回滚的初步专项；复审发现共享快照回退、WAL 资金守恒与记录校验风险，正在返工，当前不予接受。
- 掉落合法落点及隔墙拾取检查正在实现，未测试接受；不改爆率概率、槽位、随机抽样次数。
- 上项后续：真实 WORLD 落点/隔墙拾取、死亡队列预算、旧仓库迁移、目标索引专项 4/4 PASS，engine errors=0，见 `bank_and_loot_stage_c`。第一次失败原始日志保留在 `loot_world_first_failure`；队列专用夹具无正式地图，明确隔离位置 provider，实际墙体由新增正式场景承担；拾取场景禁用玩家物理推进以隔离射线与收集调度，不宣称完成玩家碰撞验收。
- **原始日志复核修正**：上述 `engine_log_errors=0` 只是现有 runner 的未放行错误计数。`bank_and_loot_stage_c/loot_world_placement_integration_test.stderr.log` 实际含 dummy renderer `Parameter "t" is null`（world_bootstrap_coordinator.gd:645）及退出资源报告；现有 allowlist 已放行这些文本，本轮未改 allowlist。功能断言 PASS 与 R3-REV-08 渲染/严格无错误验收分开，后者仍 OPEN。
- `41471a79`：银行三文件已提交。接受单进程同步共享仓库合同；账户级高水位拒绝旧序号重放，保留最近 64 条审计。多进程同时写档不在当前运行合同，未来支持需 OS 级锁。
- Android 隔离构建预检：`build_android_isolated.ps1 -Commit 7468943c -BaselineApkPath outputs/hardcore/HardCore-20260906-gameplay-audio-debug.apk -PreflightOnly` PASS；旧脚本默认 v38 基准包不存在，显式改用磁盘现存 9 月 6 日包通过。本项只验证工具链/提交配置，不是 APK 构建或设备验收。正式候选需更新版本并在用户校准确认后重新固化 commit。
- `monster_delivery_inventory.csv` 记录全部 153 个 runtime_allowed 条目；ID 50 掷斧骷髅当前缺 attackDelivery，原始 `ObjAxeMon.pas` 有 FlyAxeAttack/CanFly 及 `UsrEngn.pas` race 87 分派。原始类到正式 ID 的完整映射与 actor 正反例仍待补齐，CSV 的 PENDING_ACTOR_PROOF 不代表通过。

## 最终验收

待逐项填入实际代码、正式测试、设备和包身份。当前所有未交付项均为 NOT_RUN/IN_PROGRESS，不宣称已修复。
