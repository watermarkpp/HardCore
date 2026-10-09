# v108 独立审查意见接入与 v109 前置验证

2026-10-09。审查材料来自用户提供的完整文本，原样保存在 `INDEPENDENT_REVIEW_XHIGH.md`，审查基线为 `61d5b03f0568fee0f9c88fa2c20fbe93861c5095`。材料是待核验发现，不自动扩大玩法或删除授权。用户最新要求：继续“项目助手工作线程”，仅极高；本轮修复闭合后开展全项目分块审查，确认的缺陷修复并必要验证后封装109。

## 接入与处置

| 审查项 | 当前状态 | 处置与证据范围 |
|---|---|---|
| 临时 pending 被永久退出失败字段锁存 | PASS | 当前源码只将真正 FAILED 写入失败锁存。真实 profile_changed 重入返回 pending，外层完成死亡链，后续退出成功；重复退出不重复 XP、roll、节点或 terminal。真正存档失败仍拒绝并锁存。direct05_logout 原生退出0、44检查，roll1、节点12；1级升15级、剩余经验706、死亡收益2500。不能据此断言用户手机原故障必然经过重入分支 |
| 投影不可用吞掉激活事件 | PASS | 已补当前地图/代际的去重事件保留，复用正式 process pump，不加计时器或全图扫描；direct06_projection 无新movement恢复30/30、玩家存活、失效候选0、队列去重1、旧代际拒绝、新事件30/30，原生退出0、stderr为空。专项冻结actor physics并在常规GameRoot process后立即取样，只证明激活，不能冒称攻击或FPS。direct01–04 的失败证据全部保留，部分 fixture 解析错误和角色在取样前死亡不能当作生产行为结论 |
| 活 Node 但不再合格的旧目标阻塞新唤醒 | PASS | 检查目标生命、地图/代际、安全资格；有效既有目标、已提交攻击保持；完整新候选gate通过后才退役旧目标。related08五项通过，direct09额外确认已释放Summon主人及缺少owner schema安全拒绝；原生退出0。related07的int(null)失败已修，仍保存旧FAIL。此前direct01同runner其它场景FAIL不能当整组PASS |
| 同 process 多移动事件必要工作峰值 | PASS | direct06记录30合格怪、十次同步movement事件：10空间查询，回调合计14073us、最大2196us。仅测量动作回调已完成；这暴露扎堆峰值风险，不能宣称预算风险已消除。不是真实physics补步、107对比或Android帧率证明；不能恢复8候选限流或300ms激活等待来制造提升。全项目首批继续审查此风险 |
| 实际发布地图怪物的正式掉落覆盖 | PASS | 只读 join：67地图、2638正式刷怪语义行、120独有稳定怪物ID，全部有可运行身份、available人工表状态、非空启用 DIRECT_21CQ profile，缺失0。36目录ID未在当前发布地图刷出，不能冒称掉落缺项。`DROP_COVERAGE_REVIEW.md` 与 outputs 对应 JSON；未修改资料或 fallback |
| Android 前后台/音频焦点重绑 | NOT_RUN | 冷启动相关专项保留；没有真实Android焦点恢复证据，先作为全项目音频生命周期审查范围，不凭猜测加timer/重试 |
| 进程被杀时 XP 与掉落恢复事务 | NOT_RUN | 作为全项目持久化/恢复边界审查，不能当作本轮PERSISTING卡死的同一缺陷或凭审查建议直接变更存档合同 |
| 原生测试退出时对象/资源释放 | FAIL | direct05功能断言及原生退出0，但stderr仍报告13 ObjectDB泄漏与3 resources still in use；旧death_queue_lifecycle也报告8/3。runner聚合的engine_log_errors=0不覆盖该stderr清理错误。保留记录，交资源生命周期精查；不宣称无引擎告警或全系统PASS |

## 证据与源码边界

本轮生产只补 `scripts/game_root.gd` 与 `scripts/enemy.gd`。音频、菜单、正式PlayerState/JsonPersistence、掉落资料、碰撞、特殊装备和原有v107/v108工作保持。真实主树 HEAD 和真实 index 未改变；提交身份由后续正常推送收据给出。

证据根为 `outputs/wake_drop_v108_review_followup_20261009/`。每阶段 fingerprint 记录相关源码/场景 SHA256、实际runner命令、复测原因和隔离数据目录；runner含 invocation、原生退出、超时与场景结果。direct05_logout_receipt.json 是完整成功/失败门禁实物回执，未删旧失败。

全项目标准提示词、逐文件范围与进度账本位于 `docs/review/full_project_audit_v109_20261009/`。当前仅准备范围，不冒称外部已审查。不能将局部专项、源码审查、APK导出或设备验收混为一个PASS。

相关激活最终回归：related08 的真实30怪自然movement/正式firewall、零optional攻击与owner、正伤害冷唤醒、projection恢复与代际、stale/schema五项PASS。之后只将Summon主人非空检查改为is_instance_valid，direct09针对释放生命周期再验证；有效正式owner其它分支不变，按范围复用证据。此处是功能验证，旧R3 fixture高HP设置不用于任何性能提升声明。音频、菜单、死亡批次源码相关函数未变，沿原记录复用。

NEW APK: NOT_RUN。DEVICE TEST: NOT_RUN。v109 尚未封装。
