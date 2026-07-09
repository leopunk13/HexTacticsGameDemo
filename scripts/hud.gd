extends CanvasLayer
## HUD界面 - 血条、法力条、技能栏、波次信息
@onready var skill_bar: HBoxContainer = $BottomPanel/SkillBar
@onready var controls: RichTextLabel = $Controls
@onready var game_menu: Control = %GameMenu
@onready var bottom_panel: Panel = $BottomPanel


var unit_info_panel: PanelContainer
var unit_name_label: Label
var unit_hp_label: Label
var unit_stats_label: Label

var skill_cooldown_overlays: Array = []
var player: CharacterBody2D

var skill_names: Dictionary = {1: "旋风斩", 2: "火球术", 3: "地裂击", 4: "暗影冲"}
var skill_colors: Dictionary = {
	1: Color(0.5, 0.8, 1.0),
	2: Color(1.0, 0.4, 0.1),
	3: Color(0.6, 0.3, 0.1),
	4: Color(0.3, 0.1, 0.5),
}


func _ready() -> void:
	# 不要用 XXX.new() 覆盖 @onready 节点引用，否则操作的是脱离场景树的新实例
	# 场景中的真实节点（$BottomPanel 等）会保持原状不受控
	show_game_menu()
	bottom_panel.visible = false
	controls.visible = false
	# 单位信息面板
	unit_info_panel = PanelContainer.new()
	unit_info_panel.name = "UnitInfoPanel"
	unit_info_panel.custom_minimum_size = Vector2(0, 60)
	unit_info_panel.visible = false
	
	var info_hbox: HBoxContainer = HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 20)

	# 左侧留白
	var info_left: Control = Control.new()
	info_left.custom_minimum_size = Vector2(20, 0)
	info_hbox.add_child(info_left)

	unit_name_label = Label.new()
	unit_name_label.name = "UnitName"
	unit_name_label.add_theme_font_size_override("font_size", 16)
	unit_name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	info_hbox.add_child(unit_name_label)

	unit_hp_label = Label.new()
	unit_hp_label.name = "UnitHP"
	unit_hp_label.add_theme_font_size_override("font_size", 14)
	unit_hp_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	info_hbox.add_child(unit_hp_label)

	unit_stats_label = Label.new()
	unit_stats_label.name = "UnitStats"
	unit_stats_label.add_theme_font_size_override("font_size", 13)
	unit_stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	info_hbox.add_child(unit_stats_label)
	#hide_unit_info()
	## 等待场景就绪后绑定玩家
	#await get_tree().process_frame
	#_bind_player()


func show_skill_bar() -> void:
	skill_bar.visible = true
	# 初始化技能栏样式
	for i in range(4):
		var skill_panel: Panel = get_node("BottomPanel/SkillBar/Skill" + str(i + 1))
		var style := StyleBoxFlat.new()
		style.bg_color = skill_colors[i + 1]
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		skill_panel.add_theme_stylebox_override("panel", style)

		var overlay: ColorRect = skill_panel.get_node("CooldownOverlay")
		skill_cooldown_overlays.append(overlay)

func hide_skill_bar() -> void:
	skill_bar.visible = false

func show_game_menu() -> void:
	game_menu.visible = true
	
func hide_game_menu() -> void:
	game_menu.visible = false

func _bind_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		#player.health_changed.connect(_on_health_changed)
		#player.mana_changed.connect(_on_mana_changed)
		player.level_up.connect(_on_level_up)
		player.skill_used.connect(_on_skill_used)


func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return

	_update_skill_cooldowns()

	# 从游戏世界获取波次信息
	var game_world := get_tree().get_first_node_in_group("game_world")


## 显示单位信息
func show_unit_info(unit: Unit) -> void:
	unit_info_panel.visible = true
	var team_str: String = "玩家" if unit.team == Unit.Team.PLAYER else "敌方"
	unit_name_label.text = "[%s] %s" % [team_str, unit.unit_name]
	unit_hp_label.text = "HP: %d/%d" % [unit.health, unit.max_health]
	unit_stats_label.text = "ATK:%d DEF:%d MOV:%d RNG:%d" % [unit.attack_damage, unit.armor_class, unit.move_range, unit.attack_range]

## 隐藏单位信息
func hide_unit_info() -> void:
	unit_info_panel.visible = false

func _update_skill_cooldowns() -> void:
	for i in range(4):
		var cooldown: float = player.skill_cooldowns[i + 1]
		var max_cd: float = player.skill_max_cooldowns[i + 1]
		#var overlay: ColorRect = skill_cooldown_overlays[i]
		#if cooldown > 0:
			#overlay.visible = true
			#var ratio := cooldown / max_cd
			#overlay.offset_top = 60 * (1.0 - ratio)
		#else:
			#overlay.visible = false


#func _on_health_changed(current: float, maximum: float) -> void:
	#health_bar.value = (current / maximum) * 100
	#health_label.text = str(int(current)) + " / " + str(int(maximum))
#
#
#func _on_mana_changed(current: float, maximum: float) -> void:
	#mana_bar.value = (current / maximum) * 100
	#mana_label.text = str(int(current)) + " / " + str(int(maximum))


func _on_level_up(new_level: int) -> void:
	# 升级闪烁效果
	var flash := ColorRect.new()
	flash.size = Vector2(250, 80)
	flash.color = Color(1, 1, 0.5, 0.3)
	flash.z_index = 10
	$TopPanel.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.5)
	tween.tween_callback(flash.queue_free)


func _on_skill_used(slot: int) -> void:
	# 技能使用闪烁
	var skill_panel: Panel = get_node("BottomPanel/SkillBar/Skill" + str(slot))
	var flash := ColorRect.new()
	flash.size = Vector2(60, 60)
	flash.color = Color(1, 1, 1, 0.5)
	skill_panel.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)
