# MIR2 传统服务端数据导入目录

把合法持有的服务端数据按原目录结构放在这里，然后运行：

```powershell
python tools/import_mir2_server_data.py --source import_server_data
```

支持的输入：

- `Envir/MapInfo.txt`：地图名称与门点配置。
- `Envir/MonGen.txt`：怪物刷新点。
- `Envir/MonItems/*.txt`：逐怪物掉落表。
- `Envir/Merchant.txt`：商人位置原始表。
- `Envir/Market_Def/*.txt`：提取包含物品/等级条件与奖励指令的任务脚本候选；复杂脚本仍需人工复核。
- `Monster.DB`、`StdItems.DB`、`Magic.DB`：支持 dBase/DBF 格式；若原文件为 Borland Paradox，请先用数据库工具导出为同名 `.csv` 或 `.json`。
- `Monster.csv`、`StdItems.csv`、`Magic.csv`：推荐的无损中间格式，列名保持原数据库字段名。

导入器默认只生成候选结果和差异报告，不会直接覆盖游戏运行数据。确认报告后，显式添加 `--apply` 才会把可安全匹配的服务端字段合并到 `assets/data/legend176_data.json`；写入前自动生成备份。

版本规则：正式合并必须提供 `import_manifest.json`。没有清单时所有记录标为 `未确认版本`，只允许生成差异报告，`--apply` 会拒绝执行。目录名或文件名包含 `幻境`、`圣域`、`追加`、`后期` 时仍会标记为 `1.76后期追加内容`；其余文件只有在清单明确声明后才可进入 `2003官服1.76基准版`。

导入器会依次检查数据根、`Mir200/`、`MirServer/Mir200/` 和 `Server/Mir200/`，因此可以保留传统服务端原目录结构，不必手工搬散文件。
