# 01 — 项目目录结构总览

> 本文档列出 HardCore 仓库的顶层目录、职责归属及编辑策略。
> 所有路径相对于仓库根目录 `C:\Users\Administrator\Documents\HardCore\`。

---

## 目录清单

### `assets/art/`
| 字段 | 值 |
|------|-----|
| **路径** | `assets/art/` |
| **用途** | 游戏美术资源总目录（角色、装备、怪物、地图、NPC 等） |
| **归属** | 按子目录分属各专业工作树 |
| **编辑策略** | SOURCE AUTHORITY — 原始美术素材，由对应工作树维护 |
| **文件数** | ~13,401 |

子目录：
- `characters/` — 职业角色美术 → **codex/professions-skills**
- `items/` — 装备物品美术 → **codex/equipment**
- `monsters/` — 怪物美术 → **codex/monsters**
- `maps/` — 地图美术 → **codex/maps**
- `npcs/` — NPC 美术 → **codex/ui-art**
- `samples/` — 样本素材
- `generated/` — **GENERATED** — 生成器产出，勿手动编辑
- `presentation/` — **GENERATED** — 演示素材，勿手动编辑
- `raw_import/` — 只读原始导入素材，**DO NOT MANUALLY EDIT**

---

### `assets/data/`
| 字段 | 值 |
|------|-----|
| **路径** | `assets/data/` |
| **用途** | 游戏数据 JSON 文件（装备属性、怪物数据、技能数据、优先级策略等） |
| **归属** | 按文件内容分属各专业工作树或 integration |
| **编辑策略** | 混合 — 见下方标记文件表 |
| **文件数** | 233 |

#### 标记文件权限表

| 文件 | 分类 | 生成器/权威源 |
|------|------|--------------|
| `complete_monster_client_art_sources.json` | GENERATED | `tools/build_complete_monster_client_art.py` |
| `runtime/monster_animation_catalog.json` | GENERATED | `tools/build_monster_animation_catalog.py` |
| `runtime/monster_ground_contacts.json` | GENERATED | `tools/build_monster_ground_contacts.py` |
| `runtime/monster_ground_contact_calibrations.json` | GENERATED | `tools/build_monster_ground_contacts.py` |
| `runtime/monster_ground_alignment_manual_v1.json` | GENERATED | `tools/import_monster_ground_alignment_drafts.py` |
| `runtime/monster_overhead_anchors.json` | GENERATED | `tools/build_monster_overhead_anchors.py` |
| `runtime/canonical_monster_catalog.json` | GENERATED | `tools/build_canonical_monster_catalog.py` |
| `source_priority_policy.json` | HAND-AUTHORED authority | 唯一来源优先级总表 |
| `equipment_attribute_master.json` | HAND-AUTHORED authority | 装备属性唯一主源 |
| `vanilla_176/monsters.json` | SOURCE DATA | Excel 导入 |
| `vanilla_176/skills.json` | SOURCE DATA | 原始 1.76 数据 |

---

### `assets/ui/`
| 字段 | 值 |
|------|-----|
| **路径** | `assets/ui/` |
| **用途** | UI 纹理、图标等界面美术资源 |
| **归属** | **codex/ui-art** |
| **编辑策略** | SOURCE AUTHORITY |
| **文件数** | 205 |

---

### `assets/maps/`
| 字段 | 值 |
|------|-----|
| **路径** | `assets/maps/` |
| **用途** | 编译后的地图数据 |
| **归属** | **codex/maps** |
| **编辑策略** | GENERATED — 由地图工具链生成，勿手动编辑 |

---

### `assets/audio/`
| 字段 | 值 |
|------|-----|
| **路径** | `assets/audio/` |
| **用途** | 音频资源 |
| **归属** | **codex/integration** |
| **编辑策略** | SOURCE AUTHORITY |
| **文件数** | 6 |

---

### `assets/branding/`
| 字段 | 值 |
|------|-----|
| **路径** | `assets/branding/` |
| **用途** | 品牌资产（Logo、图标等） |
| **归属** | **codex/integration** |
| **编辑策略** | SOURCE AUTHORITY |
| **文件数** | 15 |

---

### `scripts/`
| 字段 | 值 |
|------|-----|
| **路径** | `scripts/` |
| **用途** | GDScript 游戏逻辑代码 |
| **归属** | 按子目录分属各专业工作树 |
| **编辑策略** | SOURCE AUTHORITY — 手写代码 |
| **文件数** | 366 |

子目录：
- `layers/runtime/` — 运行时服务层 → **codex/integration**
- `layers/rules/` — 规则层 → **codex/integration**
- `layers/presentation/` — 表现层 → **codex/integration**
- `map_assets/` — 地图资源脚本 → **codex/maps**
- `map_editor/` — 地图编辑器脚本 → **codex/maps**
- `skills/` — 技能相关脚本 → **codex/professions-skills**

---

### `scenes/`
| 字段 | 值 |
|------|-----|
| **路径** | `scenes/` |
| **用途** | Godot 场景文件（.tscn） |
| **归属** | **codex/integration** |
| **编辑策略** | SOURCE AUTHORITY |
| **文件数** | 6 |

---

### `tools/`
| 字段 | 值 |
|------|-----|
| **路径** | `tools/` |
| **用途** | 构建脚本、Python 工具、Godot 引擎二进制 |
| **归属** | 按工具功能分属各专业工作树或 integration |
| **编辑策略** | EDITOR TOOL — 工具链代码 |
| **文件数** | 51,618 |

关键生成器（产出 `assets/data/` 中的 GENERATED 文件）：
- `tools/build_complete_monster_client_art.py`
- `tools/build_monster_animation_catalog.py`
- `tools/build_monster_ground_contacts.py`
- `tools/import_monster_ground_alignment_drafts.py`
- `tools/build_monster_overhead_anchors.py`
- `tools/build_canonical_monster_catalog.py`

---

### `tests/`
| 字段 | 值 |
|------|-----|
| **路径** | `tests/` |
| **用途** | 测试场景和测试脚本 |
| **归属** | 按测试对象分属各专业工作树 |
| **编辑策略** | TEST ONLY |
| **文件数** | 1,927 |

---

### `outputs/`
| 字段 | 值 |
|------|-----|
| **路径** | `outputs/` |
| **用途** | 构建输出、测试日志等临时产物 |
| **归属** | 全局共享 |
| **编辑策略** | AUDIT OUTPUT — git-ignored，可安全清理 |
| **文件数** | 27,249 |

---

### `docs/`
| 字段 | 值 |
|------|-----|
| **路径** | `docs/` |
| **用途** | 项目文档 |
| **归属** | **codex/integration** |
| **编辑策略** | SOURCE AUTHORITY |
| **文件数** | 104 |

---

### `map_editor_workspace/`
| 字段 | 值 |
|------|-----|
| **路径** | `map_editor_workspace/` |
| **用途** | 地图编辑器工作区文件 |
| **归属** | **codex/maps** |
| **编辑策略** | EDITOR TOOL — 地图编辑器产出 |
| **文件数** | 731 |

---

### `import_server_data/`
| 字段 | 值 |
|------|-----|
| **路径** | `import_server_data/` |
| **用途** | 服务端数据导入 |
| **归属** | **codex/integration** |
| **编辑策略** | SOURCE DATA |
| **文件数** | 2 |

---

### `dev_art_sources/`
| 字段 | 值 |
|------|-----|
| **路径** | `dev_art_sources/` |
| **用途** | 只读提取的客户端原始美术素材 |
| **归属** | 全局只读参考 |
| **编辑策略** | **DO NOT MANUALLY EDIT** — git-ignored，只读源 |
| **文件数** | 38,947 |

---

### `artifacts/`
| 字段 | 值 |
|------|-----|
| **路径** | `artifacts/` |
| **用途** | 构建产物存档 |
| **归属** | **codex/integration** |
| **编辑策略** | AUDIT OUTPUT |
| **文件数** | 1,006 |

---

### `recovery/`
| 字段 | 值 |
|------|-----|
| **路径** | `recovery/` |
| **用途** | 救援快照 |
| **归属** | **codex/integration** |
| **编辑策略** | SOURCE AUTHORITY — 紧急恢复用 |
| **文件数** | 8 |

---

## 编辑策略速查

| 策略 | 含义 |
|------|------|
| SOURCE AUTHORITY | 手写源文件，由归属工作树维护 |
| GENERATED | 由工具/生成器产出，禁止手动编辑 |
| RUNTIME GENERATED | 运行时动态生成，禁止手动编辑 |
| AUDIT OUTPUT | 审计/构建输出，git-ignored，可清理 |
| TEST ONLY | 测试专用代码 |
| EDITOR TOOL | 编辑器工具链代码 |
| DO NOT MANUALLY EDIT | 绝对禁止手动修改 |
