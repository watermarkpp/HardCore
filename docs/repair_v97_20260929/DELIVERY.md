# v97 交付：锻造保存与新物品图标

## APK

- 文件：`C:/Users/Administrator/Desktop/HardCore-v97-forge-icons-debug.apk`
- 大小：488711865 字节（约 488.7 MB / 466.1 MiB）
- SHA256：`02E3E86D90F2437C64F211A83E052578A728EEF53D4912C80FAE8867C5C90CDD`
- versionCode：97；versionName：`hardcore 1.0 正式版`
- 包名：`com.personal.mafaoffline`；名称：HardCore；架构：arm64-v8a
- 签名 SHA256：`C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC`，与 v96 相同，直接覆盖身份检查 PASS。
- 固定源码：`a945e921e849b4aa81439183f60cec95e63d725c`。后续文档提交不改变 APK 源码身份。
- 基线 v96：`b0119a18a346e7919d5b2d6657329b910b1746af`。v94 后 Sol 热补丁 `21b40ddae663997f8e9f267585988e6a7c63db6a` 在祖先链中。

## 修复与验证

- 锻造真实掉落装备的 JSON 数字校验修正。武器、衣服、头盔成功/失败后可后台保存、读回、取放及继续保存；费用、材料、强化概率与原有属性保持。
- 商店购买/出售卡片消费正式图标尺寸；圣物、徽章与碎片 UI 最大 32×32、地面最大 36×36，等比显示。18 种新物品和两种旧装备在实际面板/地面节点检查 PASS；7 种自定义图片的可见像素边界检查 PASS，未改原图。
- 17 个相关场景 PASS、零引擎错误，正式测试注册 PASS；固定源码的两个直接专项再次 PASS（`evidence/final_source_runner.json`）。未重复整套全量回归。
- 完整独立构建 PASS；包内两个修复脚本确认更新；其余 296 个编译脚本、9684 个数据与纹理条目同 v96 逐字节一致，ZIP CRC 与测试/工具排除检查 PASS。
- 桌面副本 SHA256 与构建产物相同。

## 现场与远端

- 构建目录：`C:/Users/Administrator/.codex/worktrees/apk-v97/HardCore`，从固定提交创建并保留；主目录没有使用构建缓存覆盖源码。
- `AGENTS.md` 和 `tests/cangyue_area_test.gd` 保持接管时哈希，旧未跟踪内容保留。
- 地图、技能素材、物品属性、人工数据、包名和主树版本配置零改动；没有新稳定 ID。
- 推送目标：`watermarkpp/HardCore` 的 `codex/integration`，普通快进推送，未强推。
- DEVICE TEST：`NOT_RUN`。电脑未识别到手机；本轮未安装、未读取或改写手机人物档。APK 已放桌面供用户覆盖安装检验。

证据：`evidence/matrix.json`、`evidence/final_source_runner.json`、`evidence/icon_pixel_footprints.json`、`evidence/apk_verification.json`、`evidence/v97_build_full.log`。
