# BICH-MAP-2 NPC、安全区、回城点与怪物生态

- 原版 NPC：5 名，来自 `vanilla_176/npcs.json`。
- 单机扩展 NPC：仓库管理员、药剂商、铁匠，独立存放于个人扩展层。
- 城市安全区：中心 `(128,128)`，半径 16 Tile。
- 回城规则：主动退出、返回角色选择和进程异常均使用比奇安全区锚点。
- 普通怪：稻草人、多钩猫、钉耙猫、半兽人、森林雪人、食人花。
- 明确排除：鸡、鹿。
- 生态分层：近郊新手环、远郊强化环、道路与城门安全缓冲。
- Runtime：`assets/data/runtime/map_editor/bich_province.runtime.json`。
