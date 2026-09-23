# HardCore v93 冻结与清理记录

2026-09-23 将 APK 对应源码提交 `672811a135ddf0f4d8048a6a0eb11e92dee48dc4` 固定为已推送的 annotated tag `milestone-hardcore-1.0-v93`。后续文档提交不属于 APK 源码；复现本版须从该标签检出。用户已确认爬行怪黄圈的展示效果，并要求冻结版本、保留一切与版本有关的内容。

| 项目 | 已核对结果 |
| --- | --- |
| 桌面包 | `C:\Users\Administrator\Desktop\HardCore-v93-20260923-672811a1-debug.apk` |
| 大小 / SHA-256 | 480,233,417 bytes / `00354EA15A1FB51C4D63F74CEF52CBCE3ECA27040A593298D0785410F9638654` |
| 安装身份 | `com.personal.mafaoffline`，versionCode 93；签名证书 SHA-256 `C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC` |
| Android 构建树 | `C:\Users\Administrator\Documents\HardCore-android-staging\672811a135dd-20260923-131550-a28ef8bd`，保持原状 |
| 测试 | 本次清理未改游戏源码，未重新运行游戏测试。六项修复的针对性 8/8 与黄圈冻结专项 2/2 均 PASS；综合校准器玩家走路预览断言在旧基线和当前源码均 FAIL。见 `docs/repair_20260923_six/VERIFICATION.md`。DEVICE TEST: NOT_RUN。 |

清理前共 9 棵本地工作树。仅 `map-safety-r1-20260920` 与 `summon-cap-20260923` 两棵已合入主树、无需保留完整检出目录的临时树被移除；对应本地分支以非强制 `git branch -d` 删除。两树独立输出、报告及人工内容先逐文件校验并归档到项目内 `outputs/milestones/v93-worktree-archives/`：

| 归档 | 文件数 | ZIP SHA-256 |
| --- | ---: | --- |
| `map-safety-r1-20260920.zip` | 1,259 | `F49C469565645D4C92A3697C7B83E65B1EC5E75DBEECF0CAE224A1D1A0EA7C63` |
| `summon-cap-20260923.zip` | 140 | `FF2E788FC338BD2E29201596EC3074CA4419FCF82F869787868F2724CA314D50` |

两份逐文件 manifest 同目录保留。原工作树中的 `dev_art_sources`、`tools/godot-4.7` 是指向共享目录的联接；其联接柄移入归档目录，主树共享目标经移除后核对仍在。其他 6 棵非主树均因版本构建、旧版基线或复核用途保留：v93/v92 两棵 Android staging，以及 `msr1-baseline-39fe8685`、`rv15-joint-review`、`v92-m30-baseline-b961`、`HardCore_r14_base`。主树原有的 `AGENTS.md` 未提交修改与 23 个 `.gd.uid` 文件均未处理。

远端清理前有 227 个分支。仅删除了 54 个无开放 PR、提交已包含在上述里程碑源码内、且不带版本/发布/归档/基线标识的冗余分支指针。保留的 173 个分支及 SHA 逐项复核未变；包含独有提交的分支均保留。清理前后全部分支及删除清单见 [remote_cleanup.json](remote_cleanup.json)，原始本机计划和核验结果留在 `outputs/milestones/`。`main` 与 `codex/integration` 后续可追加本文档提交，里程碑标签始终指向原 APK 源码。
