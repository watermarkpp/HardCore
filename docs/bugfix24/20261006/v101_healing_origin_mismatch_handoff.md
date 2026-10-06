# v101 Android 热补丁交接说明（GLM → GPT Pro）

日期：2026-10-06　基线：`be92f2775235f7e30daa346af04dd504d3037f00`（stage 固定检出）
分支：`codex/glm-thirdtree-continuation-20261006`
状态：**FAIL（1/3 项）**——创建角色仍失效，剩余一项 `feature_resource_primary_origin_mismatch:hc.resource.item.healing.inventory`

---

## 1. 本轮已修复并实证通过的两项

### 1.1 音效两项 mismatch：已修复，真机日志确认消失

**根因**：Godot 4.7 导出 APK 时只打包导入产物（`.sample`/`.ctex`）+ `.import` remap 元数据，**不打包 `.wav`/`.png` 源文件**。`feature_resource_registry.gd` 的音效校验用 `FileAccess.get_sha256(path)` 对源路径做字节校验，PC 工作树有源文件所以通过，真机包内没有源文件 → `get_sha256` 失败 → mismatch。

- `hc.resource.sound.fire_sword.attack`（res://assets/audio/sfx/client/137__M26-3.wav）
- `hc.resource.sound.ice_storm.effect`（res://assets/audio/sfx/client/10332__M33-3.wav）

**修复**（不弱化校验，把源文件补进包）：
1. 先试了 `export_presets.cfg` 的 `include_filter` 追加 3 个源文件 → **对导入资源的源文件不生效**（v97 包内同样只有 .import+.sample，实测确认），此路不通。
2. 改用**导出后处理**：`tools/android_seal/bridge/inject_sources_resign.ps1` 在导出后用 zip 注入 3 个源文件到 `assets/assets/...`，`zipalign` 后用引擎内置 debug keystore（`tools/godot-4.7/editor_data/keystores/debug.keystore`，证书 `c62d0f82…` 与 v97/v100 一致）重签。two-pass 的 seal 绑定注入后的 first APK，`verify_final_export` 全部 PASS。
3. **真机/模拟器日志实证：两个音效的 mismatch 消失**。

### 1.2 stage 版 catalog_data 未装入 APK：已修复

v100 的 two-pass 把重生成的 `internal_code_preparation_catalog_data.gd` 只生成到了 evidence 目录，没有装进 stage 的 `scripts/features/generated/`。APK 内还是旧 PC 版，`code_preparation_export_contract()` L530 的 `seal.source_bundle_json_sha256 != InternalCodeData.BUNDLE_JSON.sha256_text()` 必然拒绝。v101 起已装入（stage 副本 sha=b3cae7cb…与 seal 绑定一致）。

---

## 2. 未解决问题（请求 Pro 协助定位）

### 2.1 现象

v101（versionCode 101）在模拟器（emulator-5554）上 `Feature loadout rejected: ["feature_resource_primary_origin_mismatch:hc.resource.item.healing.inventory"]` 仍出现 3 次，创建角色依旧无法完成。PC headless 一切正常。

### 2.2 校验代码（scripts/features/compilation/feature_resource_registry.gd validate() 内）

```gdscript
if resource_type == "Texture2D" and (origin.size() != 3 or origin.get("lane") != "client_assets" \
    or not origin.get("entity_id") is String or origin.get("surface") not in ["inventoryIcon", "dropIcon"] \
    or GameData.get_entity_record(origin.get("entity_id", "")).is_empty() \
    or GameData.get_item_art_path(origin.get("entity_id", ""), origin.get("surface", "")) != path):
    errors.append("feature_resource_primary_origin_mismatch:" + id)
```

登记（assets/data/features/resource_registry.json）：
```json
{"resource_id": "hc.resource.item.healing.inventory", "type": "Texture2D",
 "path": "res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png",
 "origin": {"lane": "client_assets", "entity_id": "hc.item.910007", "surface": "inventoryIcon"}}
```

### 2.3 调用链

`player_state.gd:3737 recalculate_stats → _synchronize_feature_loadout → FeatureContributionProvider.collect → feature_resource_registry.validate`
触发点：PlayerState._ready（启动早期）×2 + `startup_loading.gd finish_startup_save_upgrade`（载入完成后）×1。

### 2.4 PC 实证（等 35 秒让 GameData 载入完成后）

```
PROBE resolve_kind=item legacy=910007.0 empty=false
PROBE entity_record_empty=false size=15
PROBE art_path=res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png
PROBE MATCH=true
```

### 2.5 真机/模拟器诊断数据（v101 + 探针，模拟器 adb）

| 探针 | 结果 |
|---|---|
| EntityRegistry.ensure_loaded | `ok=true`, `last_errors=[]` |
| `resolve("hc.item.910007")` | `resolve_empty=false resolve_kind=item` |
| `from_legacy("item", 910007)` | `=hc.item.910007`（成功） |
| registry 文档 | `doc_records=1243 rec910007=true` |
| `entity_registry_v1.json` 的 source_hashes 15/15 | stage 文件逐一实测匹配（LF 口径一致，不是行尾问题） |
| APK 内关键文件 | entity_registry_v1.json(395KB)/item_runtime_authority_v1.json(24KB 含 910007)/resource_registry.json/source_priority_policy.json/item_categories_v1.json(4KB) 全部在包内 |
| source_priority_policy 的 item_categories evidenceSha256 | stage 与 PC 文件哈希都等于 policy 记录值（C60D00DA…），两侧一致 |
| **时序分裂** | 前两次 rejected（PlayerState._ready）发生在"数据库载入完成"**之前**，此刻 `_catalog_by_item_id` **count=0**（整个索引未建）；第三次 rejected 发生在载入完成**之后** |
| 载入完成后 | `_catalog_by_item_id` **count=206**（索引正常）；910007 的查询**不再出现** `HC_DIAG2 item_id=910007` 探针（该探针在 `_catalog_by_item_id.has(item_id)` 为 false 时打印）→ 说明此时 910007 **在** by_id 索引中命中或被 `_valid_explicit_item_reference` 更早短路 |
| ItemCategories.attach_source_category 失败探针 | 0 次（`HC_DIAG3` 无输出）→ catalog 注册链本身无 category 失败 |

### 2.6 结论嫌疑（按证据强度排序）

1. **载入完成后的第三次 rejected**：`get_entity_record("hc.item.910007")` 非空（by_id 206 项含 910007，否则 DIAG2 会打印），但 `get_item_art_path("hc.item.910007","inventoryIcon")` 返回 ≠ 登记 path。即 **catalog 中 910007 record 的 `art.inventoryIcon.path` 值与 resource_registry 登记值在真机不相等（PC 相等）**。catalog record 来自 service bridge（`_catalog_by_service_index[service_for_item(...)]` + `itemId` bridge）或 `_catalog_by_item_id`，且 `_register_catalog_item` 是先到先得——需要确认真机命中的 record 到底是哪条、其 art 字段实际值。
2. **启动早期前两次 rejected**：GameData 的载入在 Android 上是长异步（实测约 28 秒），PlayerState._ready 时 catalog 未建 → 必然 rejected。PC 的 GameData 同步载入完成后再跑 PlayerState._ready 所以不出现。这两个 rejected 是否阻断创建角色未单独确认，但第三次（载入完成后）仍 rejected 表明还有独立问题。

### 2.7 最后一轮探针未取回

`HC_DIAG6`（打印 `get_item_record({"item_id":910007})` 的完整 `art` JSON 与 `get_item_art_path` 实际返回，插在 mismatch 分支内）的导出循环被中止，**未取得数据**。stage 目录探针仍然在位，可重新导出后一键取回：

```powershell
# stage 目录 = HardCore-android-staging\current_stage.txt 所指
# 探针位置：stage\scripts\features\compilation\feature_resource_registry.gd L52-60（HC_DIAG4/6）
# 复现：真引擎 --headless --export-debug "Android" <out> → inject_sources_resign.ps1 → adb install -r → logcat 抓 HC_DIAG
```

### 2.8 给 Pro 的具体问题

1. `GameData._item_record_for_read({"item_id":910007})` 在 Android 命中 `_catalog_by_item_id[910007]` 后返回的 record，其 `art.inventoryIcon.path` 为何会与 service_item_catalog.json 的 authoring 值不同？（service bridge `direct_record` 的 `identityBridge` 分支会 `duplicate(true)` 后改 `itemId`，不碰 art；还是 910007 命中了 `_catalog_by_item_id` 中先注册的另一条同 id record——`_register_catalog_item` 先到先得，equipment(175) 循环在 service 循环之前）
2. PlayerState._ready 两次 rejected（catalog 未建）在 Android 上是否属于可接受时序（后续 finish_startup_save_upgrade 会重跑 recalculate_stats），还是本身就是创建角色被阻断的原因之一？
3. 若确认是 catalog record art 差异，热补丁的正确层面是 service bridge/`_register_catalog_item` 的注册顺序，还是 `ItemCategories`/`_stable_item_id` 的判定？

---

## 3. 本轮产物与状态

| 项 | 状态 |
|---|---|
| v101 APK（含 3 源文件注入+重签+seal） | `C:\Users\Administrator\Desktop\HardCore-v101-thirdtree-debug.apk`，SHA256 `65042296603d24b4fa2c900c4da2c2c4771f67a6fb2e795dbea2b8cb02e497a4` |
| verify_final_export | PASS（receipt sha=eea4c4b8…） |
| verify_android_build | PASS（versionCode=101，签名同 v97 证书） |
| 音效 mismatch ×2 | **已修复**（真机日志确认） |
| healing inventory mismatch ×1 | **FAIL**（本文档主体） |
| DEVICE TEST | NOT_RUN（创建角色无法完成） |
| stage 诊断探针 | 仅存在于 stage 临时副本（current_stage.txt 所指目录），未污染主树；正式包前需还原 `feature_resource_registry.gd` 的 HC_DIAG 注入 |

## 4. 主树变更（本次 commit）

- `tools/build_android_isolated.ps1`：two-pass seal 接入（+95/-24）
- `tools/android_seal/bridge/build_android_seal.py`、`verify_final_export.py`、`android_two_pass_export_hook.ps1`（candidate 提升目录，bridge/ 布局）
- `tools/android_seal/export_identity_tool/collector.py`（COLLECTOR_SHA 自洽）
- `tools/android_seal/bridge/inject_sources_resign.ps1`（新增：导出后源文件注入+同证书重签）
- `docs/bugfix24/20261006/v101_healing_origin_mismatch_handoff.md`（本文档）
