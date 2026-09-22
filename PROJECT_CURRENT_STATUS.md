# HardCore Current Status

Branch: `codex/integration`。Updated: 2026-09-22（Astra→Codex 交接现状）。

## 2026-09-22：RV14+RV15 联合成果落主树 + 内部测试 APK v91 + main/integration 统一

**接手者先读**：本轮把 9 月 audit 线全部成果（887 个提交，含 RV14 补件、RV15 手修爆率、九怪精英化与 6144 槽掉落权威、编译链参数化）合入了 `codex/integration` 与 `main`，并交付内部测试 APK。历史合同中"主树=e388e159"已过时，实际主树状态以本节与下述 SHA 为准。

### 一、分支状态（全部实测，2026-09-22 13:4x）

| 分支 | 本地 | 远端 | 内容 |
|---|---|---|---|
| `codex/audit-bugfix-performance-20260921` | `85d37077` | `85d37077`（=`codex/rv14-rv15-joint-review`） | 9 月施工线最终源（critical 409 项验证树） |
| `codex/integration`（主树） | `85d37077` | `85d37077` | **快进**至 audit 最终源（5cdf038e→85d37077，无冲突） |
| `main` | `c74a7108` | `c74a7108` | **merge commit**（audit 线 + main 独有 8 提交融合，见裁决记录） |
| `codex/rv14-rv15-joint-review` | — | `85d37077` | review 镜像分支 |

演进链：`3f8cb3dd`（联合复审注册）→ `2b4ef9ef`（九怪精英迁移+overlay 首轮）→ `565711f7`（178 花吻蜘蛛补齐 144→168 槽）→ `85d37077`（编译链参数化+overlay 确定性合成）。工作树 `C:/Users/Administrator/Documents/HardCore` 当前 checkout 在 `main`（c74a7108）。

### 二、main 合并裁决记录（c74a7108，接手必读）

main 独有 8 个提交（8-20 的"217 身份闭合"战役+handoff 文档）与 9 月生产线的"156 活跃目录"合同（P3C）不相容。按用户指令"以现在的进度为准、主树和 main 一致"，裁决如下：

- **生产合同保留 9 月已验证状态（156 活跃身份）**：`canonical_monster_classification_v1.json`、`canonical_monster_catalog.json`、`tools/build_canonical_monster_catalog.py`、`tests/canonical_drop_item_alias_test.gd`、`tests/canonical_monster_classification_closure_test.py`、`tests/monster_world_integration_test.gd` 六文件取 audit 版本。依据：该合同树是 critical 409 项（399 PASS / 10 已知债）与 APK v91 的构建验证源。
- **217 闭合合同不丢弃**：提交 `ea01f197`…`066e84f6` 完整保留在 main 历史；仅其活体断言不留在生产树（与 156 合同矛盾）。
- `SOL_HANDOFF.md`：保留 main 的 2026-08-20 handoff 入口头部，融合 audit 侧正文。
- 合并后冒烟（c74a7108 树）：6 项掉落域/目录合同 5 PASS + monster_world :353 m76 V505（既有基线，merge 前同位同错）。

### 三、本轮交付成果与验证

- **RV14 五补件+RV15 手修爆率+联合复审**：全部在链（7bbf46b7…3f8cb3dd）；确定性注入与 suite 注册闭环。
- **九怪精英化+赤月/祖玛 overlay 掉落**：七怪（164/166/168/170/172/178/182）elite、174/176 保持普通；权威 JSON 126 怪/6144 槽（5976 编译基础+168 overlay）/UID 全集唯一；178 花吻蜘蛛按用户原指令"其他的"分母组补齐（565711f7）。
- **编译链最小修正（85d37077）**：路径参数化（隔离树不再读写旧主目录）、工作簿双模式（实盘哈希门禁/存档解析行回退+SOURCE_BINDINGS 绑定 bc234fca）、版本化 overlay 合成（evidence/user_directive_overlay_slots.json 全槽记录）、白名单/新行/意外排除失败改为 exit 1、两次重建字节相同（F0BA6AD7…）且与正式权威 6144 槽逐 UID 语义一致。
- **验证证据**：最终源 critical `runner_results_critical_20260922_122847_005_18084.json`（git_head=85d37077，total=409，passed=399，failed=10，10 项全部与基线同断言同因）；干净检出门禁 7/8 PASS（唯一 FAIL=m76 基线）；三份运行 JSON 与对照判定见 `D:\HardCoreAudit\RV14_RV15_JOINT_REVIEW_REPORT.md`。
- **内部测试 APK v91**：`D:\HardCoreAudit\HardCore-20260922-rv15-loot-overlay-85d37077-v91-debug.apk`（480,041,367 B，SHA256 `71E841585D333706FE87B192285649C3BC8F443D1B83F452D24D5F837F0DCDCD`，versionCode=91/versionName 同前/包名 com.personal.mafaoffline/同 debug 证书）。构建与包内核验全 PASS（ANDROID_ISOLATED_BUILD_PASS / DIRECT_UPDATE_IDENTITY_PASS / RUNTIME_RESOURCE_PROBE_PASS；包内权威 JSON 语义 6144/168/m178=72、分类权威与 catalog 字节级一致、掉落链 gdc 在包）。首轮 v87 因用户手机实际安装版本为 90（9-19 更新，非本地 v86）失败，v91 同源重打包修复。构建细节见 `D:\HardCoreAudit\RV15_INTERNAL_TEST_APK_BUILD_MANIFEST.md`。
- **用户设备**：手机 AADMVB3602042319 已连接；用户选择直接覆盖安装 v91（versionCode 91>90、同签名，存档自动保留）。卸载前已做完整存档备份 `D:\HardCoreAudit\hardcore_save_backup_v90_20260922.tar`（3 角色+仓库+配置，93 条目，JSON 可解析）。设备实测结果待用户反馈，DEVICE TEST 状态以用户回报为准。

### 四、已知债务（不阻断内部测试，清单见 `D:\HardCoreAudit\RV15_INTERNAL_TEST_APK_KNOWN_ISSUES.md`）

critical 10 项 FAIL 全部为既有基线/环境类（canonical_skill_production_entry :222 魔法盾末帧、skill_contract_manifest :57、w6_visual_contract :170、inventory_equipment_ui :142、equipment_luck :182、hud_authority :177、shop_gothic_ui :140、warehouse_gothic_ui :303/:342、monster_world :353 m76、runtime_test timeout）。四项 worktree→主树转 PASS 的逐项归因（缺产物/时序/引擎日志）与 warehouse 单列环境差异已在联合复审报告第 7 节登记。

### 五、接手注意事项

1. **冻结/保留对象**：`HardCore_r14_base` 工作树（12 M+10 untracked，用户裁决前不动）；真实地图重新发布 R01 HOLD；用户桌面工作簿 bc234fca 已不在磁盘（编译链走存档模式，勿臆造重建）；`codex/rv14-rv15-joint-review` 为 review 镜像。
2. **untracked 现场勿清理**：`outputs/`（测试日志/编译证据/交付脚本）与各 worktree 的 `.godot/` 为运行产物，历史轮次按"保留待用户确认逐树清理"处理。
3. **测试纪律入口**：分层漏斗与三分类规范按用户长期规则执行；正式结论只认 `runner_results_*.json`；m76/V505 等基线债勿在本轮范围外顺手修。
4. **AGENTS.md 变更**：5cdf038e 落了协作规则改写（本地 integration 曾领先远端的唯一提交），已随快进进入主树。

## 2026-09-20：全量合入——墙体 P1R 战役 + 受击 V4 历史闭环

- 集成落库源码：wall 合并 `fdb298c2`（codex/wall-p1r-final-v2 @ ab0d5524 → integration @ 3d572da1，唯一冲突 game_root.gd 按"R13 计时行 + P0-3 pre-arrival 失败接管 + 常规 guard"并集裁决；P0-3b blocked-arrival 重定位与 R14 相机约束共存）；受击 V4 归并 `88784258`（13 文件中 12 个 blob 级相同、player.gd 唯一改动已在集成 L1148 原文存在，合并零内容变更，仅关闭祖先链）；`.uid` 侧车入库 `ed497c32`；注册契约对齐 `ade575d1`（map_runtime_release_critical 期望列表 5→14 对齐 HC-POLY-R2 实际 suite）。
- 门禁（同 commit ade575d1）：注册检查 PASS；冒烟 PASS；受击 V4 六场景 6/6；相机五场景 5/5；多边形九场景 9/9；map_runtime_release_critical 14/14；transaction critical 6/6；P0-3 转移专项 3/3；R11 force_legacy gate PASS；R7 全程直跑 `WALL_RENDER_R7_STRICT_PASS hops=16 checks=74`；R6 全程直跑 `WALL_RENDER_R6_STRICT_PASS maps=67 a_maps=60 checks=387`；monster 45/47；full critical 360/377。
- 失败逐项基线归因（对照 3d572da1 主树与 ab0d5524 wall tip）：14 项同断言基线旧债（含 ID76/V505 :344 既有接受债、fire_wall_exact_2x2、W7 affix、共享金币 :342、shop 价格行等）；2 项摇摆/噪声（canonical_skill_production_entry 三次运行断言点 :154/:184/:222 跨两树漂移，技能代码与数据零差异；source_collision_chunk 自身 PASS 后仅退出期引擎日志噪声，隔离复跑 PASS）；1 项环境（complete_client_resource_catalog 新树缺 outputs/resource_catalog 生成产物，重建属冻结验收管线待用户授权）。**本轮零合并回归。**
- classic_boss_order_test 按方案 E3 十次专项：候选隔离 10/10 PASS；基线 9/10（第 7 次复现同断言 :104）→ 既有间歇债。
- APK_BUILD=NOT_RUN；打包前检查与工作树清理见本轮交付报告（HardCore-consolidation-evidence/20260919-2）。设备帧率/触感 NOT_RUN。

## 2026-09-14：物品详情、Buff、设置与地面名称 v81

- APK源码 `4f4462ad027714acf657c7a2ac28fa4f15a6e293`。物品详情按实际最长行宽度整体居中，各行保持左对齐，名称单行居中且★独立；标题20/正文14不变。设置布局已由用户验收，正式功能验证通过。
- 持久单独增加不算JP；地面图标在人物/技能下、名称事件驱动防重叠；10项精确分类调整；沃玛教主命运之刃新增1/24槽，原108槽/概率/优先级/15上限不变；共用Buff行及12类神水到期属性和图标清理验证。
- 31不同场景分批最终PASS，固定源码4/4 PASS。桌面 `HardCore-1.0-v81-release.apk`，81 / `hardcore 1.0 正式版`，466,010,045 bytes，SHA256 `6AF911A381AA5D567B6086D698EC4480FAC9316192D4E6BAEE50B96E4705D89E`。
- APK同签名覆盖、源码身份、冻结内容验证PASS；228其他运行时脚本/8983其他资源项与v80相同。沿用项目development导出和旧签名。旧APK/标签及用户现场保留；设备NOT_RUN，旧冷UI/故障回滚/多怪安卓性能债务未由本轮测试消除。
- 里程碑 `milestone-hardcore-1.0-v81` 固定上述APK源码；交付和远端核对见 `docs/loot_ui_20260914/DELIVERY.md`，后续文档提交不是APK源码。

## 2026-09-14：人物成长、神水、地面过滤与掉率 v80

- 源码 `fa4a1ffa88f7d2ec20d83a8548afc2d4b99d1393`，三职业裸属性统一到主服务端生成链；神水正式计时到期、单个与旧堆叠无损拆分、当前仓库页整理、JP范围合并及★、药水颜色说明、三挡即时过滤与600秒地面回收。
- 按用户DOCX明确倍率调整765原槽并向M159复制17槽，原台账/优先级/15上限保留；Excel仅比对，不参与规则。
- 26场景分批最终PASS；固定源码3/3 PASS。APK 80 / `hardcore 1.0 正式版` 已在桌面 `HardCore-1.0-v80-release.apk`，465,996,946 bytes，SHA256 `D8B9E5FF0C395F354997A0F0ED8E7E4F996C1433191D07C04CA5C7F76746F52D`。
- APK同签名升级和内容核对PASS，221其他脚本/8979其他资源项与v79不变；已接受校准布局冻结。手机性能/设备NOT_RUN，既存冷UI及故障回滚延迟保留明确记录。
- 快进合并integration；源码里程碑 `milestone-hardcore-1.0-v80`，旧标签与桌面旧包保留。详见 `docs/progression_loot_20260913/DELIVERY.md`。

## 2026-09-13：人物属性与稀有度复核 v79

- 用户批准校准器候选：恢复人物属性标题，角色名/职业等级居中，正文按零至三位数自动增宽并整体居中，保持固定字号和十行；完整等级含数字可点击查看经验。
- 175 项装备按用户 DOCX 精确 ID 分类；三类衣服男女六项按祖玛橙色，赤月紫色，极其稀有红字暗金边。修改仅为显示策略及 UI，不改装备数值、掉率或已接受玩法。
- APK 源 `98b38830ea074084cde49e964b3ca1da15263417`；79 / `hardcore 1.0 正式版`；桌面 `HardCore-1.0-v79-release.apk`，465,961,383 bytes，SHA256 `3FEE8F55D649090C52C8C5165DF9CBC1ABD006FEADA09CD3F07536CD0FABCDA8`。
- 最终源码专项 3/3、合并冒烟 1/1 PASS。背包、仓库、购买页分别覆盖 188 ID；原旧商店价格断言和仓库单场景超时已分类并按当前合同复验。包内 228 个其他脚本、603 项其他数据与 v78 字节相同，原校准表和签名不变；设备 NOT_RUN。
- 快进合并至 integration，源码以 `milestone-hardcore-1.0-v79` 标记，原 1.0 里程碑和桌面 v78 包保留。详情与原始证据见 `docs/ui_character_review_20260913.md`（快照相对路径 `ui_character_review_20260913.md`）。

## 2026-09-13 hardcore 1.0 正式版里程碑

- 用户接受 v77 的其他功能后，本轮完成完整人物属性与点击说明、精确名称颜色三端统一、抗拒火环动画和判定中心修正。源码固定 `00ca013d032346fc2e0020388933de9ad23ec8dc`。
- 版本 78 / `hardcore 1.0 正式版`；桌面 `HardCore-1.0-release.apk`，465,955,859 bytes，SHA-256 `E687CB8F6A871B2BAD9B2BDDBF83A427FA24047FF16B7BDB57BD5ECA3E379E01`。原包名与签名保留，覆盖安装资格、包内源码与冻结资源校验 PASS；新 APK 未安装手机。
- 18 个不同专项场景分批 PASS；源码提交后核心 4/4 PASS，合并后主副本缓存刷新并复验通过。9 个预期脚本改变，其余 225 个运行时脚本和 603 项数据与 v77 字节一致。
- 标签 `milestone-hardcore-1.0` 固定 APK 源码；主工作副本恢复 `codex/integration`。详细规则、原始失败和证据见 `docs/milestone_1_0/DELIVERY.md`。下文旧阶段记录仅作历史，不替代本轮结果。

## 2026-09-09 V3/R3 与 24 项整合

- 最终生产源码固定 `909821c928ddb66e5fd48f7cef718baa2e8bfe03`；后续提交为证据与文档。功能施工与集成已完成，12 条来源不足的精确 ID 保持 DATA_HOLD。
- 属性面板已按用户批准使用：标题20/正文14、内容自适应、优先背包空位、装备详情邻位允许覆盖纸娃娃。不再等待重复校准。
- 完整 Critical 基线318/344，26个失败修复后全部分批复验通过；影响回归34/34，渲染三轮各3/3。输入/补丁组合5/5，真实菜单/冒烟2/2，最终移动向量边界3/3。不冒称一次最终HEAD全套全绿。
- 持续攻击相关输入生命周期、模拟鼠标、指针所有权、暂停/失焦/Loading清零均已修复并验证；6 Pro普通聊天审计的新增边界已处理。尚未在故障手机确认消失。
- 热补丁使用真实包内身份路径；身份未知拒载，版本失配定向退役旧PCK，存档保留。APK以72 / 1.21.0-r3-closure构建，对照桌面v71验证覆盖资格。成品结果见本轮交付记录。
- **性能验收未完成**：最终8bf77a34四场景×三数量全部12项未达标；30怪近战23.451ms、拥堵25.443ms，较旧版11.962/11.720ms仍退化。下一阶段测试包不代表性能与设备验收通过。
- 详细范围、测试锚点、原始失败与限制见 `docs/bugfix24/20260909/FINAL_REVIEW.md`、`CONSTRUCTION_CONTENTS.md` 与 `ACCEPTANCE_MATRIX.md`。
## 2026-09-06 玩法与精确音频升级（最近已构建包）

- APK 源码锚点 `e6939a74fb091db24683c738fb85fb977d580cd0`，版本 `71 / 1.20.0-gameplay-audio`。完整安装包已放桌面 `HardCore-20260906-gameplay-audio-debug.apk`，461,365,538 bytes，SHA-256 `A759922572001C43B00C329C7FE398BDF979B70F07B20B53137B32A05898772F`。版本/签名/资源验证通过，交付身份见 `docs/upgrade/20260906/DELIVERY.md`；未安装手机，实机听感/玩法待验。
- 音乐 6 秒且播放不截断；NPC 单语音随机切换与 BGM 独立；522 个精确音频事件，无法确认来源/材质映射的声音保留为空，不猜配。
- 召唤物防御与最终传送落点、首本技能 1 级、全图随机卷、物品/掉落 ID 链、主源远程射程、普攻/烈火 2 GU、半月 2 GU/120°、刺杀 3 GU/末端 1.5 GU 无视防御及当前经验门槛再除 3 已接入。保留地图/怪物数/AI 节拍和已批准升级动画。
- 完整 critical 首轮 310/317，7 个失败均完成夹具修正后分批复验通过；音频核心 3/3、相邻 6/6；最终干净代码锚点最小专项 3/3 PASS。不是一次全套全绿。正式成功/失败 JSON 已入 `docs/upgrade/20260906/evidence/`。
- 尸王人工倍率未变：当前十只零掉落概率约 16.96%；修复的是正式物品身份传递，未擅自增加保底。详情见 `docs/UPGRADE_20260906.md`。

## 2026-09-06 复活后怪物视觉与经验/音乐跟进（前一版）

- 源码 `571db0bc`：同图死亡回城保留怪物视觉 generation/订阅，真实跨图隔离不变；死亡扣本级总升级门槛 10%（封顶已有经验），主城音乐默认音量 70%。未修改地图、AI、怪物数量或已批准升级动画。
- 最终源码专项 3/3 PASS、0 engine errors；最小累计热补丁 1,445,316 bytes / 13 项，无删除项，独立基包加载通过。手机已加载精确最终 patchId/SHA，loadError 为空，存档保留。
- 启动后比奇 82 个视觉注册，屏幕内 6 个活怪正常显示；实机死亡回城后再接近怪物仍待用户验收。完整根因、包身份及证据见 `docs/hotfix/20260905/FOLLOWUP.md`。

## 2026-09-05 经验与城镇音乐 hotfix（前一版）

- 源码 `0abc83e9`：经验门槛 10%、经验条横跨四快捷物品槽、一次成功结算仅一次升级动画、技能音效关闭、主城安全区 Loading 后 10 秒一次背景音乐。用户已批准 75% 光焰及人物前后遮挡视觉。
- 干净源码专项 7/7 PASS。最小补丁 `hotfix-20260905-xp-town-minimal` 为 1,404,188 bytes，SHA-256 `1643D8D05276D4DF45A823697645173C6D27A654C37B60238F024086BA501434`；独立基包+补丁加载验证通过。
- 手机已安装精确里程碑 APK70；本次只原子替换旧补丁，备份并保留存档。手机运行回执已确认新 patchId/SHA，loadError 为空。玩法及音乐听感等待用户实测，不宣称全部手动验收完成。详见 `docs/hotfix/20260905/DELIVERY.md`。
- 首次全量导出夹带无关资源和两个删除项，被安全检查拒绝、未安装；最终仅 12 项精确闭包，无删除项。主树交付记录保留失败与成功证据。

## 2026-09-05 审计里程碑（历史基包记录）

- 审计修复及 APK 构建完成：构建提交 `52ae0565856c2d99a28639b2bf0c6278186e0858`，版本 `70 / 1.19.0-audit-milestone`。桌面文件 `HardCore-20260905-audit-milestone-debug.apk`，大小 449,193,057 bytes，SHA-256 `26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664`。证据见 `docs/audits/20260905/MILESTONE_APK.md`。
- 全量 critical 295/298 PASS；余下三项在干净构建提交独立复验 3/3 PASS，正常退出且错误计数为 0。不是一次 298/298 全绿。签名、build-info、运行时资源与实际构建目录的 67 图/208 纹理闭包通过；126 项 CRLF 检出字节差异逐项证明无内容漂移，原始 FAIL 记录保留。
- 用户已拔手机，要求回来再安装：本包未安装、未做新版本实机验收，手机存档/补丁未改动。后续只用精确 SHA 包安装并复核三职业 40 级赤月档案。
- 主树及标签 `milestone-20260905-audit-upgrade` 已同步并核对；标签固定 APK 源 `52ae0565`，主树后续含交付文档证据。13 个旧/临时构建工作树已在远端核对和归档后移除，两次磁盘采样净增 52,050,092,032 bytes（约 48.475 GiB）；源提交、重要包/日志及共享工具保留。详见 `docs/audits/20260905/CLEANUP_COMPLETED.md`。
- 已人工验收的怪物密度性能基线 `c97a08b43832b174f98de31f5ed6673ccda344ae` 已归入 `codex/integration`。该基线不是本轮全部审计通过证明。
- 当前工作树、专业领域、冻结保护与代理调度以根目录最新 `AGENTS.md` 为准。下文旧“只在主树修改”是历史阶段记录，不否定本轮由 integration 明确分配的隔离专项树。
- 下文旧 PASS、旧 APK 和旧标签仅作历史证据，不代表当前 HEAD 验收结果。本轮源码构建锚点与后续证据文档提交分开记录，文件变化必须以实时 Git 为准。

## Current HEAD

Use annotated tag `standard-20260829-main-tree` for the immutable consolidated standard. Formal runtime/map baseline is `00f6e5e6525a4a07679b41eb482a2cfd05fdd068`.

## Current Stage

**MAIN TREE CONSOLIDATION CLOSED / DEVICE ACCEPTANCE CONTINUES**

## 2026-08-29 Main Tree Standard Freeze

- 地图、怪物、装备、职业、UI、地图编辑器、素材编辑工具和校准器已按提交与工作副本双层筛查，正式内容统一收口到 `codex/integration`。
- DeepSeek/DSH 工作树的正式地图编辑器、footprint 校准、XZSC 素材导入/校准及怪物编辑器成果均已在正式历史中；未倒灌中间版本和旧 217 怪 Authority。
- 所有仍有历史价值但不应启用的 WIP、候选数据和校准证据均已保存到远端 `archive/*-20260829` refs。
- 以后正常修改只在主树完成；临时工作树验收并合入后立即删除。可热修内容继续通过补丁进入 APK，超出热修边界的重大修改重新打包。
- 完整证据与恢复点见 `docs/handoff/2026-08-29/MAIN_TREE_STANDARD_FREEZE.md`。

## Historical 2026-08-10 Foundation Audit Closure

## 2026-08-10 Foundation Audit Closure

- 全项目按 UI/数据、地图发布、职业战斗、核心世界/存档四个互斥范围完成 Sol high/xhigh 审计、修复和集成；Monster Streaming 继续遵守既有 `HOLD`，未修改冻结生产实现。
- 关闭的主要缺陷：安全退出误报成功与坏档无备份恢复；canonical 资源提交/召唤 descriptor 丢失；玩家和召唤物死亡重复结算；投射物重复建立释放快照；地图候选跨文档发布、registry 非 fail-closed、显示名覆盖；HUD 出售/任务放弃/仓库排序无权威消费者；仓库上限与弹窗布局；12 个女性盔甲主表缺失；Android build-info/dirty/编译脚本验证不完整。
- 正式关键回归：`critical = PASS 250/250`，`failed=0`，`engine_log_errors=0`；来源优先级、资源完整性、测试注册、Python AST、PowerShell 解析全部通过。
- 固定 APK runtime commit：`58db719671c15a126fde67733745e1a84ccee3a9`。
- 桌面 APK：`C:/Users/Administrator/Desktop/HardCore-20260810-foundation-audit-debug.apk`；`245,014,120` 字节；SHA-256 `E673181750303DD189F7ABFF32679B882EE46DDD0321159BDC3809F1EE978AA1`。
- Android 验证：`versionCode=64`、`versionName=1.18.1-spatial-projection`、`HardCore`、`com.personal.mafaoffline`、`arm64-v8a`、minSdk 24、targetSdk 36；APK v2/v3 签名、12 个编译脚本、运行时资源探针和 build-info commit 全部通过。

## Active Wizard Line Presentation Alignment

- `WIZARD-LINE-PRESENTATION-ALIGNMENT = DEVICE_ACCEPTANCE_PENDING`
- Professional implementation commit: `14bb52f5`（merged into integration as `348b6809`）
- Formal design: Hellfire / Laser use target-aligned continuous canonical geometry; Presentation consumes the same release snapshot and must not quantize Gameplay to character or source-art directions.
- Automated verification:
  - focused arbitrary-angle alignment: `PASS`（Hellfire 126 samples + Laser 126 samples）
  - `wizard_line_geometry_critical`: `PASS / 3_OF_3`
  - related caster visual tests: `PASS / 4_OF_4`
  - suite registration guard: `PASS`
- Single authorized default Critical run: every completed entry before the outer 900-second command cutoff passed, including `wizard_line_geometry_critical`; no final runner JSON / `TEST_SUMMARY` was produced, so this is `PARTIAL`, not a formal full-Critical PASS. Do not rerun automatically.
- Gameplay origin / axis / length / width, lock-on, target selection, damage and Geometry Debug Band were not modified.
- Final closure requires a newly exported Debug APK and device visual acceptance.

## Confirmed Production Blockers

`confirmed_production_blockers = 0`

## New Must-Fix

`0`

## Hellfire Damage Regression Fix

- `known_unverified_production_regressions = 0`
- `HELLFIRE_CANONICAL_TARGET_REGRESSION = FIX_IMPLEMENTED`
- User-visible symptom confirmed: Hellfire animation and geometry released, but no target received damage.
- Root cause: the canonical target selector interpreted production `maximum_targets = 0` as an empty target set before applying the explicit `target_limit_policy = all_intersecting_effect_cells` contract.
- Fix commit: `13821799fced2fee0d50c27d89bba3149464077f` (`fix(skills): restore hellfire line damage`).
- Automated verification:
  - production-effect regression reproduced before fix and passed after fix: `PASS / 1_OF_1`
  - wizard canonical/runtime/lock integration: `PASS / 3_OF_3`
  - `wizard_line_geometry_critical`: `PASS / 3_OF_3`
- `HELLFIRE_DAMAGE_DEVICE_ACCEPTANCE = PENDING`

## Closed Recent Bugs

- B030 = `CLOSED`（PassiveProcSkillEffect actor 平面）
- B038 = `CLOSED`（Skill Panel AssignmentHint 溢出）

## Test Infrastructure Debts

- B004 = `CONFIRMED_TEST_INFRA`
  - `production_touch_scroll_works=true`
  - `old_test_calls_disabled_path=true`
  - 旧测试调用了被 `STABLE_ID` 策略禁用的 `launcher._input` 路径。
- B037 = `CONFIRMED_TEST_INFRA`
  - `InventoryScroll` 存在于真实 HUD 树且触摸有效。
  - 旧测试只扫描 `MobileSafeRoot`，漏掉 HUD 根子节点。

## Runner Allowlist Gate Closure

- `RUNNER ALLOWLIST GATE = CLOSED`
- 关闭提交：`9a174d14015268e570bf687ddf3e14aad440f314`（`fix(test): harden runner allowlist contract`）
- public suites：23
- runner identity isolation：`PASS`
- `TestPaths`：`adhoc only`
- timeout hard range：`1..60`
- `monster_streaming_critical` direct suite remains available。
- 2026-09-21 RV14-04 (O07)：`monster_streaming_critical` 重新加入默认 critical suite（去重保留）；runner 对包含 streaming 成员的运行强制 `-TimeoutSeconds >= 30`，低于预算启动前直接拒绝。注册自检（`tools/tests/test_suite_registration.ps1`）同步断言包含与预算守卫。历史 HOLD 记录保留为档案，不再作为排除默认 suite 的依据。
- formal suite smoke：`player_visual_contract_critical = PASS / 1_OF_1`
- `confirmed_runner_blockers = 0`
- registration guard remaining weakness：`NON_BLOCKING_TEST_INFRA_DEBT`

## Monster Streaming Historical Evidence

- apply-order 历史记录：20-run evidence 17 PASS / 3 FAIL。
- 当前状态：
  - `HOLD`
  - `NOT_NEXT_GATE`
  - `NOT_ACTIVE_MUST_FIX`
  - `20_RUN_NOT_AUTHORIZED`
  - `PRODUCTION_CHANGE_NOT_AUTHORIZED`
- 该状态不是 `CLOSED`；它只暂停执行，不否认历史现象。

## Environment Noise

- Orc Tomb headless dummy renderer shutdown：20/20 standalone PASS；批跑偶发关闭期 RID 噪声。

## Next Verification

- `NEXT_VERIFICATION = FOUNDATION_APK_DEVICE_ACCEPTANCE`
- `STATUS = DESKTOP_APK_READY_FOR_MANUAL_ACCEPTANCE`
- 使用 2026-08-10 桌面 APK 复验战斗、存档、地图发布、装备性别门禁、商店出售、任务放弃、仓库排序，以及既有 Wizard Line / Hellfire 实机表现。

## Pending Freeze Quality Gates

1. `NEXT_FREEZE_QUALITY_GATE = WORLD_ACTOR_SPAWN_PERFORMANCE` — `NOT_STARTED`
2. Final G1 audit — `NOT_STARTED`
3. Android device acceptance — `NOT_STARTED`

用户当前已暂停全部 Freeze 工作；上述 verification 与 quality gates 均未开始。

## Do Not Work On

- 未制作地图内容（338 等）
- 未来 MSE 功能
- B004/B037 生产代码（两项均已确认是测试基础设施问题）
- GameRoot 拆分
- 坐标重新设计
- Snapshot 重新设计
