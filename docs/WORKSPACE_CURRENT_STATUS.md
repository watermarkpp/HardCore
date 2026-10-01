# HardCore 分支与工作树现况

核验时间：2026-10-01 20:49（Asia/Shanghai）。这是本次现场快照；下次开工以实时 Git 和文件状态为准。

## 工程入口与协作方式

正式工程入口为 `C:/Users/Administrator/Documents/HardCore` 的 `codex/integration`。唯一主控按已授权任务范围串行处理各系统，GLM 的 Codex CLI 机械任务边界按根目录 `AGENTS.md` 第 4 节执行。

原按分支划分文件所有权的表不再作为当前施工流程：本次实时 Git 登记下列三个工作树。存在历史分支引用或磁盘目录，不代表其对应工作树仍登记、正在施工、已完成合并或可以删除。

## 已注册工作树

| 工作区 | 分支 | 核验 HEAD | 当前角色与现场 |
|---|---|---|---|
| `C:/Users/Administrator/Documents/HardCore` | `codex/integration` | `27bf669fdd5293f8657e28e1ecd7976c39e8d983` | 第一树，保留 v97 现场；已有规则、integration 文档、人工 cangyue 测试和多项 untracked 全部保留，未接入第二树或第三树源码 |
| `C:/Users/Administrator/Documents/HardCore-worktrees/glm53-r1-20260929` | `codex/glm53-r1-20260929` | `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` | 第二树，保留R3与反馈修复源码；75 R3和29反馈全部PASS。683项串行证据658 PASS /25既有FAIL，性能V4 FAIL。精确内容集合 `543e5eb23094f24c68f577e83121d52b18ca75e7b565264c540179e5461e0c95`，源码交接完成，发布验收FAIL |
| `C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore` | `codex/pluggable-framework-v2` | `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` | 第三树，原精确镜像完成：245文件复制，3298运行文件和2278地图编辑源逐字节一致。P0—P5实现及正式ID范围持续推进，类别范围49直接检查、21唯一专项/回归、27生成器检查PASS；P6及完整架构验收仍未完成，尚未接入主树 |

第二树的最终证据在 `outputs/r3_takeover/20260930/SECOND_TREE_FINAL_EVIDENCE.json`、`SECOND_TREE_FAILURE_CLASSIFICATION.json` 与 `COMPLETION_LEDGER.json`；25个正式FAIL及性能FAIL保留。完整683场景调用加唯一独立受阻夹具复验形成当前串行覆盖，生产字节和其他夹具完全不变。第三树镜像清单为 `outputs/framework_v2/baseline/MIRROR_MANIFEST.json`，后续框架改动使用独立证据。

v97 安装包为 `C:/Users/Administrator/Desktop/HardCore-v97-forge-icons-debug.apk`，488711865 字节，SHA256 `02E3E86D90F2437C64F211A83E052578A728EEF53D4912C80FAE8867C5C90CDD`。包的固定构建源为 `a945e921e849b4aa81439183f60cec95e63d725c`；不能把当前主树 HEAD 或任一 dirty 候选当成该 APK 的构建源。本轮未重新构建、安装或发布。

## 提交关系与远端

- 主树与镜像共同祖先为 `8181f197b09b0aafc8ed8de0c5604c5edacbed7f`。
- `git rev-list --left-right --count <主树HEAD>...<镜像HEAD>` 为 `1 34`：主树独有 1 个提交、镜像独有 34 个提交，两者分叉；镜像 HEAD 未成为主树祖先，不能宣称镜像成果已经合入。
- `origin/HEAD` 仍指向 `origin/main`；本地和远端 `main` 均为 `78a797973409c0ce47590b928f3d26ff067fe567`。
- `git rev-list --left-right --count main...codex/integration` 为 `0 140`：`main` 是主树祖先，落后主树 140 个提交。远端默认分支不能替代当前 `codex/integration` 工程基线。
- 第三树HEAD与第二树相同，已精确复制受测未提交文件。六个干净测试文件CRLF/LF差异已核实为仅换行并补齐受测字节；所有运行文件和地图编辑源一致。P0工具/测试及后续架构改动独立于该镜像基线，不能用同HEAD宣称当前所有字节始终相同。
- 远端身份属于 2026-09-30 的 `git ls-remote` 快照：当时远端 integration/GLM 分支与对应本地 HEAD 相同。本轮没有刷新远端身份，不将此历史结果作为当前远端证明。
- `codex/ui-art`、`codex/maps`、`codex/monsters`、`codex/equipment`、`codex/professions-skills` 的本地分支引用仍保留，但没有对应的已注册专业工作树。本次没有裁决这些引用的独有内容或删除资格。

## 目录与保护边界

`HardCore-worktrees` 下还存在未出现在本仓库注册清单中的历史、基线和包目录。本次仅核对一级目录名称，不将它们视为现行专业树，也不推断其 Git 类型、唯一资料、占用状态或删除资格。

本次已按用户授权创建第三工作树及 `codex/pluggable-framework-v2` 分支。三个工作区的 `.godot`、用户数据和 `outputs` 独立；第三树仅通过本地联接只读使用主树 Godot 工具及 `dev_art_sources`，不复制素材库、不改变共享源。本轮没有合并镜像、清理现场、修改 Git 路由、提交或推送。bootstrap 的历史路由与保护检查保留；第三树正式预检在受测字节和最新规则复制后执行。

## 下次开工核验

在实际目标工作区运行：

```powershell
git branch --show-current
git rev-parse HEAD
git status --short
git worktree list --porcelain
```

需要接入候选时，再核验 `git merge-base`、`git rev-list --left-right --count`、候选实际差异、受测 SHA 和相关回归。需要远端身份时使用 `git ls-remote`，不将旧 tracking ref 当成实时远端。

分支与工作树布局变化后更新本文件；临时路径、SHA、计数和任务状态留在现况文档，长期工程约束留在 `AGENTS.md`。
