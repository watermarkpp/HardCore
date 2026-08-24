extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	# This is a procedural fallback presentation test, not a world boot test.
	# Keep it detached so headless runs do not initialize map textures or depend
	# on an unmapped name-only EnemyActor that the ID-only runtime would reject.
	var fallback_actor := EnemyActor.new()
	fallback_actor.monster_id = 21
	fallback_actor.monster_data = {"monster_id": 21}
	fallback_actor.display_name = "动画测试占位怪"
	fallback_actor.facing = Vector2.RIGHT
	var fallback_visual := MonsterVisual.new()
	fallback_visual.setup(fallback_actor)
	fallback_actor.visual = fallback_visual
	fallback_visual._resource_residency_timer = 999.0
	assert(fallback_actor.monster_id > 0, "占位攻击夹具必须携带正的canonical monster_id")
	assert(not fallback_visual.uses_final_art(), "占位攻击夹具不应启动客户端图集")
	fallback_visual.play_attack(0.46)
	fallback_visual._process(0.12)
	assert(fallback_visual.is_fallback_attacking(), "占位怪攻击前摇未启动")
	assert(fallback_visual.fallback_lunge_offset_px(fallback_actor.facing).length() >= 7.0, "占位怪扑击位移不可见")
	assert(fallback_visual.fallback_attack_progress() > 0.0, "占位怪攻击进度未推进")
	fallback_visual._process(0.40)
	assert(not fallback_visual.is_fallback_attacking(), "占位怪攻击动作没有按时结束")
	fallback_visual.free()
	fallback_actor.free()
	print("PLACEHOLDER_ATTACK_PASS：占位怪前摇、12像素扑击与方向挥击反馈正常")
	get_tree().quit(0)
