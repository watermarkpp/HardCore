# HardCore 分支与工作树现况

核验时间：2026-10-01 20:49（Asia/Shanghai）。这是本次现场快照；下次开工以实时 Git 和文件状态为准。

## 工程入口与协作方式

正式工程入口为 `C:/Users/Administrator/Documents/HardCore` 的 `codex/integration`。唯一主控按已授权任务范围串行处理各系统，GLM 使用用户级 `glm_readonly` MCP（或同一安装的授权 --once 入口），只读机械任务边界按根目录 `AGENTS.md` 第 4 节执行；旧 Codex CLI GLM profile 不再使用。

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


## 2026-10-02 11:54 增量核验

以上 2026-10-01 记录保留为历史。当前仍登记三个工作树；主树 codex/integration HEAD 27bf669fdd5293f8657e28e1ecd7976c39e8d983，第二/第三树构建分支 HEAD 均为5d9ceb0121980ca9636d9d1cc2e19982949fbf63。第三树保留大量既有dirty，12项生命周期源码/测试增量采用独立临时index固定审查，未切换工作树、未覆盖真实index、未合入主树。

审查分支codex/framework-review-lifecycle-20261002固定4d1efdc45897ace1be64fe0050c977c47f703ad0已push并经ls-remote核对，已交原Pro对话。直接角色切换保护、完成队列容器回收、同帧效果消费及90状态/360tick有界组合，最终14原生场景293检查PASS。交付3472文件指纹847c42a6278f9241551378775697c528742539a9d56fc8f774995236224efe5c，受测全体3477文件指纹be3e6596fe28f73f6cec59123957494cc2749477c6620502d2db64c2170b5001；差5个当时未运行的迁移fixture已明确排除，本段后续另行完成默认root验证。详见docs/review/framework_lifecycle_20261002/README.md及施工范围账本。

完整容量仍FAIL；receipt安全退休与journal64协议、剩余定价名称身份、完整P6及R3性能、精确v97历史B故障、主树接入/APK/设备验收未完成。此处的工作树现况和审查提交不能替代这些门禁。


## 2026-10-02 审查引用核验

核验时间（UTC）：2026-10-02T05:07:28.766468+00:00。新增独立审查分支 codex/framework-review-audit-closure-20261002，远端已核对1687798348756846001eb6c27a14cf2f376f42cf，父4d1efdc45897ace1be64fe0050c977c47f703ad0。使用独立临时index固定受测内容，施工HEAD仍5d9ceb0121980ca9636d9d1cc2e19982949fbf63，原施工index保持。没有新增工作树、切换分支或集成主树。主树codex/integration仍27bf669fdd5293f8657e28e1ecd7976c39e8d983；第二树仍5d9ceb0121980ca9636d9d1cc2e19982949fbf63。

A—C本轮限定门禁补证及D非空范围声明见docs/review/framework_audit_closure_20261002/README.md。审查SHA已交原《游戏稳定性设计》；未另行联络dots。完整容量FAIL、receipt/journal协议、精确v97 B输入MISSING及主树/APK/设备验收继续开放。该记录不可替代下次现场核验。


## 2026-10-03 最终候选与双审计交接（UTC 2026-10-03T13:21:33.408675+00:00）

本记录实时核验三棵树。主树 codex/integration HEAD 27bf669fdd5293f8657e28e1ecd7976c39e8d983、第二树 codex/glm53-r1-20260929 HEAD 5d9ceb0121980ca9636d9d1cc2e19982949fbf63，HEAD/分支/119及249项dirty清单指纹与此前保护记录一致；未清理或改写现场。

第三树仍为 codex/pluggable-framework-v2、真实HEAD 5d9ceb0121980ca9636d9d1cc2e19982949fbf63，既有index保留。独立审查分支 codex/framework-layered-critical-20261003 已推送并核验远端固定 d70121c7183094a23992985e63ee796dd5c0f586，tree db24ae1978e5036ec12278bea127224d2ca5814a。该提交是受测内容快照，并非切换本树或声称干净checkout运行。

父阶段c2d3ac514e7d3f2015aff9bc19a5ef2c3aac3104按原内容a607400e保留239次成功/215唯一场景/4221检查；最终两文件空身份标记增量按内容b234e922保留27场景/876检查，旧139检查5FAIL与修复139PASS原始证据均保留，不互换受测指纹。报告见docs/review/framework_layered_critical_20261003与docs/review/framework_empty_category_20261003。

固定SHA已发原Pro及小可爱双审计。遵用户最新要求，本轮启用现有dots定时任务每10分钟直接拉取小可爱自身对话；实际读到本轮完整结果后暂停，下一次求助再启用。没有操作消息队列数据库或删除对话。

原v97第二角色B原始输入MISSING，Android/GPU/热机及物理掉电/外部有效旧primary整体替换NOT_RUN；PC证据和两受控强杀边界不替代这些范围。没有主树集成、APK发布、签名或设备验收。ABBA CPU门禁与帧间隔例外分别保留。

此段仅为本地追加现场记录，保存了完整追加前字节；未把本文件既有暂存历史内容混入审查提交。


## 2026-10-03 双审计实际读取与补证（UTC 2026-10-03T13:59:35.665118+00:00）

Pro与小可爱对d70121c7的完整报告均已从各自原对话实际读到，来源/消息身份/读取时间和完整正文已保存；支持空类别缺陷有界关闭。原小可爱拉取已暂停。本次将两个既有受控强杀producer各9个原文件及18-entry原始字节ZIP补入远端，补nonce/source/run/invocation/armed/controller/cold关联，两个producer保留FAIL/-1/非timeout；只改证据与CPU P95/P99/P50措辞。

同一审查分支现已非强推到b538ccdb4086f04e0a2c4b3703e75f44a6705086，parent d70121c7183094a23992985e63ee796dd5c0f586、tree 5f26e3442dde16b7d00b08ae9521c9638f7e241c。26路径均为docs证据，生产/测试/配置差异0，原生运行内容仍b234e922，未新增Godot执行；真实第三树HEAD/index和主树/第二树现场保持。

新窄补证已实际交给两位审计者；现有dots任务每10分钟只读取尚未完成的对应报告，读完一位即停止扫描该位，两份读完暂停。原B MISSING及Android/GPU/热机、物理掉电/外部旧primary、主树/APK边界保持。最新补证入口docs/review/framework_crash_archive_20261003/README.md。


## 2026-10-03 补证双审计读取完成（UTC 2026-10-03T14:17:00.348244+00:00）

固定b538ccdb4086f04e0a2c4b3703e75f44a6705086的Pro与小可爱完整结果均已实际读到并保存。两方支持原producer归档缺口与性能口径有界关闭；小可爱逐项复算18-member ZIP及身份链，Pro的读取/哈希核对范围单列，不相互扩大。

收口文档提交3a1b781b4b10ddb918f6abca955ae4c33985f2e0已推送，父b538；只增加两份实际报告、收口记录，澄清派生索引场景wrapper=-1与外层validation=1，五个docs路径，运行/测试差异0、没有新原生执行。真实第三树HEAD/index保留，b234的27/876与a607的239/4221证据仍分开。两方扫描均停止，定时任务PAUSED；只有下一次实际求助才重新启用。

原v97 B输入MISSING、设备/GPU/热机及物理掉电/内部完整矩阵/外部有效旧primary NOT_RUN，主树/APK边界保留。收口入口docs/review/framework_crash_archive_20261003/AUDIT_CLOSURE.md。


## 2026-10-05 B方案集中增量 fffadd21f

核验时间（UTC）：2026-10-05T03:12:58.048175+00:00。正式审查分支codex/framework-layered-critical-20261003已非强推到fffadd21f608d7cc759744fc53eb64e161b1e5ef，父5c34cd5acdd0e7d98ff46965479555a6a708c4c4。固定运行内容7d048ed9b2d83053b8c24b7ea7bff3d27f3e2b9805c1046d1eae853611794242、3855文件；同源46正常场景1767完整检查、两个owned失败注入38业务检查。两个官方runner FAIL保持，不存在成功producer。原始阶段及票据补充合计87尝试/15原FAIL，分指纹保留。固定代码、两套原生ZIP和票据补充ZIP见docs/review/framework_acceleration_20261005；不是干净checkout实跑声明。

主树codex/integration HEAD27bf669fdd5293f8657e28e1ecd7976c39e8d983/119dirty，第二树codex/glm53-r1-20260929 HEAD5d9ceb0121980ca9636d9d1cc2e19982949fbf63/249dirty及指纹与保护记录一致。第三树实际分支/HEAD仍codex/pluggable-framework-v2/5d9ceb，真实index SHA df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb保持，没有切换、主树集成或APK。第三树继承dirty与未提交现场保留，下一阶段只有诊断tests新增，不将其指纹当固定fffadd21源。

用户选择B并允许可用任意模型/强度的子代理，工具实际并发主控加3名辅助；生产接入、原生测试和裁决仍归主控。两项指定持续natural live外层90s/cold30s，原每轮35s deadline与完整玩法断言不变。已实际交小可爱及原Pro原对话集中独立只读复审resource-sustained-fffadd21-20261005；现有dots定时每10分钟仅拉取未完整读到结果的对象，两份读全后暂停。审计材料不自动批准主树或APK。

角色大厅46 ObjectDB实例退出警告、完整P6/R3和旧V4/DeviceLab FAIL、1us扩展服务规则产品选择、原v97B输入MISSING及Android/GPU/热机与物理掉电等范围仍单列。新虚拟安卓安装消息需核对准确线程/执行器及ABI；不以历史容器状态否定另一个执行器。暂无新APK，DEVICE TEST: NOT_RUN。
