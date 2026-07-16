class_name RegionContent
extends RefCounted

const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")

const MINE_SOURCE_SIZES := {
	401: Vector2i(200, 200), 402: Vector2i(100, 100), 403: Vector2i(100, 100), 404: Vector2i(200, 200),
	405: Vector2i(100, 100), 406: Vector2i(200, 200), 407: Vector2i(100, 100), 408: Vector2i(200, 200),
	409: Vector2i(100, 100), 410: Vector2i(200, 200), 411: Vector2i(100, 100), 412: Vector2i(200, 200),
	1578: Vector2i(30, 30),
}

# source_coordinate是原MAP逻辑坐标；运行position由统一等距映射生成。
const MAPS := {
	4: {
		"name": "比奇省",
		"status": "client_map_full_size",
		"source_map": "0",
		"source_map_path": "research/mir2_client_raw/Map/0.map",
		"source_size": Vector2i(700, 700),
		"service_map_id": 0,
		"service_home_coordinate": Vector2i(289, 618),
		"spawns": [
			{"name": "稻草人", "source_coordinate": Vector2i(283, 625), "source_confidence": "C"}, {"name": "多钩猫", "source_coordinate": Vector2i(295, 612), "source_confidence": "C"},
			{"name": "钉耙猫", "source_coordinate": Vector2i(292, 626), "source_confidence": "C"}, {"name": "半兽人", "source_coordinate": Vector2i(298, 620), "source_confidence": "C"},
			{"name": "森林雪人", "source_coordinate": Vector2i(273, 617), "source_confidence": "C"}, {"name": "食人花", "source_coordinate": Vector2i(288, 602), "source_confidence": "C"},
		],
		"npcs": [
			{"name": "比奇杂货商", "kind": "shop", "stock": "general", "source_coordinate": Vector2i(274, 613), "source_confidence": "C"},
			{"name": "比奇武器店", "kind": "shop", "stock": "starter_gear", "source_coordinate": Vector2i(284, 603), "source_confidence": "C"},
			{"name": "书店老板", "kind": "shop", "stock": "books", "source_coordinate": Vector2i(297, 622), "source_confidence": "C"},
			{"name": "武馆教头", "kind": "trainer", "source_coordinate": Vector2i(293, 626), "source_confidence": "C"},
			{"name": "比奇老兵", "kind": "quest", "source_coordinate": Vector2i(280, 625), "source_confidence": "C"},
		],
		"portals": [
			{"target_map_id": 217, "source_coordinate": Vector2i(288, 598), "source_confidence": "C", "label": "进入兽人古墓一层"},
			{"target_map_id": 248, "source_coordinate": Vector2i(269, 617), "source_confidence": "C", "label": "进入天然洞穴一层"},
			{"target_map_id": 401, "source_coordinate": Vector2i(298, 627), "source_confidence": "C", "label": "进入比奇废矿"},
			{"target_map_id": 268, "source_coordinate": Vector2i(304, 614), "source_confidence": "C", "label": "前往沃玛森林"},
			{"target_map_id": 338, "source_coordinate": Vector2i(285, 633), "source_confidence": "C", "label": "前往毒蛇山谷"},
		],
	},
	217: {
		"name": "兽人古墓一层",
		"status": "client_map_full_size", "source_map": "D001", "source_size": Vector2i(400, 400), "source_map_path": "research/mir2_client_raw/Map/D001.map",
		"spawns": [
			{"name": "骷髅", "source_coordinate": Vector2i(77, 377), "position": Vector2(-420, 210)},
			{"name": "掷斧骷髅", "source_coordinate": Vector2i(80, 374), "source_confidence": "C", "position": Vector2(-330, 180)},
			{"name": "骷髅战士", "source_coordinate": Vector2i(186, 141), "position": Vector2(260, -180)},
			{"name": "山洞蝙蝠", "source_coordinate": Vector2i(198, 237), "position": Vector2(300, 120)},
			{"name": "洞蛆", "source_coordinate": Vector2i(202, 240), "source_confidence": "C", "position": Vector2(390, 170)},
		],
		"portals": [
			{"target_map_id": 4, "source_coordinate": Vector2i(25, 374), "source_confidence": "C", "position": Vector2(-650, 300), "label": "返回比奇省"},
			{"target_map_id": 218, "source_coordinate": Vector2i(381, 23), "source_confidence": "C", "position": Vector2(650, -300), "label": "前往兽人古墓二层"},
		],
	},
	218: {
		"name": "兽人古墓二层",
		"status": "client_map_full_size", "source_map": "D002", "source_size": Vector2i(400, 400), "source_map_path": "research/mir2_client_raw/Map/D002.map",
		"spawns": [
			{"name": "骷髅", "source_coordinate": Vector2i(174, 195), "position": Vector2(-260, -80)},
			{"name": "骷髅", "source_coordinate": Vector2i(197, 203), "position": Vector2(260, 80)},
			{"name": "掷斧骷髅", "source_coordinate": Vector2i(87, 126), "position": Vector2(-430, -220)},
			{"name": "骷髅战士", "source_coordinate": Vector2i(178, 198), "source_confidence": "C", "position": Vector2(-160, 120)},
			{"name": "骷髅战将", "source_coordinate": Vector2i(201, 207), "source_confidence": "C", "position": Vector2(350, 170)},
			{"name": "山洞蝙蝠", "source_coordinate": Vector2i(332, 80), "position": Vector2(430, -180)}, {"name": "洞蛆", "source_coordinate": Vector2i(57, 351), "position": Vector2(-380, 230)},
		],
		"bosses": [
			{"name": "骷髅精灵", "source_coordinate": Vector2i(200, 200), "position": Vector2(560, 260), "respawn_seconds": 3600.0},
		],
		"portals": [
			{"target_map_id": 217, "source_coordinate": Vector2i(30, 357), "source_confidence": "C", "position": Vector2(-650, 300), "label": "返回兽人古墓一层"},
			{"target_map_id": 221, "source_coordinate": Vector2i(364, 44), "source_confidence": "C", "position": Vector2(650, -300), "label": "前往兽人古墓三层"},
		],
	},
	221: {
		"name": "兽人古墓三层",
		"status": "client_map_full_size", "source_map": "D003", "source_size": Vector2i(400, 400), "source_map_path": "research/mir2_client_raw/Map/D003.map",
		"spawns": [
			{"name": "骷髅", "source_coordinate": Vector2i(97, 87), "position": Vector2(-330, -170)}, {"name": "骷髅", "source_coordinate": Vector2i(289, 300), "position": Vector2(290, 150)},
			{"name": "掷斧骷髅", "source_coordinate": Vector2i(311, 84), "position": Vector2(340, -190)}, {"name": "骷髅战士", "source_coordinate": Vector2i(114, 319), "position": Vector2(-280, 180)},
			{"name": "骷髅战将", "source_coordinate": Vector2i(201, 28), "position": Vector2(0, -260)}, {"name": "山洞蝙蝠", "source_coordinate": Vector2i(56, 214), "position": Vector2(-470, 20)},
			{"name": "洞蛆", "source_coordinate": Vector2i(343, 221), "position": Vector2(470, 30)},
		],
		"bosses": [
			{"name": "骷髅精灵", "source_coordinate": Vector2i(196, 204), "position": Vector2(560, 230), "respawn_seconds": 3600.0},
		],
		"portals": [
			{"target_map_id": 218, "source_coordinate": Vector2i(66, 298), "source_confidence": "C", "position": Vector2(-650, 300), "label": "返回兽人古墓二层"},
		],
	},
	248: {
		"name": "洞穴一层", "status": "client_map_full_size", "source_map": "D011", "source_size": Vector2i(400, 400), "source_map_path": "research/mir2_client_raw/Map/D011.map",
		"spawns": [
			{"name": "山洞蝙蝠", "source_coordinate": Vector2i(89, 75), "position": Vector2(-360, -180)}, {"name": "蝎子", "source_coordinate": Vector2i(312, 92), "position": Vector2(330, -160)},
			{"name": "洞蛆", "source_coordinate": Vector2i(113, 327), "position": Vector2(-270, 190)}, {"name": "骷髅", "source_coordinate": Vector2i(309, 314), "position": Vector2(300, 180)},
		],
		"portals": [
			{"target_map_id": 4, "source_coordinate": Vector2i(28, 352), "source_confidence": "C", "position": Vector2(-620, 300), "label": "返回比奇省"},
			{"target_map_id": 249, "source_coordinate": Vector2i(314, 31), "source_confidence": "C", "position": Vector2(620, -300), "label": "前往洞穴二层"},
		],
	},
	249: {
		"name": "洞穴二层", "status": "client_map_full_size", "source_map": "D012", "source_size": Vector2i(400, 400), "source_map_path": "research/mir2_client_raw/Map/D012.map",
		"spawns": [
			{"name": "山洞蝙蝠", "source_coordinate": Vector2i(46, 80), "position": Vector2(-410, -210)}, {"name": "蝎子", "source_coordinate": Vector2i(326, 87), "position": Vector2(390, -170)},
			{"name": "洞蛆", "source_coordinate": Vector2i(94, 332), "position": Vector2(-320, 200)}, {"name": "骷髅战士", "source_coordinate": Vector2i(306, 340), "position": Vector2(330, 210)},
		],
		"portals": [{"target_map_id": 248, "source_coordinate": Vector2i(38, 375), "source_confidence": "C", "position": Vector2(-620, 300), "label": "返回洞穴一层"}],
	},
	401: {
		"name": "废矿入口", "status": "client_map_vertical_slice", "source_map": "D401",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-350, -180)}, {"name": "僵尸2", "position": Vector2(340, -170)},
			{"name": "僵尸3", "position": Vector2(-250, 180)}, {"name": "僵尸4", "position": Vector2(260, 190)},
			{"name": "山洞蝙蝠", "position": Vector2(0, -270)},
		],
		"portals": [
			{"target_map_id": 4, "position": Vector2(0, 350), "label": "返回比奇省"},
			{"target_map_id": 402, "position": Vector2(-620, -280), "label": "前往矿区B一层"},
			{"target_map_id": 403, "position": Vector2(620, -280), "label": "前往矿区A一层"},
		],
	},
	402: {
		"name": "矿区B一层", "status": "client_map_vertical_slice", "source_map": "D411",
		"spawns": [{"name": "僵尸1", "position": Vector2(-300, -120)}, {"name": "僵尸2", "position": Vector2(290, 130)}],
		"portals": [
			{"target_map_id": 401, "position": Vector2(-620, 300), "label": "返回废矿入口"},
			{"target_map_id": 404, "position": Vector2(620, -300), "label": "前往废矿区东部"},
		],
	},
	403: {
		"name": "矿区A一层", "status": "client_map_vertical_slice", "source_map": "D413",
		"spawns": [{"name": "僵尸3", "position": Vector2(-310, -130)}, {"name": "僵尸4", "position": Vector2(300, 140)}],
		"portals": [
			{"target_map_id": 401, "position": Vector2(-620, 300), "label": "返回废矿入口"},
			{"target_map_id": 404, "position": Vector2(620, -300), "label": "前往废矿区东部"},
		],
	},
	404: {
		"name": "废矿区东部", "status": "client_map_vertical_slice", "source_map": "D402",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-390, -200)}, {"name": "僵尸2", "position": Vector2(380, -190)},
			{"name": "僵尸3", "position": Vector2(-300, 190)}, {"name": "僵尸4", "position": Vector2(290, 200)},
			{"name": "僵尸5", "position": Vector2(0, -260)}, {"name": "山洞蝙蝠", "position": Vector2(0, 260)},
		],
		"portals": [
			{"target_map_id": 402, "position": Vector2(-620, -300), "label": "返回矿区B一层"},
			{"target_map_id": 403, "position": Vector2(-620, 300), "label": "返回矿区A一层"},
			{"target_map_id": 405, "position": Vector2(620, 300), "label": "前往矿区C一层"},
			{"target_map_id": 1578, "position": Vector2(620, -300), "label": "进入尸王殿（结构候选）"},
		],
	},
	405: {
		"name": "矿区C一层", "status": "client_map_vertical_slice", "source_map": "D414", "spawns": [],
		"portals": [
			{"target_map_id": 404, "position": Vector2(-620, 300), "label": "返回废矿区东部"},
			{"target_map_id": 406, "position": Vector2(620, -300), "label": "前往矿区一层"},
		],
	},
	406: {
		"name": "矿区一层", "status": "client_map_vertical_slice", "source_map": "D403",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-390, -210)}, {"name": "僵尸2", "position": Vector2(380, -190)},
			{"name": "僵尸3", "position": Vector2(-300, 190)}, {"name": "僵尸4", "position": Vector2(290, 210)},
			{"name": "僵尸5", "position": Vector2(0, -270)}, {"name": "山洞蝙蝠", "position": Vector2(0, 260)},
		],
		"portals": [
			{"target_map_id": 405, "position": Vector2(-620, 300), "label": "返回矿区C一层"},
			{"target_map_id": 407, "position": Vector2(620, -300), "label": "前往矿区桥一"},
		],
	},
	407: {
		"name": "桥", "status": "client_map_vertical_slice", "source_map": "D412",
		"spawns": [{"name": "僵尸2", "position": Vector2(-220, 0)}, {"name": "僵尸3", "position": Vector2(220, 0)}],
		"portals": [
			{"target_map_id": 406, "position": Vector2(-620, 300), "label": "返回矿区一层"},
			{"target_map_id": 408, "position": Vector2(620, -300), "label": "前往矿区B二层"},
		],
	},
	408: {
		"name": "矿区B二层", "status": "client_map_vertical_slice", "source_map": "D404",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-430, -220)}, {"name": "僵尸2", "position": Vector2(420, -200)},
			{"name": "僵尸3", "position": Vector2(-320, 190)}, {"name": "僵尸4", "position": Vector2(310, 210)},
			{"name": "僵尸5", "position": Vector2(0, -280)}, {"name": "山洞蝙蝠", "position": Vector2(-80, 270)},
			{"name": "洞蛆", "position": Vector2(110, 260)},
		],
		"portals": [
			{"target_map_id": 407, "position": Vector2(-620, 300), "label": "返回矿区桥一"},
			{"target_map_id": 409, "position": Vector2(620, -300), "label": "前往矿区桥二"},
			{"target_map_id": 412, "position": Vector2(0, 350), "label": "前往废矿区南部"},
		],
	},
	409: {
		"name": "桥", "status": "client_map_vertical_slice", "source_map": "D415",
		"spawns": [{"name": "僵尸3", "position": Vector2(-220, 0)}, {"name": "僵尸4", "position": Vector2(220, 0)}],
		"portals": [
			{"target_map_id": 408, "position": Vector2(-620, 300), "label": "返回矿区B二层"},
			{"target_map_id": 410, "position": Vector2(620, -300), "label": "前往矿物回收站"},
		],
	},
	410: {
		"name": "矿物回收站", "status": "client_map_vertical_slice", "source_map": "D405",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-430, -220)}, {"name": "僵尸2", "position": Vector2(420, -200)},
			{"name": "僵尸3", "position": Vector2(-320, 190)}, {"name": "僵尸4", "position": Vector2(310, 210)},
			{"name": "僵尸5", "position": Vector2(0, -280)}, {"name": "山洞蝙蝠", "position": Vector2(-80, 270)},
			{"name": "洞蛆", "position": Vector2(110, 260)},
		],
		"portals": [
			{"target_map_id": 409, "position": Vector2(-620, 300), "label": "返回矿区桥二"},
			{"target_map_id": 411, "position": Vector2(620, -300), "label": "前往矿区桥三"},
		],
	},
	411: {
		"name": "桥", "status": "client_map_vertical_slice", "source_map": "D416",
		"spawns": [{"name": "僵尸4", "position": Vector2(-220, 0)}, {"name": "僵尸5", "position": Vector2(220, 0)}],
		"portals": [
			{"target_map_id": 410, "position": Vector2(-620, 300), "label": "返回矿物回收站"},
			{"target_map_id": 412, "position": Vector2(620, -300), "label": "前往废矿区南部"},
		],
	},
	412: {
		"name": "废矿区南部", "status": "client_map_vertical_slice", "source_map": "D406",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-460, -230)}, {"name": "僵尸2", "position": Vector2(450, -220)},
			{"name": "僵尸3", "position": Vector2(-360, 170)}, {"name": "僵尸4", "position": Vector2(350, 190)},
			{"name": "僵尸5", "position": Vector2(0, -290)}, {"name": "山洞蝙蝠", "position": Vector2(-160, 270)},
			{"name": "洞蛆", "position": Vector2(170, 260)}, {"name": "蝎子", "position": Vector2(-40, 80)},
			{"name": "僵尸3", "position": Vector2(70, -80)},
		],
		"portals": [
			{"target_map_id": 411, "position": Vector2(-620, 300), "label": "返回矿区桥三"},
			{"target_map_id": 408, "position": Vector2(620, -300), "label": "返回矿区B二层"},
		],
	},
	1578: {
		"name": "尸王殿", "status": "client_map_vertical_slice", "source_map": "Q004",
		"spawns": [{"name": "僵尸4", "position": Vector2(-330, 190)}, {"name": "僵尸5", "position": Vector2(330, 190)}],
		"bosses": [
			{"name": "尸王", "position": Vector2(-240, -120), "respawn_seconds": 1800.0},
			{"name": "尸王", "position": Vector2(240, -120), "respawn_seconds": 1800.0},
		],
		"portals": [{"target_map_id": 404, "position": Vector2(0, 340), "label": "返回废矿区东部"}],
	},
	268: {
		"name": "沃玛森林", "status": "client_map_vertical_slice", "source_map": "1",
		"spawns": [
			{"name": "半兽战士", "position": Vector2(-360, -170)}, {"name": "半兽勇士", "position": Vector2(350, -160)},
			{"name": "粪虫", "position": Vector2(-260, 190)}, {"name": "暗黑战士", "position": Vector2(270, 190)},
		],
		"portals": [
			{"target_map_id": 4, "position": Vector2(-620, 300), "label": "返回比奇省"},
			{"target_map_id": 1506, "position": Vector2(0, -340), "label": "进入沃玛自然洞穴"},
			{"target_map_id": 312, "position": Vector2(620, 300), "label": "进入沃玛寺庙"},
		],
	},
	1506: {
		"name": "沃玛自然洞穴", "status": "client_map_vertical_slice", "source_map": "E001",
		"spawns": [
			{"name": "粪虫", "position": Vector2(-430, -220)}, {"name": "暗黑战士", "position": Vector2(420, -210)},
			{"name": "洞蛆", "position": Vector2(-330, 180)}, {"name": "蝎子", "position": Vector2(320, 190)},
			{"name": "山洞蝙蝠", "position": Vector2(0, -270)}, {"name": "骷髅战将", "position": Vector2(0, 260)},
			{"name": "粪虫", "position": Vector2(-160, 40)}, {"name": "暗黑战士", "position": Vector2(170, 30)},
		],
		"portals": [
			{"target_map_id": 268, "position": Vector2(-620, 300), "label": "返回沃玛森林"},
			{"target_map_id": 1507, "position": Vector2(620, -300), "label": "深入沃玛自然洞穴"},
			{"target_map_id": 312, "position": Vector2(0, 340), "label": "通往沃玛寺庙入口"},
		],
	},
	1507: {
		"name": "沃玛自然洞穴", "status": "client_map_vertical_slice", "source_map": "E002",
		"spawns": [
			{"name": "粪虫", "position": Vector2(-430, -220)}, {"name": "暗黑战士", "position": Vector2(420, -210)},
			{"name": "洞蛆", "position": Vector2(-330, 180)}, {"name": "蝎子", "position": Vector2(320, 190)},
			{"name": "山洞蝙蝠", "position": Vector2(0, -270)}, {"name": "骷髅战将", "position": Vector2(0, 260)},
			{"name": "暗黑战士", "position": Vector2(-160, 40)}, {"name": "粪虫", "position": Vector2(170, 30)},
		],
		"portals": [{"target_map_id": 1506, "position": Vector2(-620, 300), "label": "返回沃玛自然洞穴入口"}],
	},
	312: {
		"name": "沃玛寺庙入口", "status": "client_map_vertical_slice", "source_map": "D021",
		"spawns": [{"name": "粪虫", "position": Vector2(-250, 0)}, {"name": "暗黑战士", "position": Vector2(250, 0)}],
		"portals": [
			{"target_map_id": 268, "position": Vector2(-620, 300), "label": "返回沃玛森林"},
			{"target_map_id": 313, "position": Vector2(620, -300), "label": "前往沃玛寺庙一层"},
			{"target_map_id": 1506, "position": Vector2(-620, -300), "label": "通往自然洞穴一"},
			{"target_map_id": 1507, "position": Vector2(620, 300), "label": "通往自然洞穴二"},
		],
	},
	313: {
		"name": "沃玛寺庙一层", "status": "client_map_vertical_slice", "source_map": "D022",
		"spawns": [
			{"name": "沃玛战士", "position": Vector2(-430, -220)}, {"name": "沃玛勇士", "position": Vector2(420, -210)},
			{"name": "沃玛战将", "position": Vector2(-330, 180)}, {"name": "火焰沃玛", "position": Vector2(320, 190)},
			{"name": "暗黑战士", "position": Vector2(0, -270)}, {"name": "粪虫", "position": Vector2(-120, 250)},
			{"name": "沃玛战士", "position": Vector2(150, 240)},
		],
		"portals": [
			{"target_map_id": 312, "position": Vector2(-620, 300), "label": "返回寺庙入口西"},
			{"target_map_id": 312, "position": Vector2(-620, -300), "label": "返回寺庙入口东"},
			{"target_map_id": 314, "position": Vector2(620, 300), "label": "前往寺庙二层西"},
			{"target_map_id": 314, "position": Vector2(620, -300), "label": "前往寺庙二层东"},
		],
	},
	314: {
		"name": "沃玛寺庙二层", "status": "client_map_vertical_slice", "source_map": "D023",
		"spawns": [
			{"name": "沃玛战士", "position": Vector2(-450, -230)}, {"name": "沃玛勇士", "position": Vector2(440, -220)},
			{"name": "沃玛战将", "position": Vector2(-350, 170)}, {"name": "火焰沃玛", "position": Vector2(340, 190)},
			{"name": "暗黑战士", "position": Vector2(0, -290)}, {"name": "粪虫", "position": Vector2(-170, 270)},
			{"name": "沃玛战士", "position": Vector2(180, 260)}, {"name": "火焰沃玛", "position": Vector2(0, 40)},
		],
		"portals": [
			{"target_map_id": 313, "position": Vector2(-620, 300), "label": "返回寺庙一层西"},
			{"target_map_id": 313, "position": Vector2(-620, -300), "label": "返回寺庙一层东"},
			{"target_map_id": 315, "position": Vector2(620, -300), "label": "进入沃玛寺庙核心"},
		],
	},
	315: {
		"name": "沃玛寺庙", "status": "client_map_vertical_slice", "source_map": "D024",
		"spawns": [
			{"name": "沃玛战士", "position": Vector2(-380, -190)}, {"name": "沃玛勇士", "position": Vector2(370, -180)},
			{"name": "沃玛战将", "position": Vector2(-280, 190)}, {"name": "火焰沃玛", "position": Vector2(290, 190)},
		],
		"bosses": [
			{"name": "沃玛卫士", "position": Vector2(-170, -50), "respawn_seconds": 3600.0},
			{"name": "沃玛教主", "position": Vector2(240, -40), "respawn_seconds": 7200.0},
		],
		"portals": [{"target_map_id": 314, "position": Vector2(-620, 300), "label": "返回沃玛寺庙二层"}],
	},
	338: {
		"name": "毒蛇山谷", "status": "client_map_vertical_slice", "source_map": "2",
		"spawns": [
			{"name": "红蛇", "position": Vector2(-390, -200)}, {"name": "虎蛇", "position": Vector2(380, -190)},
			{"name": "多钩猫", "position": Vector2(-300, 190)}, {"name": "钉耙猫", "position": Vector2(290, 200)},
			{"name": "半兽人", "position": Vector2(0, -270)}, {"name": "半兽战士", "position": Vector2(0, 260)},
		],
		"portals": [
			{"target_map_id": 4, "position": Vector2(-620, 300), "label": "返回比奇省"},
			{"target_map_id": 457, "position": Vector2(0, -340), "label": "进入山谷矿区"},
			{"target_map_id": 478, "position": Vector2(620, 300), "label": "前往盟重省"},
		],
	},
	457: {
		"name": "山谷矿区", "status": "client_map_vertical_slice", "source_map": "D421",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-430, -220)}, {"name": "僵尸2", "position": Vector2(420, -210)},
			{"name": "僵尸3", "position": Vector2(-330, 180)}, {"name": "僵尸4", "position": Vector2(320, 190)},
			{"name": "僵尸5", "position": Vector2(0, -270)}, {"name": "山洞蝙蝠", "position": Vector2(-140, 260)},
			{"name": "洞蛆", "position": Vector2(150, 250)},
		],
		"portals": [
			{"target_map_id": 338, "position": Vector2(-620, 300), "label": "返回毒蛇山谷"},
			{"target_map_id": 458, "position": Vector2(620, -300), "label": "深入山谷矿区"},
		],
	},
	458: {
		"name": "山谷矿区", "status": "client_map_vertical_slice", "source_map": "D422",
		"spawns": [
			{"name": "僵尸1", "position": Vector2(-470, -240)}, {"name": "僵尸2", "position": Vector2(460, -230)},
			{"name": "僵尸3", "position": Vector2(-380, 170)}, {"name": "僵尸4", "position": Vector2(370, 190)},
			{"name": "僵尸5", "position": Vector2(0, -290)}, {"name": "山洞蝙蝠", "position": Vector2(-220, 270)},
			{"name": "洞蛆", "position": Vector2(230, 260)}, {"name": "僵尸2", "position": Vector2(-100, 70)},
			{"name": "僵尸4", "position": Vector2(120, -60)}, {"name": "蝎子", "position": Vector2(0, 170)},
		],
		"portals": [
			{"target_map_id": 457, "position": Vector2(-620, 300), "label": "返回山谷矿区入口"},
			{"target_map_id": 457, "position": Vector2(-620, -300), "label": "返回山谷矿区侧门"},
			{"target_map_id": 338, "position": Vector2(620, 300), "label": "返回毒蛇山谷南口"},
			{"target_map_id": 338, "position": Vector2(620, -300), "label": "返回毒蛇山谷北口"},
		],
	},
	478: {
		"name": "盟重省", "status": "structure_candidate",
		"spawns": [
			{"name": "猎鹰", "position": Vector2(-390, -200)}, {"name": "盔甲虫", "position": Vector2(380, -190)},
			{"name": "沙虫", "position": Vector2(-300, 190)}, {"name": "蝎子", "position": Vector2(290, 200)},
			{"name": "半兽勇士", "position": Vector2(0, -270)}, {"name": "红蛇", "position": Vector2(0, 260)},
		],
		"npcs": [
			{"name": "盟重杂货商", "kind": "shop", "stock": "general", "position": Vector2(-300, -250)},
			{"name": "盟重装备店", "kind": "shop", "stock": "mid_gear", "position": Vector2(300, -250)},
			{"name": "盟重书店", "kind": "shop", "stock": "books", "position": Vector2(120, 280)},
			{"name": "盟重武馆教头", "kind": "trainer", "position": Vector2(-120, 280)},
		],
		"portals": [
			{"target_map_id": 338, "position": Vector2(-650, 310), "label": "返回毒蛇山谷"},
			{"target_map_id": 1197, "position": Vector2(-650, -310), "label": "进入石墓"},
			{"target_map_id": 1378, "position": Vector2(650, -310), "label": "进入蜈蚣洞"},
			{"target_map_id": 659, "position": Vector2(650, 310), "label": "进入祖玛寺庙"},
			{"target_map_id": 1183, "position": Vector2(0, 360), "label": "进入沙巴克密道"},
			{"target_map_id": 3013, "position": Vector2(0, -360), "label": "前往封魔谷"},
			{"target_map_id": 2863, "position": Vector2(600, 0), "label": "前往白日门"},
			{"target_map_id": 3165, "position": Vector2(-600, 0), "label": "前往苍月岛"},
		],
	},
	1183: {
		"name": "沙巴克密道", "status": "structure_candidate", "spawns": [],
		"portals": [{"target_map_id": 478, "position": Vector2(-620, 300), "label": "返回盟重省"}, {"target_map_id": 1488, "position": Vector2(620, -300), "label": "进入香石墓穴"}],
	},
	1197: {
		"name": "石墓入口", "status": "structure_candidate", "spawns": [],
		"portals": [{"target_map_id": 478, "position": Vector2(-620, 300), "label": "返回盟重省"}, {"target_map_id": 1198, "position": Vector2(620, -300), "label": "进入石墓一层"}],
	},
	1198: {
		"name": "石墓一层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-350, -170)}, {"name": "黑野猪", "position": Vector2(340, -160)}, {"name": "楔蛾", "position": Vector2(-260, 190)}, {"name": "蝎蛇", "position": Vector2(270, 190)}],
		"portals": [{"target_map_id": 1197, "position": Vector2(-620, 300), "label": "返回石墓入口"}, {"target_map_id": 1199, "position": Vector2(620, -300), "label": "前往石墓二层"}],
	},
	1199: {
		"name": "石墓二层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-350, -170)}, {"name": "黑野猪", "position": Vector2(340, -160)}, {"name": "楔蛾", "position": Vector2(-260, 190)}, {"name": "蝎蛇", "position": Vector2(270, 190)}],
		"portals": [{"target_map_id": 1198, "position": Vector2(-620, 300), "label": "返回石墓一层"}, {"target_map_id": 1200, "position": Vector2(620, -300), "label": "前往石墓三层"}, {"target_map_id": 1203, "position": Vector2(0, 340), "label": "进入石墓阵支路"}],
	},
	1200: {
		"name": "石墓三层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-400, -200)}, {"name": "黑野猪", "position": Vector2(390, -190)}, {"name": "楔蛾", "position": Vector2(-300, 190)}, {"name": "蝎蛇", "position": Vector2(290, 200)}, {"name": "红野猪", "position": Vector2(0, -270)}, {"name": "黑野猪", "position": Vector2(0, 260)}],
		"portals": [{"target_map_id": 1199, "position": Vector2(-620, 300), "label": "返回石墓二层"}, {"target_map_id": 1201, "position": Vector2(620, -300), "label": "前往石墓四层"}],
	},
	1201: {
		"name": "石墓四层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-410, -210)}, {"name": "黑野猪", "position": Vector2(400, -200)}, {"name": "楔蛾", "position": Vector2(-310, 190)}, {"name": "蝎蛇", "position": Vector2(300, 200)}, {"name": "红野猪", "position": Vector2(0, -280)}, {"name": "黑野猪", "position": Vector2(0, 260)}],
		"bosses": [{"name": "白野猪", "position": Vector2(190, 20), "respawn_seconds": 1800.0}],
		"portals": [{"target_map_id": 1200, "position": Vector2(-620, 300), "label": "返回石墓三层"}, {"target_map_id": 1202, "position": Vector2(620, -300), "label": "前往石墓五层"}],
	},
	1202: {
		"name": "石墓五层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-410, -210)}, {"name": "黑野猪", "position": Vector2(400, -200)}, {"name": "楔蛾", "position": Vector2(-310, 190)}, {"name": "蝎蛇", "position": Vector2(300, 200)}, {"name": "红野猪", "position": Vector2(0, -280)}, {"name": "黑野猪", "position": Vector2(0, 260)}],
		"bosses": [{"name": "白野猪", "position": Vector2(190, 20), "respawn_seconds": 1800.0}],
		"portals": [{"target_map_id": 1201, "position": Vector2(-620, 300), "label": "返回石墓四层"}, {"target_map_id": 1203, "position": Vector2(620, -300), "label": "进入石墓阵"}],
	},
	1203: {
		"name": "石墓阵", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-460, -230)}, {"name": "黑野猪", "position": Vector2(450, -220)}, {"name": "楔蛾", "position": Vector2(-360, 170)}, {"name": "蝎蛇", "position": Vector2(350, 190)}, {"name": "红野猪", "position": Vector2(0, -290)}, {"name": "黑野猪", "position": Vector2(-180, 270)}, {"name": "楔蛾", "position": Vector2(190, 260)}, {"name": "蝎蛇", "position": Vector2(-80, 70)}, {"name": "红野猪", "position": Vector2(100, -60)}],
		"bosses": [{"name": "白野猪", "position": Vector2(230, 30), "respawn_seconds": 1800.0}],
		"portals": [{"target_map_id": 1202, "position": Vector2(-620, 300), "label": "返回石墓五层"}, {"target_map_id": 1232, "position": Vector2(620, -300), "label": "前往石墓六层"}, {"target_map_id": 1199, "position": Vector2(-620, -300), "label": "返回石墓二层支路"}, {"target_map_id": 478, "position": Vector2(620, 300), "label": "离开石墓阵"}],
	},
	1232: {
		"name": "石墓六层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-400, -200)}, {"name": "黑野猪", "position": Vector2(390, -190)}, {"name": "楔蛾", "position": Vector2(-300, 190)}, {"name": "蝎蛇", "position": Vector2(290, 200)}, {"name": "黑野猪", "position": Vector2(0, -270)}],
		"bosses": [{"name": "白野猪", "position": Vector2(190, 40), "respawn_seconds": 1800.0}],
		"portals": [{"target_map_id": 1203, "position": Vector2(-620, 300), "label": "返回石墓阵"}, {"target_map_id": 1233, "position": Vector2(620, -300), "label": "前往石墓七层"}],
	},
	1233: {
		"name": "石墓七层", "status": "structure_candidate",
		"spawns": [{"name": "红野猪", "position": Vector2(-360, -180)}, {"name": "黑野猪", "position": Vector2(350, -170)}, {"name": "楔蛾", "position": Vector2(-270, 190)}, {"name": "蝎蛇", "position": Vector2(280, 190)}],
		"bosses": [{"name": "石墓尸王", "position": Vector2(230, 20), "respawn_seconds": 7200.0}],
		"portals": [{"target_map_id": 1232, "position": Vector2(-620, 300), "label": "返回石墓六层"}, {"target_map_id": 1234, "position": Vector2(620, -300), "label": "桃源之门（触发候选）"}],
	},
	1234: {
		"name": "桃源之门", "status": "structure_candidate",
		"spawns": [{"name": "蜜蜂", "position": Vector2(-350, -170)}, {"name": "红野猪", "position": Vector2(340, -160)}, {"name": "黑野猪", "position": Vector2(-260, 190)}, {"name": "蝎蛇", "position": Vector2(270, 190)}],
		"portals": [{"target_map_id": 1233, "position": Vector2(-620, 300), "label": "返回石墓七层"}],
	},
}

const CENTIPEDE_MAPS := {
	1378: {"name": "地牢一层东", "spawn_count": 6, "targets": [478, 1379, 1380, 1445]},
	1379: {"name": "地牢一层西", "spawn_count": 3, "targets": [1378, 1381, 1445]},
	1380: {"name": "地牢一层北", "spawn_count": 4, "targets": [1378, 1382, 1384, 1385]},
	1381: {"name": "地牢一层西", "spawn_count": 3, "targets": [1379, 1383, 1445]},
	1382: {"name": "地牢一层北", "spawn_count": 4, "targets": [1380, 1383, 1451, 1386]},
	1383: {"name": "死亡棺材", "spawn_count": 7, "targets": [1381], "boss": "触龙神", "boss_respawn": 7200.0},
	1384: {"name": "铁灯笼屋", "spawn_count": 0, "targets": [1380, 1385]},
	1385: {"name": "紫水晶屋", "spawn_count": 0, "targets": [1384, 1386, 1380]},
	1386: {"name": "石墓小溪", "spawn_count": 0, "targets": [1385, 1387]},
	1387: {"name": "阴森石屋", "spawn_count": 0, "targets": [1386, 1388]},
	1388: {"name": "阴森石路", "spawn_count": 0, "targets": [1387, 1445, 1446, 1447, 1448]},
	1445: {"name": "黑暗地带", "spawn_count": 6, "targets": [1388, 1446, 1449, 1450, 1451], "boss": "邪恶钳虫", "boss_respawn": 3600.0},
	1446: {"name": "生死之间", "spawn_count": 6, "targets": [1445, 1447]},
	1447: {"name": "传奇部落", "spawn_count": 6, "targets": [1446, 1448]},
	1448: {"name": "邪恶势力", "spawn_count": 6, "targets": [1447, 1449]},
	1449: {"name": "幽名圣域", "spawn_count": 6, "targets": [1448, 1450]},
	1450: {"name": "恐怖空间", "spawn_count": 6, "targets": [1449, 1451]},
	1451: {"name": "一线天", "spawn_count": 6, "targets": [1450, 1382, 1378, 1544], "boss": "邪恶钳虫", "boss_respawn": 3600.0},
}

const ZUMA_MAPS := {
	659: {"name": "祖玛寺长廊", "spawn_count": 0, "targets": [478, 660, 665]},
	660: {"name": "祖玛寺庙一层", "spawn_count": 4, "targets": [659, 661, 659, 661]},
	661: {"name": "祖玛寺庙二层", "spawn_count": 4, "targets": [660, 662, 660, 662]},
	662: {"name": "祖玛寺庙三层", "spawn_count": 6, "targets": [661, 663]},
	663: {"name": "祖玛寺庙四层", "spawn_count": 7, "targets": [662, 664]},
	664: {"name": "祖玛寺庙五层", "spawn_count": 5, "targets": [663, 665]},
	665: {"name": "祖玛阁", "spawn_count": 5, "targets": [664, 674, 660, 665]},
	674: {"name": "祖玛神殿七层大厅", "spawn_count": 0, "targets": [665, 675]},
	675: {"name": "祖玛神殿七层", "spawn_count": 7, "targets": [674, 676]},
	676: {"name": "祖玛神殿七层", "spawn_count": 6, "targets": [675, 677]},
	677: {"name": "祖玛神殿七层", "spawn_count": 5, "targets": [676, 682]},
	682: {"name": "祖玛教主之家", "spawn_count": 1, "targets": [677], "boss": "祖玛教主", "boss_respawn": 10800.0},
}

const UNKNOWN_DARK_MAPS := {
	1544: {"name": "连接通道", "spawn_names": ["蜈蚣", "跳跳蜂", "巨型蠕虫", "钳虫", "蜈蚣", "跳跳蜂", "巨型蠕虫", "钳虫", "蜈蚣"], "targets": [1451, 1545, 1544, 1545], "npc": true},
	1545: {"name": "连接通道", "spawn_names": ["蜈蚣", "跳跳蜂", "巨型蠕虫", "钳虫", "蜈蚣", "跳跳蜂", "巨型蠕虫", "钳虫", "蜈蚣"], "targets": [1544, 1546]},
	1546: {"name": "连接通道", "spawn_names": ["蜈蚣", "跳跳蜂", "巨型蠕虫", "钳虫", "蜈蚣"], "targets": [1545, 1571]},
	1571: {"name": "未知暗殿", "spawn_names": ["稻草人1", "半兽勇士1", "骷髅精灵1", "沃玛卫士1", "沃玛教主1", "尸王1", "巨型多角虫1", "邪恶钳虫1", "白野猪1", "邪恶毒蛇1"], "targets": [1546]},
}

const FENGMO_MAPS := {
	3013: {"name": "封魔谷", "spawn_count": 6, "targets": [478, 3025], "bosses": ["千年树妖"], "boss_respawn": 3600.0},
	3025: {"name": "封魔矿区", "spawn_count": 5, "targets": [3013, 3026, 3027]},
	3026: {"name": "崎路", "spawn_count": 3, "targets": [3025, 3027, 3028, 3029]},
	3027: {"name": "连接通道", "spawn_count": 3, "targets": [3025, 3026, 3028]},
	3028: {"name": "封魔道", "spawn_count": 4, "targets": [3026, 3027, 3029, 3030]},
	3029: {"name": "疾风殿", "spawn_count": 4, "targets": [3028, 3030, 3031, 3029], "bosses": ["白野猪"], "boss_respawn": 3600.0},
	3030: {"name": "光芒回廊", "spawn_count": 4, "targets": [3029, 3031, 3032, 3033, 3030]},
	3031: {"name": "烈焰殿", "spawn_count": 6, "targets": [3030, 3032, 3033, 3034], "bosses": ["邪恶毒蛇"], "boss_respawn": 3600.0},
	3032: {"name": "雷霆之路", "spawn_count": 7, "targets": [3031, 3033]},
	3033: {"name": "霸者大厅", "spawn_count": 7, "targets": [3032, 3034], "bosses": ["白野猪"], "boss_respawn": 3600.0},
	3034: {"name": "幽冥回廊", "spawn_count": 6, "targets": [3033, 3035, 3036, 3034]},
	3035: {"name": "纵横道", "spawn_count": 6, "targets": [3034, 3036]},
	3036: {"name": "魔魂殿", "spawn_count": 4, "targets": [3035, 3037]},
	3037: {"name": "炼狱回廊", "spawn_count": 5, "targets": [3036, 3038, 3037, 3035]},
	3038: {"name": "封魔殿", "spawn_count": 4, "targets": [3037, 3013], "bosses": ["虹魔猪卫", "虹魔蝎卫", "虹魔教主"], "boss_respawn": 10800.0},
}

const RED_MOON_MAPS := {
	2863: {"name": "白日门", "spawn_count": 5, "targets": [478, 2934], "npcs": [
		{"name": "白日门杂货商", "kind": "shop", "stock": "general", "position": Vector2(-300, -250)},
		{"name": "白日门装备店", "kind": "shop", "stock": "mid_gear", "position": Vector2(300, -250)},
		{"name": "白日门书店", "kind": "shop", "stock": "books", "position": Vector2(120, 280)},
		{"name": "白日门武馆教头", "kind": "trainer", "position": Vector2(-120, 280)},
	]},
	2934: {"name": "丛林迷宫", "spawn_count": 6, "targets": [2863, 2935, 2936, 2937]},
	2935: {"name": "赤月峡谷北入口", "spawn_count": 5, "targets": [2934, 2938]},
	2936: {"name": "赤月峡谷南入口", "spawn_count": 7, "targets": [2934, 2938]},
	2937: {"name": "赤月峡谷东入口", "spawn_count": 5, "targets": [2934, 2938]},
	2938: {"name": "赤月峡谷广场", "spawn_count": 6, "targets": [2935, 2936, 2937, 2939, 2940]},
	2939: {"name": "左回廊", "spawn_count": 6, "targets": [2938, 2941]},
	2940: {"name": "右回廊", "spawn_count": 6, "targets": [2938, 2941]},
	2941: {"name": "抉择之地", "spawn_count": 7, "targets": [2939, 2940, 2942, 2943], "npcs": [
		{"name": "抉择之地商人", "kind": "shop", "stock": "general", "position": Vector2(0, 40)},
	]},
	2942: {"name": "山谷秘道", "spawn_count": 6, "targets": [2941, 2944, 2942]},
	2943: {"name": "山谷秘道", "spawn_count": 6, "targets": [2941, 2945]},
	2944: {"name": "恶魔祭坛", "spawn_count": 6, "targets": [2942], "bosses": ["双头血魔", "双头金刚"], "boss_respawn": 21600.0},
	2945: {"name": "赤月魔穴", "spawn_count": 6, "targets": [2943], "bosses": ["赤月恶魔"], "boss_respawn": 21600.0},
}

const CANGYUE_MAPS := {
	3165: {"name": "苍月岛", "monster_set": "surface", "spawn_count": 6, "targets": [478, 3195, 3216, 3245, 3288], "npcs": [
		{"name": "苍月杂货商", "kind": "shop", "stock": "general", "position": Vector2(-300, -250)},
		{"name": "苍月装备店", "kind": "shop", "stock": "mid_gear", "position": Vector2(300, -250)},
		{"name": "苍月书店", "kind": "shop", "stock": "books", "position": Vector2(120, 280)},
		{"name": "苍月武馆教头", "kind": "trainer", "position": Vector2(-120, 280)},
	]},
	3195: {"name": "尸魔洞一层", "monster_set": "corpse", "spawn_count": 7, "targets": [3165, 3196, 3195, 3196]},
	3196: {"name": "尸魔洞二层", "monster_set": "corpse", "spawn_count": 8, "targets": [3195, 3197, 3195, 3197, 3196, 3196]},
	3197: {"name": "尸魔洞三层", "monster_set": "corpse", "spawn_count": 8, "targets": [3196, 3165], "bosses": ["恶灵尸王"], "boss_respawn": 3600.0},
	3216: {"name": "骨魔洞一层", "monster_set": "bone", "spawn_count": 9, "targets": [3165, 3217, 3216, 3217]},
	3217: {"name": "骨魔洞二层", "monster_set": "bone", "spawn_count": 7, "targets": [3216, 3218, 3217]},
	3218: {"name": "骨魔洞三层", "monster_set": "bone", "spawn_count": 7, "targets": [3217, 3219, 3218]},
	3219: {"name": "骨魔洞四层", "monster_set": "bone", "spawn_count": 7, "targets": [3218, 3220]},
	3220: {"name": "骨魔洞五层", "monster_set": "bone", "spawn_count": 7, "targets": [3219], "bosses": ["黄泉教主"], "boss_respawn": 10800.0},
	3245: {"name": "牛魔寺庙入口", "monster_set": "cow", "spawn_count": 0, "targets": [3165, 3246, 3245, 3246]},
	3246: {"name": "牛魔寺庙一层", "monster_set": "cow", "spawn_count": 7, "targets": [3245, 3247, 3245, 3247]},
	3247: {"name": "牛魔寺庙二层", "monster_set": "cow", "spawn_count": 7, "targets": [3246, 3248, 3246, 3248]},
	3248: {"name": "牛魔寺庙三层", "monster_set": "cow", "spawn_count": 7, "targets": [3247, 3249, 3247, 3249]},
	3249: {"name": "牛魔寺庙四层", "monster_set": "cow", "spawn_count": 7, "targets": [3248, 3250, 3248, 3250, 3249, 3249, 3250, 3248]},
	3250: {"name": "牛魔寺庙五层", "monster_set": "cow", "spawn_count": 7, "targets": [3249, 3251, 3249, 3251]},
	3251: {"name": "牛魔寺庙六层", "monster_set": "cow", "spawn_count": 7, "targets": [3250, 3252, 3250, 3252]},
	3252: {"name": "牛魔寺庙大厅", "monster_set": "cow", "spawn_count": 8, "targets": [3251, 3165], "bosses": ["牛魔王"], "boss_respawn": 21600.0},
}

const FINAL_BASE_MAPS := {
	1488: {"name": "香石墓穴", "spawn_count": 6, "targets": [1183, 1489]},
	1489: {"name": "香石墓穴", "spawn_count": 12, "targets": [1488, 1490]},
	1490: {"name": "香石墓穴", "spawn_count": 6, "targets": [1489, 1183]},
	3288: {"name": "困惑殿堂", "spawn_count": 1, "targets": [3165, 3291], "bosses": ["暗之牛魔王"], "boss_respawn": 21600.0},
	3291: {"name": "地狱烈焰", "spawn_count": 1, "targets": [3288, 3294], "bosses": ["暗之双头血魔"], "boss_respawn": 21600.0},
	3294: {"name": "堕落坟场", "spawn_count": 1, "targets": [3291, 3297], "bosses": ["暗之黄泉教主"], "boss_respawn": 21600.0},
	3297: {"name": "死亡神殿", "spawn_count": 1, "targets": [3294, 3300], "bosses": ["暗之虹魔教主"], "boss_respawn": 21600.0},
	3300: {"name": "深渊魔域", "spawn_count": 1, "targets": [3297, 3303], "bosses": ["暗之双头金刚"], "boss_respawn": 21600.0},
	3303: {"name": "钳虫巢穴", "spawn_count": 1, "targets": [3300, 3165], "bosses": ["暗之骷髅精灵"], "boss_respawn": 21600.0},
}

const LATER_MAPS := {
	900001: {"name": "幻境一层", "spawn_count": 6, "targets": [478, 900002]},
	900002: {"name": "幻境二层", "spawn_count": 6, "targets": [900001, 900003]},
	900003: {"name": "幻境三层", "spawn_count": 6, "targets": [900002, 900004]},
	900004: {"name": "幻境四层", "spawn_count": 6, "targets": [900003, 900005], "bosses": ["白野猪"], "boss_respawn": 3600.0},
	900005: {"name": "幻境五层", "spawn_count": 6, "targets": [900004, 900006], "bosses": ["邪恶钳虫"], "boss_respawn": 3600.0},
	900006: {"name": "幻境六层", "spawn_count": 6, "targets": [900005, 900007], "bosses": ["沃玛教主"], "boss_respawn": 7200.0},
	900007: {"name": "幻境七层", "spawn_count": 6, "targets": [900006, 900008, 900011], "bosses": ["祖玛教主"], "boss_respawn": 10800.0},
	900008: {"name": "幻境八层", "spawn_count": 6, "targets": [900007, 900009], "bosses": ["黄泉教主"], "boss_respawn": 10800.0},
	900009: {"name": "幻境九层", "spawn_count": 6, "targets": [900008, 900010], "bosses": ["双头血魔", "双头金刚"], "boss_respawn": 21600.0},
	900010: {"name": "幻境十层", "spawn_count": 6, "targets": [900009, 478], "bosses": ["赤月恶魔"], "boss_respawn": 21600.0},
	900011: {"name": "幻境迷宫", "spawn_count": 6, "targets": [900007, 900012]},
	900012: {"name": "圣域", "spawn_count": 6, "targets": [900011], "bosses": ["暗之骷髅精灵"], "boss_respawn": 21600.0},
	900013: {"name": "沙巴克藏宝阁", "spawn_count": 8, "targets": [1183], "bosses": ["牛魔王", "虹魔教主"], "boss_respawn": 21600.0},
}

const DUNGEON_SPAWN_POSITIONS := [
	Vector2(-430, -220), Vector2(420, -210), Vector2(-330, 180), Vector2(320, 190),
	Vector2(0, -280), Vector2(-170, 260), Vector2(180, 250), Vector2(-90, 60), Vector2(110, -50), Vector2(0, 160),
]
const DUNGEON_PORTAL_POSITIONS := [Vector2(-620, 300), Vector2(620, -300), Vector2(-620, -300), Vector2(620, 300), Vector2(0, 340), Vector2(0, -340)]
const CENTIPEDE_MONSTERS := ["蜈蚣", "跳跳蜂", "巨型蠕虫", "钳虫"]
const ZUMA_MONSTERS := ["大老鼠", "楔蛾", "祖玛弓箭手", "祖玛雕像", "祖玛卫士"]
const FENGMO_MONSTERS := ["红野猪", "黑野猪", "楔蛾", "蝎蛇"]
const RED_MOON_MONSTERS := ["天狼蜘蛛", "花吻蜘蛛", "月魔蜘蛛", "黑锷蜘蛛", "钢牙蜘蛛", "幻影蜘蛛"]
const CANGYUE_SURFACE_MONSTERS := ["半兽勇士", "森林雪人", "钉耙猫", "多钩猫"]
const CORPSE_MONSTERS := ["恶灵僵尸", "恶灵尸王"]
const BONE_MONSTERS := ["骷髅锤兵", "骷髅长枪兵", "骷髅刀斧手", "骷髅弓箭手"]
const COW_MONSTERS := ["牛头魔", "牛魔战士", "牛魔斗士", "牛魔侍卫", "牛魔将军", "牛魔法师", "牛魔祭司"]
const SHIANGSHI_MONSTERS := ["僵尸1", "僵尸2", "僵尸3", "僵尸4", "恶灵僵尸"]
const LATER_MONSTERS := ["红野猪", "黑野猪", "祖玛卫士", "月魔蜘蛛", "牛魔将军", "恶灵尸王"]

const MONSTER_DROPS := {
	"骷髅": [
		{"name": "金币 200", "denominator": 2}, {"name": "金创药(小量)", "denominator": 5},
		{"name": "魔法药(小量)", "denominator": 6}, {"name": "回城卷", "denominator": 35},
		{"name": "乌木剑", "denominator": 60}, {"name": "青铜头盔", "denominator": 75},
	],
	"掷斧骷髅": [
		{"name": "金币 450", "denominator": 2}, {"name": "金创药(中量)", "denominator": 6},
		{"name": "回城卷", "denominator": 30}, {"name": "八荒", "denominator": 90}, {"name": "海魂", "denominator": 90},
	],
	"骷髅战士": [
		{"name": "金币 500", "denominator": 2}, {"name": "魔法药(中量)", "denominator": 6},
		{"name": "回城卷", "denominator": 28}, {"name": "半月", "denominator": 90}, {"name": "轻型盔甲(男)", "denominator": 80},
	],
	"骷髅战将": [
		{"name": "金币 1000", "denominator": 3}, {"name": "疗伤药", "denominator": 12},
		{"name": "回城卷", "denominator": 24}, {"name": "凌风", "denominator": 110}, {"name": "偃月", "denominator": 110}, {"name": "降魔", "denominator": 110},
	],
	"山洞蝙蝠": [{"name": "金币 200", "denominator": 3}, {"name": "魔法药(小量)", "denominator": 8}],
	"洞蛆": [{"name": "金币 200", "denominator": 3}, {"name": "金创药(小量)", "denominator": 8}],
	"蝎子": [{"name": "金币 200", "denominator": 3}, {"name": "金创药(小量)", "denominator": 7}],
	"僵尸1": [{"name": "金币 450", "denominator": 2}, {"name": "金创药(中量)", "denominator": 6}, {"name": "雷电术", "denominator": 180}],
	"僵尸2": [{"name": "金币 450", "denominator": 2}, {"name": "魔法药(中量)", "denominator": 6}, {"name": "召唤骷髅", "denominator": 180}],
	"僵尸3": [{"name": "金币 500", "denominator": 2}, {"name": "金创药(中量)", "denominator": 6}, {"name": "攻杀剑术", "denominator": 180}],
	"僵尸4": [{"name": "金币 500", "denominator": 2}, {"name": "魔法药(中量)", "denominator": 6}, {"name": "灵魂火符", "denominator": 180}],
	"僵尸5": [{"name": "金币 1000", "denominator": 4}, {"name": "回城卷", "denominator": 35}, {"name": "大火球", "denominator": 200}],
	"粪虫": [{"name": "金币 450", "denominator": 3}, {"name": "金创药(中量)", "denominator": 8}],
	"暗黑战士": [{"name": "金币 500", "denominator": 2}, {"name": "魔法药(中量)", "denominator": 7}, {"name": "回城卷", "denominator": 45}],
	"沃玛战士": [{"name": "金币 1000", "denominator": 3}, {"name": "强效金创药", "denominator": 10}, {"name": "炼狱", "denominator": 220}],
	"沃玛勇士": [{"name": "金币 1200", "denominator": 3}, {"name": "强效魔法药", "denominator": 10}, {"name": "魔杖", "denominator": 220}],
	"沃玛战将": [{"name": "金币 1500", "denominator": 3}, {"name": "太阳水", "denominator": 12}, {"name": "银蛇", "denominator": 220}],
	"火焰沃玛": [{"name": "金币 1500", "denominator": 3}, {"name": "强效太阳水", "denominator": 14}, {"name": "魔法盾", "denominator": 260}],
	"红蛇": [{"name": "金币 200", "denominator": 3}, {"name": "金创药(小量)", "denominator": 7}],
	"虎蛇": [{"name": "金币 200", "denominator": 3}, {"name": "魔法药(小量)", "denominator": 7}],
	"猎鹰": [{"name": "金币 450", "denominator": 3}, {"name": "回城卷", "denominator": 55}],
	"盔甲虫": [{"name": "金币 500", "denominator": 3}, {"name": "金创药(中量)", "denominator": 9}],
	"沙虫": [{"name": "金币 500", "denominator": 3}, {"name": "魔法药(中量)", "denominator": 9}],
	"红野猪": [{"name": "金币 1500", "denominator": 2}, {"name": "强效金创药", "denominator": 8}, {"name": "炼狱", "denominator": 260}],
	"黑野猪": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 8}, {"name": "魔杖", "denominator": 260}],
	"楔蛾": [{"name": "金币 1000", "denominator": 3}, {"name": "太阳水", "denominator": 10}, {"name": "圣言术", "denominator": 280}],
	"蝎蛇": [{"name": "金币 1500", "denominator": 2}, {"name": "强效太阳水", "denominator": 12}, {"name": "银蛇", "denominator": 260}],
	"蜜蜂": [{"name": "金币 500", "denominator": 3}, {"name": "金创药(中量)", "denominator": 10}],
	"蜈蚣": [{"name": "金币 1000", "denominator": 2}, {"name": "强效金创药", "denominator": 9}, {"name": "炼狱", "denominator": 300}],
	"跳跳蜂": [{"name": "金币 1000", "denominator": 2}, {"name": "强效魔法药", "denominator": 9}, {"name": "魔杖", "denominator": 300}],
	"巨型蠕虫": [{"name": "金币 1200", "denominator": 2}, {"name": "太阳水", "denominator": 10}, {"name": "银蛇", "denominator": 300}],
	"钳虫": [{"name": "金币 1500", "denominator": 2}, {"name": "强效太阳水", "denominator": 12}, {"name": "半月弯刀", "denominator": 320}],
	"大老鼠": [{"name": "金币 1000", "denominator": 2}, {"name": "强效金创药", "denominator": 10}],
	"祖玛弓箭手": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 10}, {"name": "骨玉权杖", "denominator": 600}],
	"祖玛雕像": [{"name": "金币 1500", "denominator": 2}, {"name": "强效太阳水", "denominator": 12}, {"name": "龙纹剑", "denominator": 600}],
	"祖玛卫士": [{"name": "金币 1500", "denominator": 2}, {"name": "疗伤药", "denominator": 15}, {"name": "裁决之杖", "denominator": 600}],
	"恶灵僵尸": [{"name": "金币 1500", "denominator": 2}, {"name": "强效金创药", "denominator": 10}],
	"恶灵尸王": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 10}],
	"骷髅锤兵": [{"name": "金币 1500", "denominator": 2}, {"name": "强效金创药", "denominator": 10}],
	"骷髅长枪兵": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 10}],
	"骷髅刀斧手": [{"name": "金币 1500", "denominator": 2}, {"name": "强效太阳水", "denominator": 12}],
	"骷髅弓箭手": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 10}],
	"牛头魔": [{"name": "金币 1500", "denominator": 2}, {"name": "强效金创药", "denominator": 10}],
	"牛魔战士": [{"name": "金币 1500", "denominator": 2}, {"name": "强效金创药", "denominator": 10}],
	"牛魔斗士": [{"name": "金币 1500", "denominator": 2}, {"name": "强效太阳水", "denominator": 12}],
	"牛魔侍卫": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 10}],
	"牛魔将军": [{"name": "金币 1500", "denominator": 2}, {"name": "疗伤药", "denominator": 18}],
	"牛魔法师": [{"name": "金币 1500", "denominator": 2}, {"name": "强效魔法药", "denominator": 9}],
	"牛魔祭司": [{"name": "金币 1500", "denominator": 2}, {"name": "疗伤药", "denominator": 18}],
}


static func has_map(map_id: int) -> bool:
	return WorldContent.has_map(map_id)


static func get_map_content(map_id: int) -> Dictionary:
	return WorldContent.map_content(map_id)
	# 下方构建代码只保留给离线导出工具追溯，运行时不再进入。
	@warning_ignore("unreachable_code")
	if MAPS.has(map_id):
		var content: Dictionary = MAPS[map_id].duplicate(true)
		if MINE_SOURCE_SIZES.has(map_id):
			content["source_size"] = MINE_SOURCE_SIZES[map_id]
			content["status"] = "client_map_full_size"
			_expand_compact_candidates(content)
		if content.has("source_size"):
			_project_source_positions(content)
		return content
	if CENTIPEDE_MAPS.has(map_id):
		return _build_centipede_content(map_id)
	if ZUMA_MAPS.has(map_id):
		return _build_compact_dungeon_content(map_id, ZUMA_MAPS, ZUMA_MONSTERS)
	if UNKNOWN_DARK_MAPS.has(map_id):
		return _build_unknown_dark_content(map_id)
	if FENGMO_MAPS.has(map_id):
		return _build_compact_dungeon_content(map_id, FENGMO_MAPS, FENGMO_MONSTERS)
	if RED_MOON_MAPS.has(map_id):
		return _build_compact_dungeon_content(map_id, RED_MOON_MAPS, RED_MOON_MONSTERS)
	if CANGYUE_MAPS.has(map_id):
		return _build_cangyue_content(map_id)
	if FINAL_BASE_MAPS.has(map_id):
		return _build_compact_dungeon_content(map_id, FINAL_BASE_MAPS, SHIANGSHI_MONSTERS)
	if LATER_MAPS.has(map_id):
		return _build_compact_dungeon_content(map_id, LATER_MAPS, LATER_MONSTERS)
	return {}


static func _project_source_positions(content: Dictionary) -> void:
	var source_size: Vector2i = content.get("source_size", Vector2i.ZERO)
	if source_size == Vector2i.ZERO:
		return
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		for entry: Dictionary in content.get(group_name, []):
			if entry.has("source_coordinate"):
				entry["position"] = MapCoordinateMapperScript.source_to_world(Vector2(entry.source_coordinate), source_size)
	if content.has("service_home_coordinate"):
		content["runtime_home_position"] = MapCoordinateMapperScript.source_to_world(Vector2(content.service_home_coordinate), source_size)


static func _expand_compact_candidates(content: Dictionary) -> void:
	var source_size: Vector2i = content.get("source_size", Vector2i.ZERO)
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		for entry: Dictionary in content.get(group_name, []):
			if entry.has("source_coordinate") or not entry.has("position"):
				continue
			entry["legacy_compact_position"] = entry.position
			entry["source_coordinate"] = MapCoordinateMapperScript.compact_candidate_to_source(entry.position, source_size)
			entry["source_confidence"] = "C"


static func _build_centipede_content(map_id: int) -> Dictionary:
	return _build_compact_dungeon_content(map_id, CENTIPEDE_MAPS, CENTIPEDE_MONSTERS)


static func _build_unknown_dark_content(map_id: int) -> Dictionary:
	var source: Dictionary = UNKNOWN_DARK_MAPS[map_id]
	var content := {"name": source.get("name", ""), "status": "structure_candidate", "spawns": [], "bosses": [], "npcs": [], "portals": []}
	var spawn_names: Array = source.get("spawn_names", [])
	for index in range(spawn_names.size()):
		var data_name := str(spawn_names[index])
		var monster := GameData.get_monster(data_name)
		content.spawns.append({"name": data_name, "display_name": str(monster.get("baseName", data_name)), "position": DUNGEON_SPAWN_POSITIONS[index % DUNGEON_SPAWN_POSITIONS.size()]})
	if bool(source.get("npc", false)):
		content.npcs.append({"name": "暗殿老人", "kind": "guide", "position": Vector2(0, 40)})
	var targets: Array = source.get("targets", [])
	for index in range(targets.size()):
		var target_id := int(targets[index])
		var target_data := GameData.get_map_by_id(target_id)
		content.portals.append({"target_map_id": target_id, "position": DUNGEON_PORTAL_POSITIONS[index % DUNGEON_PORTAL_POSITIONS.size()], "label": "前往%s" % target_data.get("name", "区域出口")})
	return content


static func _build_cangyue_content(map_id: int) -> Dictionary:
	var monster_set := str(CANGYUE_MAPS[map_id].get("monster_set", "surface"))
	var cycle: Array = CANGYUE_SURFACE_MONSTERS
	match monster_set:
		"corpse": cycle = CORPSE_MONSTERS
		"bone": cycle = BONE_MONSTERS
		"cow": cycle = COW_MONSTERS
	return _build_compact_dungeon_content(map_id, CANGYUE_MAPS, cycle)


static func _build_compact_dungeon_content(map_id: int, map_table: Dictionary, monster_cycle: Array) -> Dictionary:
	var source: Dictionary = map_table[map_id]
	var boss_names: Array = source.get("bosses", []).duplicate()
	var boss_name := str(source.get("boss", ""))
	if not boss_name.is_empty():
		boss_names.append(boss_name)
	var normal_count := maxi(0, int(source.get("spawn_count", 0)) - boss_names.size())
	var content := {"name": source.get("name", ""), "status": "structure_candidate", "spawns": [], "bosses": [], "npcs": source.get("npcs", []).duplicate(true), "portals": []}
	for index in range(normal_count):
		content.spawns.append({"name": monster_cycle[index % monster_cycle.size()], "position": DUNGEON_SPAWN_POSITIONS[index % DUNGEON_SPAWN_POSITIONS.size()]})
	for index in range(boss_names.size()):
		content.bosses.append({"name": str(boss_names[index]), "position": Vector2(230 - index * 230, 20 + index * 120), "respawn_seconds": float(source.get("boss_respawn", 3600.0))})
	var targets: Array = source.get("targets", [])
	for index in range(targets.size()):
		var target_id := int(targets[index])
		var target_data := GameData.get_map_by_id(target_id)
		content.portals.append({"target_map_id": target_id, "position": DUNGEON_PORTAL_POSITIONS[index % DUNGEON_PORTAL_POSITIONS.size()], "label": "前往%s" % target_data.get("name", "区域出口")})
	return content


static func get_monster_drops(monster_name: String) -> Array:
	return WorldContent.monster_drops(monster_name)
