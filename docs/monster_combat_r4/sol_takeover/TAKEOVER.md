# R4 主树接管（2026-09-27）

## 身份与保护

- 接管前 integration / origin integration：`f5d6308f53162509bffd30f6981987cbfe80fa68`。
- fetch 后审核分支：`d289f907c804e87080bd4a70cd3e16df51bdbc54`，merge-base 等于接管前主树。
- 主树原无独有提交；未提交的五项存档/掉落/特效节点修复已保存为 `0c10a07a81105f5ed470ef7379b3eadd46879221`，既有专项证据在 docs/performance_20260926。
- 接管前备份：`D:/HardCoreAudit/r4-takeover-20260927-123453/manifest.json`。229 个 dirty 文件（17,782,870 bytes）、13,611 个 tracked 保护文件哈希、4,152 个隔离本地 JSON 存档；未接触手机存档。
- 不覆盖的备份 refs：`refs/backup/r4-takeover-20260927-123453/integration`、`.../candidate`。
- 69 个未跟踪、自动生成的 UID 与候选路径冲突。原件逐项哈希验证后移入备份 `uid-collision-originals`，保留 files 副本与移送清单；集成采用审核分支正式 UID。
- 用户 AGENTS.md 改动不入库、不覆盖；人工地图、技能/装备素材与配置没有 merge 内容变化。候选的怪物策略及 catalog 变更是本次审查范围，不代表已接受其正确性。
- 无其他 Godot/构建进程发现；审核树 dirty=0。锻造树与其他临时工作未集成，所有工作树保留。

## 本地候选裁决

完整 R1—R4 分支通过 no-ff/no-commit 合并，无源码冲突。候选集成只保存待审源码，状态 **NOT_RUN（最终验收）**，不得称 R4 通过。

合并差异 check 为 FAIL：候选 11 个测试场景有 EOF 空行，归档的原始 Markdown 证据有既有尾部空格（含 Markdown 换行）。场景格式将在最小修改中修正；保留原始证据字节，不以清洗历史证据掩盖检查结果。

远端主树不推送；APK、安装、热补丁、版本变化、工作树删除均禁止。普通推送既有审核分支须先核对 fast-forward。本轮尚未推送。

## 执行方式

唯一主控亲自判断与施工，不使用工程子代理。用户追加允许 GLM 浏览器低推理重任务；已验证模型 glm-5-3-flash、仅可查看，当前只归集 R3 critical 失败日志。输出仅 CANDIDATE_EVIDENCE。

用户完整接管要求保存在本目录 TAKEOVER_BRIEF.md；下列台账覆盖剩余验收，不以历史报告 PASS 替代实际执行。
