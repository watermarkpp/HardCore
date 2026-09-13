extends Node

## Local attribute links, never external URLs or data-supplied executable text.
const TouchScroll := preload("res://scripts/touch_scroll_support.gd")
const ENTRIES := {
	"等级": "人物当前等级。升级所需经验随等级变化。",
	"穿戴重量": "当前已穿戴装备的重量／角色可承受的穿戴负重上限。",
	"攻击": "决定物理攻击的伤害范围。下限与上限之间的实际取值还会受到幸运或诅咒影响，命中后再计算目标防御。",
	"魔法": "法师技能使用的魔法攻击力。具体伤害还由技能等级、技能公式和目标魔防共同决定。",
	"道术": "道士技能使用的道术能力。影响相关技能的伤害或效果，具体按该技能规则计算。",
	"防御": "减少受到的物理伤害。每次命中会在防御下限与上限之间取值，再参与伤害结算。",
	"魔防": "减少受到的魔法伤害。成功躲避的攻击不会再进入魔防结算。",
	"准确": "提高物理攻击命中目标的机会，与目标敏捷共同判定；不增加攻击伤害数值。",
	"敏捷": "提高避开物理攻击的机会，与攻击者准确共同判定。",
	"幸运": "提高攻击力取到上限的机会。武器上的幸运与诅咒互斥；祝福油作用于当前武器。",
	"诅咒": "提高攻击力取到下限的机会。武器上的诅咒与幸运互斥；祝福油改善武器时会先抵消诅咒。",
	"速度": "影响物理攻击和法术施放的快慢。速度 +1 时，普通攻击间隔由 900 毫秒变为 840 毫秒；法师、道士的施法动作、释放点和再次施法间隔按相同比例缩短。负值会减慢速度。",
	"施法速度": "影响再次施法的间隔。装备上的“速度”还会同步影响施法动作与释放时机。",
	"强度": "减少武器攻击时的耐久消耗，让武器更耐用。强度不会增加攻击伤害，也不直接增加耐久上限。",
	"远程与魔法躲避": "有概率避开远程物理攻击、投射物和魔法伤害，包括范围魔法。一次命中只判定一次；躲避成功时不承受该次伤害或附带效果。普通近战物理攻击仍由准确和敏捷判定。",
	"毒物躲避": "降低部分怪物麻痹等毒性控制的命中机会。按攻击本身的规则结算，并非对所有持续中毒伤害直接按显示百分比减伤。",
	"耐久": "当前耐久／耐久上限。战斗会消耗耐久，维修可恢复耐久；随机持久增加装备生成时的耐久上限，与减少消耗的“强度”不同。",
	"生命": "增加生命值上限。生命耗尽会死亡；恢复药品显示的是实际恢复的生命量。",
	"魔法值": "增加施放技能所用的魔法值上限。恢复药品显示的是实际恢复的魔法量。",
	"暴击": "提高触发暴击的机会，暴击造成的额外伤害由暴击伤害属性和战斗规则决定。",
	"暴击伤害": "影响成功暴击时造成的额外伤害，不提高暴击发生的机会。",
	"技能等级": "提高对应技能的有效等级，具体效果按该技能规则结算。",
	"重量": "物品或装备的负重。背包负重、穿戴负重和手持负重分别按相应规则检查。",
	"穿戴要求": "穿戴这件装备必须满足的等级或属性条件，同时还需满足装备的职业、性别和负重限制。",
	"类别": "物品所属类型，决定使用方式或可穿戴部位。小极品允许追加的属性还会按具体装备类型进一步限制。",
	"部位": "这件装备当前对应的穿戴位置。随机追加属性受装备类型限制，不是每个位置都能出现所有属性。",
	"数量": "当前物品堆叠的数量。每件装备实例的属性和耐久单独保存。",
}
const ALIASES := {"攻击速度":"速度", "魔法躲避":"远程与魔法躲避", "魔法闪避":"远程与魔法躲避"}
static var _pattern: RegEx
var label: RichTextLabel
var host: Control
var _layer: CanvasLayer
var _bubble: Panel
var _copy: RichTextLabel
var active_attribute := ""
var explanation_resolver := Callable()
var _anchor := Vector2.ZERO
var _host_rect := Rect2()


static func decorate(body: String) -> String:
	if _pattern == null:
		var terms: Array = ENTRIES.keys() + ALIASES.keys()
		# Longest first prevents “魔法” matching “魔法值” and similar labels.
		terms.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
		_pattern = RegEx.new()
		_pattern.compile("(" + "|".join(terms) + ")(上限|下限)?(?=[ ：:+\\-0-9])")
	# Do not alter BBCode tags or text which is already a local link.
	if body.contains("[url="): return body
	var result := ""
	var cursor := 0
	for match: RegExMatch in _pattern.search_all(body):
		var begin := match.get_start()
		if body.rfind("[", begin) > body.rfind("]", begin): continue
		result += body.substr(cursor, begin - cursor)
		var term := match.get_string(1)
		result += "[url=attribute:%s][color=#8dbce8][u]%s[/u][/color][/url]" % [str(ALIASES.get(term, term)), match.get_string()]
		cursor = match.get_end()
	return result + body.substr(cursor)


static func attach(owner: Control, text_label: RichTextLabel) -> Node:
	var script := load("res://scripts/item_attribute_help.gd") as GDScript
	var helper: Node = script.new()
	helper.name = "AttributeHelp"
	helper.host = owner
	helper.label = text_label
	owner.add_child(helper)
	return helper


func _ready() -> void:
	set_process_input(false)
	label.meta_clicked.connect(_on_meta_clicked)
	label.gui_input.connect(_on_label_input)
	label.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: dismiss())
	host.visibility_changed.connect(dismiss)
	host.item_rect_changed.connect(func() -> void:
		if not active_attribute.is_empty() and not host.get_global_rect().is_equal_approx(_host_rect): dismiss()
	)


func _on_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_anchor = label.get_global_transform_with_canvas() * event.position
	elif event is InputEventScreenTouch and event.pressed:
		_anchor = label.get_global_transform_with_canvas() * event.position


func _on_meta_clicked(meta: Variant) -> void:
	if TouchScroll.is_drag_active(get_tree()) or not host.is_visible_in_tree(): return
	var value := str(meta)
	if not value.begins_with("attribute:"): return
	var term := value.trim_prefix("attribute:")
	if not ENTRIES.has(term): return
	if active_attribute == term:
		dismiss()
		return
	_ensure_bubble()
	active_attribute = term
	_host_rect = host.get_global_rect()
	var explanation := str(ENTRIES[term])
	if explanation_resolver.is_valid():
		var resolved: String = explanation_resolver.call(term)
		if not resolved.is_empty(): explanation = resolved
	_copy.text = term + "\n" + explanation
	var viewport_rect := host.get_viewport_rect().grow(-10.0)
	var width := minf(300.0, viewport_rect.size.x)
	_copy.size = Vector2(maxf(1.0, width - 24.0), 1.0)
	var text_height := float(_copy.get_content_height())
	_copy.size.y = minf(text_height, viewport_rect.size.y - 24.0)
	_copy.scroll_active = text_height > _copy.size.y
	_copy.get_v_scroll_bar().hide()
	_bubble.size = Vector2(width, _copy.size.y + 24.0)
	_position_bubble()
	_bubble.show()
	set_process_input(true)


func _position_bubble() -> void:
	if _bubble == null or active_attribute.is_empty(): return
	var viewport_rect := host.get_viewport_rect().grow(-10.0)
	var position := _anchor + Vector2(16, 16)
	if position.y + _bubble.size.y > viewport_rect.end.y:
		position.y = _anchor.y - _bubble.size.y - 12.0
	position.x = clampf(position.x, viewport_rect.position.x, maxf(viewport_rect.position.x, viewport_rect.end.x - _bubble.size.x))
	position.y = clampf(position.y, viewport_rect.position.y, maxf(viewport_rect.position.y, viewport_rect.end.y - _bubble.size.y))
	_bubble.position = position


func _ensure_bubble() -> void:
	if _bubble != null: return
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_bubble = Panel.new()
	_bubble.name = "AttributeExplanation"
	# The same underlined attribute remains clickable even if the explanation
	# overlays its row near a viewport edge.
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color("17110af5")
	box.border_color = Color("c6a25d")
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	for edge: String in ["left", "right", "top", "bottom"]: box.set("content_margin_" + edge, 12.0)
	_bubble.add_theme_stylebox_override("panel", box)
	_layer.add_child(_bubble)
	_bubble.resized.connect(_position_bubble)
	_copy = RichTextLabel.new()
	_copy.position = Vector2(12,12)
	_copy.scroll_active = false
	_copy.bbcode_enabled = false
	_copy.fit_content = false
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_copy.add_theme_font_size_override("normal_font_size", 15)
	_copy.add_theme_color_override("default_color", Color("ead9b9"))
	_copy.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_copy)


func dismiss() -> void:
	active_attribute = ""
	if _bubble != null: _bubble.hide()
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		dismiss()
