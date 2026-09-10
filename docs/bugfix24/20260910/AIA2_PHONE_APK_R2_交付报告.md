# AIA2-PHONE-APK-R2 交付报告

日期：2026-09-10。执行令：`HardCore_AIA2_Phone_Only_Upgrade_DeepSeek_R2_20260910.md`（仅手机操作覆盖升级路线）。

## 1. 交付物（桌面目录）

`C:\Users\Administrator\Desktop\HardCore-AIA2-phone-update\`

| 文件 | 大小 | 说明 |
|---|---|---|
| `HardCore-20260910-aia2-phone-update-v73.apk` | 461,851,850 字节（440.5 MB） | **完整覆盖升级修复版**单 APK（资源全量，非差分包；不是 PCK 改名） |
| `INSTALL_手机直接升级.txt` | — | 全程仅手机操作的安装说明，无电脑连接步骤 |
| `checksums.sha256.txt` | — | 全部交付物 SHA-256 |
| `evidence.zip` | — | 独立证据包（构建/核验/回归原始日志），非安装依赖 |

APK SHA-256：`5E06E41FBF0121609B977D1A02F5C6B4856389416F4B4C9773AD7383DCDAEF56`（签名与核验完成后计算，之后未再写 ZIP 条目；桌面副本与构建副本逐位一致）。

## 2. 包身份（由实际 APK 读出，aapt/apksigner）

| 项 | 值 |
|---|---|
| 包名 | `com.personal.mafaoffline`（原包名，未加测试后缀） |
| 显示名 | HardCore |
| versionCode / versionName | **73** / `1.22.0-aia2-phone-update` |
| 签名证书 SHA-256 | `c62d0f8239b926f819038845c302143fd24dcfd75ed8d877ed846c430c6f3fcc`（= v71 = v72 = 台账；未换 debug.keystore、未轮换密钥） |
| ABI / SDK | arm64-v8a / minSdk 24, targetSdk 36（与旧包一致） |
| 构建类型 | 与既往分发一致的 gradle 导出链路（同一引擎 4.7.stable.official.5b4e0cb0f、同一模板与渲染器） |
| 包内 build_info | git_head=`690a0255…`，git_dirty=false，version_code=73 |

versionCode 依据：本地台账与实物旧包最高为 72（见下），73 为未使用的下一号；未盲目沿用文档，逐包重新读取。

## 3. 源码身份与施工范围

- 构建提交：`690a0255ee77babd85f3640a1121b055f4799d8d` = `561e4494`（R1 证据基线）+ 版本元数据提交（export_presets.cfg 73/1.22.0-aia2-phone-update、project.godot config/version）。
- 核心修复：`4f9faaf1`（AIA-2）；两核心脚本 Git blob 复核一致：game_root.gd=`2ac3fd4f…`，circular_touch_button.gd=`da6d8aae…`。
- 本轮对生产代码改动：**零**。仅版本元数据 + 测试 + 文档；无冷却/伤害/动作帧/怪物AI/地图/存档格式改动；无长按超时、机型特判、任意UP清全部。

## 4. 修复直接进入 APK 的证据链

1. **包内字节码合同断言（决定性）**：从签好的 v73 APK 解出 `assets/scripts/game_root.gdc`，在完整项目上下文加载并读常量表：
   `ATTACK_INPUT_TICKET_CONTRACT_ID = combat.input.ordinary_attack.live_owner_no_debt.v2`；
   五个归属方法（`_process_ordinary_attack_input`、`_reconcile_ordinary_attack_button_owners`、`_refresh_mobile_attack_held`、`_try_ordinary_attack_intent`、`_ordinary_attack_owner_matches`）全部存在 → `AIA2_PACKAGED_BYTECODE_SCENE_PASS`。
2. **负对照**：v72 实物包同一读取得到旧合同 `combat.input.attack_ticket.touch_lifecycle.v1`——方法有效且证明新旧字节码确实不同。
3. **字节级对比**：game_root.gdc、circular_touch_button.gdc 在 v73/v72 间为 CHANGED；enemy/player/hud/device_lab_patch_bootstrap.gdc 逐位相同（构建隔离与确定性的旁证，亦证明未夹带其他改动）。
4. **资源闭包**：`verify_r3_apk_resources.ps1` → `R3_APK_RESOURCE_CLOSURE_PASS scripts=25 svg_import_closures=4`；`verify_apk_runtime_resources.ps1`（hair 6 纹理、paper-doll base/hair、12 头贴、586 技能帧导入）全部 PASS。

## 5. 分项状态（PASS / FAIL / NOT_RUN）

| 项 | 状态 | 证据 |
|---|---|---|
| APK 构建（隔离流水线） | **PASS**（第二次在 ASCII 路径核验成功；首次因中文目录名导致 aapt 无法读包被误判失败，APK 本身完好，详见 evidence 内首次日志） | `evidence/build_log_first_attempt_cn_path.log`、`verify_android_build_v73.log` |
| 签名/包名/版本资格 | **PASS** | 证书三包同源；73>72；badging/横屏/resizeableActivity 全对 |
| 资源闭包 | **PASS** | 25 脚本 + 4 SVG；运行时资源探针全对 |
| AIA2 修复在包内正式脚本资源 | **PASS** | 包内字节码合同断言 + 字节级对比 |
| AIA2 软件回归（22/22） | **PASS** | 构建提交上全新复跑：19 个 README-7.7 受影响场景 + 3 个真实击杀松手场景（含"已开始的一刀经正式伤害管线击杀后松手，12.0 秒实测不再开新刀"；长按继续攻击由 harness 60s 三档帧率不截断证明，无人为超时） | 
| 旧热补丁拒载/退役回归 | **PASS** | `device_lab_patch_bootstrap_test` PASS；启动链按底包身份失配自动拒载并**定点退役** active.json 与对应 PCK（仅固定目录、不递归 user://、不要求用户手动删除），身份缺失/非法保守拒载 |
| 隔离输入 harness（31/31） | **PASS** | 60s 长按 30/60/120fps 节拍与 UP 停攻等 |
| 模拟器覆盖升级与存档读回 | **NOT_RUN** | 本机无任何 Android 模拟器（已检查 BlueStacks/Nox/MuMu/MEmu/Android SDK emulator） |
| 故障手机无电脑安装 | **NOT_RUN** | 无设备可连，包已按仅手机流程备好，等同学实测 |
| 故障手机空挥复测 / 正常对照手机回归 | **NOT_RUN** | 需真机；不得以软件回归冒充 |

## 6. 已核对旧包范围（离线实物核对，非文档抄录）

| 旧包（桌面实物） | 版本 | SHA-256 | 与台账 |
|---|---|---|---|
| HardCore-20260905-audit-milestone-debug.apk | v70 / 1.19.0-audit-milestone | 26584B87…21664 | 无台账冲突 |
| HardCore-20260906-gameplay-audio-debug.apk | v71 / 1.20.0-gameplay-audio | A7599225…8772F | 一致 |
| HardCore-20260909-r3-closure-debug.apk | v72 / 1.21.0-r3-closure | 5DA03DED…FF6A6 | 一致 |

三包均 `com.personal.mafaoffline` / arm64-v8a / targetSdk 36，v73 满足全部的直接覆盖升级资格。台账中不存在 >72 的已分发版本。

## 7. 回退说明

本轮未制作回退 APK：无已验证的一键回退包；安装异常时保留应用与存档，后续以更高 versionCode 的修复包恢复；不建议清数据/卸载。

## 8. 风险与未决

- 模拟器与真机覆盖升级、旧存档读回、故障手机空挥是否消失：**均未验证**，需同学按 INSTALL 安装后反馈。
- 首次构建核验因交付目录含中文导致本地 aapt 误读（手机安装不受影响）；已换 ASCII 路径完成全部核验并交付。
- 保留的隔离构建现场（诊断用）：`HardCore-android-staging\690a0255ee77-20260910-112356-6e18aaae`，待确认后可清理。

## 9. 结论

这是手机直接覆盖升级的完整 APK，安装无需电脑连接，原游戏不需卸载；修复效果以手机安装后的回归结果为准。
