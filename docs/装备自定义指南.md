# 装备自定义指南

主要编辑文件：`assets/data/equipment_customization.json`。

## 修改现有装备

在 `overrides` 中使用装备原名，并把要修改的字段写入 `fields`。未写字段保持原值。例如把木剑攻击改为5—12：

```json
"木剑": {"fields": {"attackMin": 5, "attackMax": 12}}
```

可修改字段包括：`category`、`profession`、`weight`、`maxDurability`、`attackMin/attackMax`、`magicMin/magicMax`、`taoMin/taoMax`、`defenseMin/defenseMax`、`mdefMin/mdefMax`、`accuracy`、`agility`、`luck`、`hpBonus`、`mpBonus`、`lifeStealPercent`、`reqLevel/reqAttack/reqMagic/reqTao`、`price`、`versionTag`。

扩展词条统一写入 `modifiers`：

```json
"modifiers": {
  "criticalChance": 0.15,
  "criticalDamageBonus": 0.5,
  "attackSpeedPercent": 0.20,
  "castSpeedPercent": 0.15,
  "skillLevels": {"all": 1, "烈火剑法": 1}
}
```

以上代表暴击率15%、暴击倍率在基础1.5倍上增加0.5、攻击速度+20%、施法速度+15%、全部技能+1且烈火剑法再+1。速度词条会同时缩短对应冷却、动作和命中前摇；没有词条时仍保持850ms攻击间隔和510ms动作。

## 新增装备

在 `newEquipment` 数组增加完整对象。最少需要 `name`、`category`、`profession`、`maxDurability`。名称必须唯一，类别必须是武器、盔甲、头盔、项链、手镯或戒指。

## 特殊效果与套装

- `specialEffect.id` 必须使用 `supportedSpecialEffectIds` 中已有的通用执行器。
- `setPiece.set` 必须使用 `supportedSetIds`；`piece` 表示组件位置，`power` 是该件强度。
- 普通数值属性可以自由增删；全新的行为型效果仍需增加一个通用代码执行器，不能只写任意字符串就自动获得新逻辑。
- 修改配置后重新启动游戏即可重新载入。存档中的装备实例会保留耐久、幸运、诅咒和唯一ID，目录属性按新配置重新结算。

## 装备美术

客户端默认映射位于 `assets/data/equipment_client_art_sources.json`，不要直接修改生成文件；用户覆盖仍写入 `equipment_customization.json` 的 `fields.art`。例如替换木剑的三种图像：

```json
"木剑": {
  "fields": {
    "art": {
      "inventoryIcon": {"path": "res://my_art/wood_sword_bag.png"},
      "equippedIcon": {"path": "res://my_art/wood_sword_state.png"},
      "groundIcon": {"path": "res://my_art/wood_sword_ground.png"}
    }
  }
}
```

- `inventoryIcon` 用于背包列表，`equippedIcon` 用于装备栏，`groundIcon` 用于地图掉落。
- 默认175件映射来自逐件资料页图片索引（B级候选），实际像素来自本地经典客户端 `Items/StateItem/DnItems.wil`（A级客户端源）。未来导入 `StdItems.Looks` 后可自动升级逐件映射，不需要改界面代码。
- `weaponAppearance` 和 `dressAppearance` 已接入当前男性战士的动态穿戴层，内部按 `idle/walk/attack/hit/death` 五套八方向图集配置。已有映射可以由配置整体覆盖；未知或版本越界的Shape继续使用装备强调层，不把背包图标冒充人物动作图。
- `art` 使用增量合并：只替换 `inventoryIcon` 不会删除已有的 `weaponAppearance/dressAppearance`，因此可以独立修改背包图、装备栏图、地面图或人物动作图。
- 动态穿戴图与属性是否生效相互独立：耐久为0时装备仍显示在人物身上，但攻击、防御、特殊效果和词条继续失效，维修后恢复属性。
