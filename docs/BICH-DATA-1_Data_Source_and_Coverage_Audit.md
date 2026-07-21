# BICH-DATA-1：数据来源与覆盖审计

## 结论

- 比奇目标怪物运行条目：15/15；当前均为带来源的B级候选。
- 正式传统服务端表：0/8可用；`import_server_data` dry-run缺失8类输入。
- 公开后期数据库交叉命中：15/15；可比字段完全一致78/105。
- 公开库含刺客、坐骑、暴击等现代Crystal字段，地图0也不是比奇省，因此全部保持后期候选，未覆盖2003运行库。
- 骷髅精灵2000/1200ms与尸王2800/1500ms攻击/移动间隔在网页候选和公开数据库中一致，可继续保持B级双源候选。

## 比奇怪物字段交叉结果

| 怪物 | 运行候选 | 后期库 | 一致字段 | 差异字段（运行→后期） |
|---|---|---|---|---|
| 稻草人 | 有 | 有 | level, defense, magicDefense, attackMin, attackMax | hp:15→20；exp:12→15 |
| 钉耙猫 | 有 | 有 | level, defense, magicDefense, attackMin, attackMax | hp:23→32；exp:18→27 |
| 半兽人 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:25→30 |
| 森林雪人 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:30→36 |
| 食人花 | 有 | 有 | level, hp, defense, magicDefense, attackMin | exp:28→36；attackMax:9→7 |
| 骷髅 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:85→140 |
| 掷斧骷髅 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:90→140 |
| 骷髅战士 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:95→150 |
| 骷髅战将 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:100→160 |
| 骷髅精灵 | 有 | 有 | hp, defense, magicDefense, attackMin, attackMax | level:40→50；exp:600→960 |
| 僵尸1 | 有 | 有 | level, hp | exp:160→210；defense:0→2；magicDefense:0→1；attackMin:12→6；attackMax:16→17 |
| 尸王 | 有 | 有 | hp, defense, magicDefense, attackMin | level:40→50；exp:800→1200；attackMax:36→38 |
| 洞蛆 | 有 | 有 | defense, magicDefense, attackMin, attackMax | level:21→31；hp:65→80；exp:60→122 |
| 蝎子 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:45→85 |
| 山洞蝙蝠 | 有 | 有 | level, hp, defense, magicDefense, attackMin, attackMax | exp:25→34 |

## 地图与刷新交叉结果

- 后期库命中目标地图4张、目标刷新54行。
- D001/D002/D003名称仍对应半兽古墓一至三层，可用于确认地图语义；坐标、数量和刷新周期不直接采用。
- 地图0在后期库名为飞天县，与当前2003比奇省基准冲突，已明确拒绝映射。
- D011/D012/Q004没有在该后期导出中形成目标地图命中，继续等待传统MapInfo/MonGen。

## 导入安全链

- 自动识别根目录、`Mir200`、`MirServer/Mir200`、`Server/Mir200`。
- 无 `import_manifest.json` 时记录标为未确认版本，允许dry-run但拒绝`--apply`。
- 基准与后期文件可逐文件标记；合并前生成差异报告和运行库备份。

## 尚未完成

- 缺同版本Monster、StdItems、Magic、MapInfo、MonGen、MonItems、Merchant及Market_Def正式文件。
- 因正式数据缺失，本审计没有提高运行内容的数据还原分数；不以公开后期库冒充官服数据。
