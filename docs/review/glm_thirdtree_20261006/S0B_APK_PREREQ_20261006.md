# S0-B APK 前置核对（只读盘点，2026-10-06）

- 方法：只读盘点（子代理）+ 主会话对关键项复算核实（aapt badging / apksigner / Get-FileHash）。
- 未安装、未复制、未修改任何文件；未输出任何密码/私钥。
- 结论速览：Android 构建工具链 **HAVE**；**versionCode 必须取 ≥98**（旧包实测最高 97）；
  签名走既有 debug.keystore 与 v97 同体系（覆盖安装兼容）。

## 1. 工具链清单（均实测路径与版本）

| 项 | 状态 | 位置/版本 |
|---|---|---|
| JDK 17 | HAVE | `C:\Users\Administrator\Documents\HardCore\tools\android-build\jdk\jdk-17.0.20+8`（Microsoft OpenJDK 17.0.20+8 LTS；仅不在系统 PATH，Godot 编辑器设置 export/android/java_sdk_path 已指向；命令行手动 gradle 需临时设 JAVA_HOME） |
| Android SDK | HAVE | `C:\Users\Administrator\Documents\HardCore\tools\android-build\sdk`（ANDROID_HOME 未设，编辑器设置已指向；第三树无本地 tools\android-build，依赖第一树路径不动） |
| build-tools | HAVE | 35.0.1、36.1.0（aapt/aapt2/apksigner 0.9/d8/zipalign 齐全） |
| platform | HAVE | android-36（历史产物 min24/target36） |
| platform-tools/adb | HAVE | 37.0.0（adb 1.0.41） |
| cmdline-tools | HAVE | 22.0（sdkmanager/apkanalyzer 在 latest/bin；sdkmanager 弃用警告不影响构建） |
| NDK | **MISSING（不阻断）** | 标准 Godot gradle_build 导出不依赖 NDK（native 库来自模板 APK） |
| Gradle | HAVE | 无独立安装属正常：模板 wrapper gradle-8.11.1，`~\.gradle\wrapper\dists` 已有同版本缓存 |
| 导出模板 | HAVE | 4.7.stable 全套（android_debug.apk 127,127,537B SHA256 602D5FDF…、android_release.apk 104,689,925B SHA256 6D0BCB4A…、android_source.zip）在第一树与第三树 `tools\godot-4.7\editor_data\export_templates\4.7.stable\`；`%APPDATA%\Godot\export_templates` 为空属自包含模式正常现象 |
| 编辑器 | HAVE | 4.7.stable.official.5b4e0cb0f，GUI+console 双形态（两树都有；console 形态含导出能力） |
| debug 签名材料 | HAVE | debug.keystore 三处同哈希 `E8ED923030B531D7D2694C393FBEBD928EB7550A486E40940FA6AEB68E85D89C`（2714B），编辑器设置指向有效，密码在编辑器设置内（不输出） |
| release 签名材料 | **MISSING** | 无任何 release keystore 配置；交付 release 正式包前需用户提供；debug 测试包不阻断 |

## 2. 旧包实测（决定 versionCode 下限）

- v97 APK：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-v97-forge-icons-debug.apk`
  - 大小 488,711,865 B；SHA256 `02E3E86D90F2437C64F211A83E052578A728EEF53D4912C80FAE8867C5C90CDD`
  - 主会话复算核实：`package: name='com.personal.mafaoffline' versionCode='97' versionName='hardcore 1.0 正式版'`；sdkVersion 24；targetSdkVersion 36；native-code arm64-v8a
  - 签名（主会话复算核实）：Signer #1 CN=Godot, OU=Godot Engine, O=Stichting Godot, C=NL；证书 SHA-256 `c62d0f8239b926f819038845c302143fd24dcfd75ed8d877ed846c430c6f3fcc`
- versionCode 实测全表（全部 com.personal.mafaoffline/min24/target36/arm64-v8a）：
  **97（v97，最高）**、96、95、93、91、87、86、83、**82（20260915-aoe-fix 两个包占用）**、74×2、73×2、71、70、69×9、68×2、66、64。
- 决策依据：**新包 versionCode ≥ 98**（97 已被 v97 实测占用；82 已被两个旧包占用；preset 当前 82 不得冒充升级）。

## 3. 第三树 export_presets.cfg 现状（S6 前必须处理的差异）

- 唯一 preset：name="Android"；`package/unique_name="com.personal.mafaoffline"`；package/name="HardCore"；signed=true
- **version/code=82 → S6 构建时改为 ≥98 并同步 version/name**（保留品牌与既有命名口径）
- architectures：arm64-v8a=true（其余 false）；gradle_build=true、export_format=0（APK）
- min/target sdk 未设（导出器注入，历史口径 24/36）
- preset 无 keystore 字段 → 走编辑器设置 debug.keystore（与 v97 同 keystore → 签名兼容，覆盖安装不卸载）
- export_path="outputs/hardcore/HardCore.apk" → S6 改为版本化输出文件名，不覆盖唯一旧 APK

## 4. S6 前置结论

- 构建/签名/校验三段所需工具全部就位（JDK/SDK/build-tools/apksigner/aapt/gradle wrapper/模板/编辑器）。
- debug 测试 APK：**可交付路径已通**（S1-S5 完成后）。
- release 正式包：BLOCKED 于缺 release keystore（用户材料，S6 前报告即可，不阻塞 debug 交付）。
- 设备安装/覆盖：S7，需用户授权；本盘点只确认签名兼容前提成立。
