extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://assets/data/service_reference.json"
	assert(FileAccess.file_exists(path), "服务端参考文件不存在")
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "服务端参考文件无法打开")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "服务端参考文件不是有效JSON")
	var reference: Dictionary = parsed
	var setup: Dictionary = reference.get("serviceSetup", {})
	assert(int(setup.get("HomeMap", -1)) == 0 and int(setup.get("HomeX", -1)) == 289 and int(setup.get("HomeY", -1)) == 618, "出生点未对齐服务端!Setup")
	assert(int(setup.get("RedHomeMap", -1)) == 3 and int(setup.get("RedHomeX", -1)) == 845 and int(setup.get("RedHomeY", -1)) == 674, "红名回城点未对齐服务端!Setup")
	assert(int(setup.get("HitIntervalTime", 0)) == 600, "服务端普攻间隔参考值未记录")
	assert(int(setup.get("MagicHitIntervalTime", 0)) == 600 and int(setup.get("MagicAttackRage", 0)) == 8, "服务端魔法参数未记录")
	var runtime_exp: Dictionary = reference.get("serviceRuntimeExpTableLevel1To60", {})
	assert(int(runtime_exp.get("1", 0)) == 100 and int(runtime_exp.get("22", 0)) == 300000 and int(runtime_exp.get("40", 0)) == 12000000, "服务端运行时经验表未从源码默认表固化")
	var override: Dictionary = reference.get("policyOverrides", {}).get("normalAttackIntervalMs", {})
	assert(int(override.get("serviceReference", 0)) == 600 and int(override.get("currentMobileDesign", 0)) == 850, "手机普攻间隔覆盖决策未记录")
	var missing_count := 0
	for _key: Variant in reference.get("requiredServerTables", {}).keys():
		var info: Dictionary = reference.requiredServerTables[_key]
		if str(info.get("status", "")) == "missing":
			missing_count += 1
	assert(missing_count == 8, "当前服务端Envir/DB缺口数量记录不符")
	var project_tables: Dictionary = reference.get("projectTables", {})
	assert(int(project_tables.get("maps", {}).get("rows", 0)) == 142, "地图表行数审计不符")
	assert(int(project_tables.get("monsters", {}).get("rows", 0)) == 217, "怪物表行数审计不符")
	assert(int(project_tables.get("bosses", {}).get("rows", 0)) == 46, "Boss表行数审计不符")
	assert(int(project_tables.get("items", {}).get("rows", 0)) == 175, "装备表行数审计不符")
	assert(int(project_tables.get("skills", {}).get("rows", 0)) == 132, "技能表行数审计不符")
	assert(int(project_tables.get("drops", {}).get("rows", 0)) == 3424, "掉落表行数审计不符")
	print("SERVICE_DATA_REFERENCE_PASS：服务端!Setup参数、缺失DB清单、七张项目表审计和手机普攻覆盖决策均已固化")
	get_tree().quit(0)
