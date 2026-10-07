# 固定 c046 累计回归期间恢复点

唯一主控，未用代理。当前main `codex/integration` HEAD `c0461f25ab2d02f2ea304dcf43be36cb868ab9d0`。

## 正在执行

- 活跃exec session **27184**：`tools/run_godot_tests.ps1 -Suite critical -TimeoutSeconds 30`，重R4按runner既有60s。
- 证据 `evidence/critical_owner_c046/identity.json`、`expected_paths.json`、`runner/`；期望542，started_at=2026-09-28T01:50:45+08:00。必须等正常最终结束和completion.json，逐项核对实际集合/退出/timeout/引擎错误。
- 此期间不改变HEAD或 scripts/tests/tools/assets/map_editor_workspace/project.godot/export_presets.cfg，不启动第二Godot进程。最新生产范围 diff quiet=0。
- 已发现实际FAIL：`map_release_identity_matrix_test` 1351 checks/1 failure，固定旧C5两单向违例集合要求现已修复的违规仍存在。详细 `evidence/critical_owner_c046/FAILURE_TRIAGE.md`。不能删FAIL或恢复缺陷。整套仍继续查其他失败。

## 新证据已完成，尚未提交

- `evidence/overhead_frame_pairs_aoe30`：固定c046 vs原1381，8/8 native collection PASS；P99三对约78–86→44–48ms；>50ms 10/10/11→4/3/3；中尾和引擎physics均值不利数据保留。
- `evidence/overhead_constructor_trace`：2原生诊断，真实工厂区域15怪批次58–64→29–33ms，夹具事件默认OFF。不是GPU/手机或正式到期respawn验收。
- `review_overhead_constructor_trace.py`、`verify_overhead_native_receipts.py`：已实际执行PASS，后者验证真实COMMITTED/事务成功/节点物化；CAND采样末pending7/7/8如实保留。
- `OVERHEAD_FACTORY_PERFORMANCE_REVIEW.md`：仅关闭此热点，不宣布整体R4通过；旧9e7性能FAIL原样保留，370 full24混合结果另册。
- `forge_intake_c046`：只读merge-tree对象2cd9c40169fcb41bd403f5a33103d411a9667c82，真实五内容冲突，未合并。180源身份/170非共享预览通过，10共享待语义整合。
- manifest初次比较Git字节与工作字节FAIL保存initial_fail；core.autocrlf=true，正确做实际工作SHA+官方Git clean blob+source/tip blob同时核验。60359已exit0；10724已exit1（原始误配表示的失败）。无其他工程/引擎进程。

## 下一项

1. 等27184结束，保存完整542结果并分类全部FAIL。先最窄修复，再相关回归。C5要求改为真正零违例，保留全部身份/发布隔离断言并补flag/role/reason负例。A/B作者portal_role仍是旧bidirectional，但正式发布准备链按portal network输出正确角色；先验证直接作者政策/正式准备的真实差异，确有问题才精确修作者元数据并正式单目标发布，绝不动坐标/几何/spawn或手改runtime。
2. 当前R4/F03/F05门禁闭合（包括最新源干净检出/保护/性能裁定）后，完整7提交forge DA41合入。读 `forge_intake_c046/REVIEW.md`，真实F03/workbench PROMOTE未ACK反例、严格新增实例ID/count、圣物缓存fallback/徽章候选均先RED再修，不改普通老档兼容。两门点旧预期不能用“基线已有”跳过。
3. forge最后源相关/正式注册/精确集合/full critical/clean/protection和有效输入性能，正常push核对远端，再保全独有内容/存档/素材/证据、逐树安全退休。
4. **最终停止在APK之前**；不构建/安装/热补丁/改版本。

用户AGENTS.md仍dirty且未stage，其他原untracked用户资料/UID/素材保持。最新地图只读审计实际再次PASS：67/132/117active/15arrival_only，64非目标registry条目未变；实际READY到达4次，不宣称117物理穿门或手机全图验收。接管备份在D:/HardCoreAudit/r4-takeover-20260927-123453。
