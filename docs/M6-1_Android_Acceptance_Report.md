# M6-1 Android构建与模拟验收报告

日期：2026-07-01

## 结论

- Android arm64调试APK已成功导出、对齐和签名。
- Sensor Landscape、可调整窗口、沉浸模式、16:9/20:9及挖孔安全区模拟验收通过。
- 摇杆、攻击、交互、换敌、解锁和4个技能槽共10个主要触控目标的尺寸与信号接线通过。
- 应用暂停、失焦和关闭通知会触发存档提交。
- 当前ADB无连接设备，因此真机帧率、内存、发热、加载和触控手感不计为已验收。

## APK信息

- 文件：`C:\Users\Administrator\Documents\Codex\2026-06-28\xian\outputs\legend176\MafaOffline_M6_1_debug.apk`
- 大小：34,975,302字节
- SHA-256：`7D6D8D19B5D48C8D8A3BCD6FCFC0B42EF6392BCEE9DDDD294819D355A37410D0`
- 包名：`com.personal.mafaoffline`
- 版本：`22 / 1.12-m6.1`
- 最低/目标API：24 / 36
- 架构：`arm64-v8a`
- 签名：APK Signature Scheme v2、v3通过
- 方向：Android Manifest `0xb`，横屏用户旋转模式

## 自动验收

- `ANDROID_LAYOUT_PASS`
- `VERTICAL_SLICE_LOOP_PASS`
- `ORC_TOMB_ENVIRONMENT_PASS`
- `BICH_ENVIRONMENT_PASS`
- `MOBILE_TARGETING_PASS`
- `SKELETON_SPIRIT_BOSS_PASS`
- `ITEM_CATALOG_PASS`
- `PROGRESSION_PASS`
- `SMOKE_TEST_PASS`
- `MAP_RUNTIME_PASS`

## 桌面兼容渲染参考

- GPU：AMD Radeon RX 6750 GRE
- 采样帧率：120 FPS
- 节点：192
- 静态内存：73.8MB
- 绘制调用：99

以上数据仅作为Android真机对照，不代表手机结果。

## M6-2真机步骤

1. 连接arm64 Android手机并启用USB调试。
2. 使用项目内ADB执行`adb install -r <APK>`。
3. 分别运行比奇连续刷怪与兽人古墓二层Boss房各10分钟。
4. 记录FPS、PSS内存、加载时间、电池温度、触控误操作和后台恢复。
