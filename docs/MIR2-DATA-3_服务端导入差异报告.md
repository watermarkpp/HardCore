# MIR2-DATA-3 服务端导入差异报告

- 模式：`dry-run`
- 数据源：`C:\Users\Administrator\Documents\Codex\2026-06-28\xian\work\legend176_game\tests\fixtures\mir2_server`
- 自动识别数据根：`.`
- 版本清单：已提供
- 缺失项：0
- 解析错误：0

## 解析数量

| 数据表 | 数量 |
|---|---:|
| `maps` | 2 |
| `monsters` | 1 |
| `bosses` | 1 |
| `items` | 1 |
| `skills` | 4 |
| `drops` | 3 |
| `tasks` | 1 |
| `serverPortals` | 1 |
| `serverSpawns` | 2 |
| `serverMerchants` | 1 |

## 与当前项目数据的差异

| 表 | 当前 | 导入 | 匹配 | 新候选 | 字段冲突 |
|---|---:|---:|---:|---:|---:|
| `maps` | 142 | 2 | 2 | 0 | 2 |
| `monsters` | 214 | 1 | 1 | 0 | 1 |
| `bosses` | 46 | 1 | 1 | 0 | 1 |
| `items` | 175 | 1 | 1 | 0 | 1 |
| `skills` | 132 | 4 | 4 | 0 | 3 |
| `drops` | 3424 | 3 | 3 | 0 | 3 |
| `tasks` | 9 | 1 | 0 | 1 | 0 |

## 缺口与错误

- 无缺失。

## 合并规则

- identity：地图/怪物/装备按规范化名称；技能按名称+技能等级；掉落按怪物名+槽位
- precedence：服务端非空字段优先；现有网络来源 URL 保留；新增记录追加
- safety：默认 dry-run；仅 --apply 写入运行数据，写入前备份

> 候选文件不会自动进入运行时。先审阅本报告，确认数据包版本后再使用 `--apply`。
