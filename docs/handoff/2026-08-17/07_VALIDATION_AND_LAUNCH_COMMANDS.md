# 验证与启动命令手册

> 生成日期: 2026-08-17

---

## Godot 环境

| 项目 | 值 |
|------|-----|
| **版本** | 4.7 stable |
| **GUI 可执行文件** | `tools\godot-4.7\Godot_v4.7-stable_win64.exe` |
| **Console 可执行文件** | `tools\godot-4.7\Godot_v4.7-stable_win64_console.exe` |

---

## 启动命令

### 启动主项目 (integration)

```
Godot_v4.7-stable_win64.exe --path "C:\Users\Administrator\Documents\HardCore"
```

### 启动地图编辑器

```
Godot_v4.7-stable_win64.exe --path "C:\Users\Administrator\Documents\HardCore-worktrees\maps" "res://tools/map_editor/map_editor_app.tscn"
```

### 启动 Visual Acceptance Lab（完整模式）

```
Godot_v4.7-stable_win64.exe --path "C:\Users\Administrator\Documents\HardCore-worktrees\monsters" "res://tools/visual_acceptance_lab/visual_acceptance_lab.tscn"
```

### 启动 Visual Acceptance Lab（怪物 ground review 模式）

```
Godot_v4.7-stable_win64.exe --path "C:\Users\Administrator\Documents\HardCore-worktrees\monsters" "res://tools/visual_acceptance_lab/visual_acceptance_lab.tscn" --monster-ground-review
```

---

## 测试命令

### 运行全量测试

```
Godot_v4.7-stable_win64_console.exe --path "C:\Users\Administrator\Documents\HardCore" --headless -s tests/run_all_tests.gd
```

或使用辅助脚本（推荐）：

```
powershell -File tools\run_godot_tests.ps1
```

---

## 数据构建命令

### 构建 canonical monster catalog

```
python tools\build_canonical_monster_catalog.py
```

### 构建 complete monster client art

```
python tools\build_complete_monster_client_art.py
```

### 构建 monster animation catalog

```
python tools\build_monster_animation_catalog.py
```

### 构建 monster ground contacts

```
python tools\build_monster_ground_contacts.py
```

### 构建 monster overhead anchors

```
python tools\build_monster_overhead_anchors.py
```

---

## 注意事项

- 所有 Godot 命令使用 console 版本运行测试，避免 GUI 弹出
- 工作树路径使用 `HardCore-worktrees\<branch>` 格式
- 数据构建脚本均为 Python，需确保 Python 环境可用
- 测试运行使用 headless 模式，不依赖图形界面
