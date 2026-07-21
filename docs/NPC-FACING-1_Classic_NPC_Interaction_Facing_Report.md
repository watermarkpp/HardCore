# NPC-FACING-1：经典 NPC 交互转向施工报告

日期：2026-07-15

## 结论

第一阶段已完成：NPC 出生时统一朝向当前地图中心点；玩家触发交互时，NPC 立即转向玩家，然后继续执行商店、仓库、训练、任务等既有服务。运行外观不再使用程序占位人形，而是直接取自主客户端 `Npc.wil`。

## 资料依据与边界

- 客户端主资料：`dev_art_sources/reference/mir2_client_raw/Data/npc.wil` 与 `npc.WIX`。
- 客户端规则主资料：`dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas`。
- 原客户端 `TNpcActor` 使用 `m_btDir mod 3`，所以旧游戏运行时只主动使用三组方向。
- 对主客户端 `Npc.wil` 的逐帧核查证明，外观 0—22 每套实际保存六组真实前后视角，每组四帧；本项目启用全部六组原始视角，不生成、不镜像像素。
- 项目逻辑方向顺序固定为 `S、SW、W、NW、N、NE、E、SE`，原图组六向映射为 `1、0、0、5、4、3、2、2`。正东、正西复用最近的原始斜侧视角。
- 主服务端 `server.crystal.cjlaaa/Server.MirDB` 的 NPC `Image` 字段可由已授权的 Crystal 解析规则读取；完整 NPC 表解析不属于本阶段完成项。当前运行结构已经接受显式 `appearance`，未提供时才使用稳定的服务类型外观兜底。

## 实施内容

- 新增 `tools/build_classic_npc_assets.py`，从主客户端 WIL 可重复生成 23 套、八逻辑方向、每方向四帧的待机图集，并记录源索引、偏移、尺寸、锚点和 SHA-256。
- 新增 `scripts/npc_visual.gd`，按 NPC `appearance`、当前 `facing` 和统一脚底锚点加载运行图集。
- 重构 `scripts/npc_actor.gd`，新增 `facing`、`default_facing`、`map_center`、`appearance`；出生计算朝中心方向，交互先转向玩家。
- `scripts/game_root.gd` 统一计算当前地图中心并传入 NPC；服务端或地图数据中的显式外观编号优先。
- `scripts/layers/runtime/map_editor_runtime_bridge.gd` 透传编辑器 NPC 的 `appearance`，并输出设计地图中心。
- 新增 `tests/npc_facing_interaction_test.gd/.tscn`，覆盖主资料清单、地图中心默认朝向、交互转向、服务入口延续和视觉方向行同步。

## 产物

- `assets/data/classic_npc_art_sources.json`
- `assets/art/npcs/classic/appearance_000_idle.png` 至 `appearance_022_idle.png`
- `outputs/visual_acceptance/classic_npc_eight_direction_acceptance.png`
- `outputs/visual_acceptance/npc_facing_runtime_20260715.png`

## 验证

- 专项测试：1/1 通过。
- 比奇回归：24/24 通过。
- 完整关键回归：51/51 通过。
- 非 headless OpenGL 真机渲染截图通过，确认 Godot 实际加载本次图集而非旧缓存。

## 后续 NPC 起点

下一阶段为 `NPC-DATA-2`：使用已经授权的 Crystal `Server.MirDB` 解析规则提取主服务端 NPC 表，建立 NPC 编号、地图、坐标、`Image`、脚本文件和服务类型目录；只有主资料缺项时才按辅 1、辅 2、辅 3 权重补证。
