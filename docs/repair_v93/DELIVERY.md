# 2026-09-23 公共 CPU 优化源码交付

生产源码与全部对照证据提交：`6bfa4235ff0fce04689dec417e3e80c24b39fc57`。
父基线：`3eb1cb8f4a80ba24d43cb0f07102b1f79763576d`（v92 后续交付记录）。
包含本文件的后续提交只追加交付说明和固定提交复验结果，生产代码/测试不变。

本轮结果与边界：

- 公共近战/多边形查询优化 PASS；全部 67 发布地图 53,400 次差分 PASS。
- 42 次本地真实场景 CPU 对照 PASS；30 怪平均 CPU 降低约 18%～20%，P95 改善较小，不能替代手机流畅度和温控验收。
- 收尾相关回归 55 次执行、53 个唯一场景 PASS；另外在上述固定提交上运行两个直接门禁，2/2 PASS、零引擎日志错误。结果见 `evidence/tests/runner_results_adhoc_20260923_102017_456_14172.json`，该文件记录准确 `git_head`。
- 18 种怪物动画/贴图只读审查 PASS；遵照用户最新决定，贴图、锚点、动画和 streaming 源码保持不动。
- 本轮无新增稳定玩法 ID，无未完成的跨系统接入。发布内容是源码及审查证据。
- APK BUILD: NOT_RUN；DEVICE TEST: NOT_RUN；全仓 critical: NOT_RUN。用户要求先推送，后续调整完成再统一打包。没有版本号变更或新 APK。

集成采用 `codex/integration` → `main` 的快进方式，两分支同步到同一个交付提交，再原子推送 origin。无需制造额外 merge commit，也不覆盖用户开工前的 AGENTS.md 修改和 23 个未跟踪 uid。源码、测试、工具及证据全部在本轮提交中；这些既有工作区内容仍留在本地。

可以用以下命令核对交付身份和生产树不变性：

```powershell
git log -1 --format=%H -- docs/repair_v93/DELIVERY.md
git rev-parse codex/integration main
git ls-remote origin refs/heads/codex/integration refs/heads/main
git diff 6bfa4235ff0fce04689dec417e3e80c24b39fc57 HEAD -- scripts tests tools assets map_editor_workspace project.godot export_presets.cfg
```

远端两行 SHA 应相同；最后一个命令应无差异。完整实现、测试命令、性能表、被拒绝的早期样本说明及证据入口见 `CPU_CROWD_REPAIR.md`。`evidence/verification_manifest.json` 对原始 52 个证据文件逐个绑定 SHA-256，`.gitattributes` 保留这些原始字节，避免 Git 换行转换破坏复核。
