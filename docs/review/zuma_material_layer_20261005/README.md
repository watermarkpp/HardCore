# 祖玛两图低层地毯被墙体补画提升

核验日期：2026-10-05。施工区为第三工作树，HEAD 为
`5d9ceb0121980ca9636d9d1cc2e19982949fbf63` 加现有未提交源码；不能把该 HEAD 当成受测干净提交。

本项源码结果：PASS。Android/GPU 画面和 APK：NOT_RUN。整个架构升级不以本项结案。

## 根因和边界

正式地图为 `mengzhong_zuma_pavilion`（913105，祖玛阁）和
`mengzhong_zuma_leader_home`（913106，祖玛教主之家）。两个发布文件与作者文件中的地毯
都已经是 `occlusion=false`、`material_layer_order=-1/-2`。作者布局没有丢失。

编辑器的素材排序检查作者层级；运行时静态装饰物向原子墙体恢复像素的路径，
却只比较大物件远角的 Y 与墙体基线，未检查作者层级。候选选择和最终像素所有者判断
均存在这个缺口。原静态地毯依然正确留在 WorldBackground 下，但其部分像素被额外复制到
与人物同一 Y 排序域的墙体 wrapper，造成地毯覆盖墙体及墙后的角色。

真实地图原生反例中，祖玛阁全部 8 个地毯实例、教主之家全部 5 个地毯实例均成为错误
wall bridge 的来源。最终源码两种加载方式均没有提升这 13 个实例。

## 最小改动

- `scripts/map_editor/map_editor_runtime_visual_geometry_service.gd`：低于墙体作者层级的
  静态装饰物不能进入墙体补画；同层及更高层仍保留既有几何遮挡切线。
- `scripts/world_background.gd`：在元数据阶段缓存素材层级，最终像素所有者使用同一
  层级与深度判定，防止另一面低层墙入选后向更高层的实际不透明墙错误补画。
  不在逐像素路径重复计算坐标变换。
- 新增两图普通/分步构建反例，以及多层墙的像素所有者反例。
- 新增三个有界回归入口，原样复用已有装饰叠加、真实 orc 地图像素哈希和六种墙型
  穿越断言。全发布场景随后按当前作者数据及低层不提升合同补齐门禁，详见下文。
- `scripts/monster_overhead.gd`：将 RankMarker 的局部 `z_index` 从 1 调整为 0，
  保持怪物与其头顶子项的整体 Z 平面；贴图、位置、评级、同级顺序不变。

曾测试过让较高素材层级无条件覆盖墙的较宽候选。它改变了原多装饰物夹具哈希，
该次结果保留 FAIL，未采用该行为。最终只增加低层拒绝约束；原夹具哈希
`31f620f617f5c3eb6cc8fa4f64c796fc1c48f12ff7cc1a54cb77823e4aeef03a`
和真实 orc F1 哈希
`bf43daed182b9ca2b630560af5cb349c8ace30beee5aabd2e4d0e09fa3355685`
均保持原值并通过原生检查。

## 同内容证据

最终内容指纹：
`2763725adc1c1b9926f8f6a160ef7b10a507e6523a59707f4dccdefd3fc6d229`。
引擎：`4.7.stable.official.5b4e0cb0f`；console SHA256：
`d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。

证据在 `outputs/framework_v2/zuma_material_layer_20261005/`：

- `BEFORE.json`：原始源码、两图作者/地面/发布数据、目录与主目录表指纹。
- `OWNED_PRODUCTION_DIFF.patch`：相对此项动工前的精确增量。
- `VERIFIED_ASSOCIATION.json`：完整 receipt 与原生退出、run/invocation/source 关联。
- `FINAL_ASSOCIATION.json`：最终 19 个原生场景的同内容关联，5 份完整 receipt 共 6833 检查，
  以及 40 文件保护和真实 index 不变核验；前一个关联文件保留为阶段证据。
- `EXACT_FINAL_RED_SOURCE.json`：仅恢复自有两处增量重跑反例、随后精确恢复最终字节的记录。

原始运行目录均在 `outputs/r3_takeover/20260930/validation/`：

| 阶段 | 目录 | 结果 |
| --- | --- | --- |
| 两图真实反例 | `periodic_dispatch_zuma_layer_clean_RED_20261005_1904_175729_877428` | 2 FAIL；祖玛阁 2209/2753 失败，教主之家 463/659 失败；均无原生脚本错误或超时 |
| 最终收紧规则反例 | `periodic_dispatch_wall_material_narrow_RED_20261005_2005_181351_034877` | 层级/像素所有者 FAIL；原装饰物夹具 PASS |
| 阶段普通/分步加载及像素回归 | `periodic_dispatch_wall_material_preserved_20261005_2000_181128_397818` | 8 PASS；5 份完整 framework receipt 共 6833 检查，另 3 个原有像素/穿越断言入口 PASS |
| 阶段相关回归 | `periodic_dispatch_wall_material_final_related_20261005_2010_181543_819519` | 5 PASS；素材层级、发布遮挡合同、发布深度、真实人物装备墙体整合、旧 profile 遮挡 |
| 最终全发布真实像素与穿越 | `periodic_dispatch_map_layer_full_pixels_20261005_2050_183216_927446` | 1 PASS，60 秒门限；67 图、7281 个保留装饰物对、0 反转，原装饰及 orc 像素哈希保持 |
| 最终完整相关回归 | `periodic_dispatch_map_layers_complete_final_20261005_2100_183438_045839` | 18 PASS，30 秒门限；5 份完整 framework receipt 共 6833 检查，另 13 个原生场景 PASS |

最后两组使用同一最终指纹，原生退出均为 0，无超时、stdout/stderr/engine 错误。
前两组 PASS 的 `c3f34bb51b645edb1712bb201cb479871fbc18be2e7f58a1cfe1eb120aa99d5e`
仅作为阶段成果保留，未合并成最终指纹结果。
6833 是逐实例/逐墙关系及结构检查数量，不是 6833 个独立玩法场景。
测试使用正式发布目录加载、真实纹理及实际补画图像；人物穿越部分含受控节点结构检查，
不声称 OS/UI 或 Android/GPU 画面端到端实测。

## 原有失败的分类与闭合

另 4 个相关旧场景在修复前原字节和候选源码上有相同失败。前原字节复核目录为
`periodic_dispatch_zuma_existing_baseline_20261005_1940_180537_849335`。
原始 FAIL 均保留，后续按证据修复或更新已过时的具体合同预期：

- `map_runtime_wall_occlusion_contract_test`：L42，旧断言未去掉作者明确保存的 visual offset。
  改为核验 cell center 加该 offset，并在逆变换前去掉 offset；正式几何实现未变。
- `monster_wall_occlusion_contract_test`：L73，怪物子项偏离整体 Z 平面。
  对应上述 RankMarker 修复，怪物墙体、W6 展示与种类锚点三项均在最终源码通过。
- `mse_small_prop_occlusion_authority_test`：当前作者与运行数据 12 图 114 实例完全对应，
  工作区 22 文档 212 实例；旧门禁基于较早数量和水井锚点。按当前人工数据更新精确
  数量及锚点，保留身份、几何、遮挡、未知类型拒绝门禁；没有覆盖人工文件。
  同时修正 PASS 文本的格式运算优先级；曾出现 wrapper 标签通过但原生报错的运行未采用。
- `wall_atomic_foreground_occlusion_runtime_test`：L233，当前 67 图保留装饰物对数为 7281，
  旧门禁要求 7178；修复前独立实测就是 7281 且反转为 0。按当前作者数量更新门禁，
  对原来要求低层地毯进入墙体的三个已登记代表实例改为明确拒绝提升并要求墙体补画
  像素数为 0，保留真实 PNG 合成与顺序敏感检查；最终全场景独立通过。

以上四项均已在最终同内容回归通过。本报告没有把过时 fixture 预期宣判为自然 UI 故障，
也没有用新增有界入口代替全发布场景。

## 现场保护

40 个受保护数据/文件哈希完全不变。两图人工布局、素材、地面和发布文件没有重新生成。
主树和第二树没有施工。真实用户存档没有读取或修改。
第三树真实 Git index 保持
`df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb`；
测试新场景只使用已有临时 runner index 与隔离 APPDATA。
全部原始 FAIL 和各阶段证据保留。尚未新增固定审计提交或构建 APK。
