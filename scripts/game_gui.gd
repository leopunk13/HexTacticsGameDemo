extends Control

signal new_game_requested
## 请求保存到指定槽位（0~5）
signal save_requested(slot: int)
## 请求从指定槽位读取（0~5）
signal load_requested(slot: int)
## 请求重试战斗
signal retry_battle_requested
## 请求返回主菜单（MAINMENU按钮）
signal main_menu_requested
## 请求继续游戏（CONTINUE按钮，载入最新存档）
signal continue_game_requested

@onready var main_menu: NinePatchRect = $MainMenu
@onready var new_container: VBoxContainer = $MainMenu/NewContainer
@onready var continue_container: VBoxContainer = $MainMenu/ContinueContainer
@onready var resume_container: VBoxContainer = $MainMenu/ResumeContainer
@onready var settings_menu: GridContainer = $SettingsMenu
@onready var save_load_panel: Panel = $"Save&LoadPanel"
@onready var save_list: VBoxContainer = $"Save&LoadPanel/ScrollContainer/SaveList"

@onready var new_game_btn: Button = %NewGameBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var quit_btn: Button = %QuitBtn
# ContinueContainer 下的按钮（与 NewContainer 同名但属于另一个容器）
@onready var continue_new_game_btn: Button = $MainMenu/ContinueContainer/NewGameBtn
@onready var continue_settings_btn: Button = $MainMenu/ContinueContainer/SettingsBtn
@onready var continue_quit_btn: Button = $MainMenu/ContinueContainer/QuitBtn

@onready var resume_game_btn: Button = $MainMenu/ResumeContainer/ResumeGameBtn
@onready var save_btn: Button = $MainMenu/ResumeContainer/SaveBtn
@onready var load_btn: Button = $MainMenu/ResumeContainer/LoadBtn
@onready var retry_battle_btn: Button = $MainMenu/ResumeContainer/RetryBattleBtn
@onready var main_menu_btn: Button = $MainMenu/ResumeContainer/MainMenuBtn
@onready var resume_quit_btn: Button = $MainMenu/ResumeContainer/QuitBtn
@onready var continue_game_btn: Button = $MainMenu/ContinueContainer/ContinueGameBtn

## 当前模式：SAVE 或 LOAD，决定点击 SaveSlot 时的行为
enum Mode { NONE, SAVE, LOAD }
var _current_mode: int = Mode.NONE

## 6 个存档槽位节点（SaveSlot Panel 实例）
var _save_slots: Array = []

var has_saved_game: bool = false
## 是否已进入游戏模式（点击 NEW GAME 后为 true）
var is_in_game: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 1.绑定按钮信号（NewContainer 下的按钮）
	new_game_btn.pressed.connect(_on_new_game_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	# ContinueContainer 下的按钮（重复按钮，连接相同的处理函数）
	continue_new_game_btn.pressed.connect(_on_new_game_pressed)
	continue_settings_btn.pressed.connect(_on_settings_pressed)
	continue_quit_btn.pressed.connect(_on_quit_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	resume_game_btn.pressed.connect(_on_resume_pressed)
	retry_battle_btn.pressed.connect(_on_retry_battle_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	resume_quit_btn.pressed.connect(_on_quit_pressed)
	continue_game_btn.pressed.connect(_on_continue_game_pressed)
	# 2.收集 SaveSlot 节点并连接 pressed 信号
	_collect_save_slots()
	# 3.检测是否存在存档，决定是否显示 ContinueContainer
	_check_has_saved_game()
	# 4.显示主菜单MainMenu
	show_main_menu(has_saved_game)


## 检测是否存在任何存档
func _check_has_saved_game() -> void:
	for i in range(SaveManager.MAX_SLOTS):
		if SaveManager.has_slot_data(i):
			has_saved_game = true
			return
	has_saved_game = false


## 收集 SaveList 下的 6 个 SaveSlot 并连接信号
func _collect_save_slots() -> void:
	_save_slots.clear()
	for i in range(1, 7):
		var slot_node: Panel = save_list.get_node_or_null("SaveSlot%d" % i)
		if slot_node:
			_save_slots.append(slot_node)
			# 连接 SaveSlot 的 pressed 信号
			if not slot_node.pressed.is_connected(_on_save_slot_pressed):
				slot_node.pressed.connect(_on_save_slot_pressed)


## 刷新存档槽位显示（根据槽位是否有存档更新标签）
func refresh_save_slots() -> void:
	for i in range(_save_slots.size()):
		var slot_node: Panel = _save_slots[i]
		var save_data: SaveData = SaveManager.load_from_slot(i)
		if save_data:
			slot_node.set_save_data(save_data)
		else:
			slot_node.set_save_data(null)


func show_main_menu(has_saved_game: bool) -> void:
	main_menu.visible = true
	resume_container.visible = false
	if has_saved_game:
		new_container.visible = false
		continue_container.visible = true
	else:
		new_container.visible = true
		continue_container.visible = false
		#设置焦点为NewGameBtn
		new_game_btn.grab_focus()
	settings_menu.visible = false
	save_load_panel.visible = false


## 显示暂停菜单（游戏中按 ESC 调用）
## 显示 ResumeContainer 下的按钮，隐藏 NewContainer 和 ContinueContainer
func show_pause_menu() -> void:
	main_menu.visible = true
	resume_container.visible = true
	new_container.visible = false
	continue_container.visible = false
	settings_menu.visible = false
	save_load_panel.visible = false
	resume_game_btn.grab_focus()


## 隐藏暂停菜单（恢复游戏）
func hide_pause_menu() -> void:
	main_menu.visible = false
	settings_menu.visible = false
	save_load_panel.visible = false


## 暂停菜单是否正在显示
func is_pause_menu_visible() -> bool:
	return main_menu.visible and is_in_game


func _on_new_game_pressed() -> void:
	# 开始新游戏：清除所有已有存档文件
	SaveManager.clear_all_saves()
	has_saved_game = false
	is_in_game = true
	new_game_requested.emit()


func _on_settings_pressed() -> void:
	settings_menu.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


## 点击 SAVE 按钮：显示存档列表，隐藏主菜单
func _on_save_pressed() -> void:
	_current_mode = Mode.SAVE
	main_menu.visible = false
	refresh_save_slots()
	save_load_panel.visible = true


## 点击 LOAD 按钮：显示读档列表，隐藏主菜单
func _on_load_pressed() -> void:
	_current_mode = Mode.LOAD
	main_menu.visible = false
	refresh_save_slots()
	save_load_panel.visible = true


## 点击 RESUME 按钮：隐藏菜单，恢复游戏
func _on_resume_pressed() -> void:
	hide_pause_menu()


## 点击 RETRYBATTLE 按钮：发出重试信号
func _on_retry_battle_pressed() -> void:
	retry_battle_requested.emit()


## 点击 MAINMENU 按钮：发出返回主菜单信号
func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()


## 点击 CONTINUE 按钮：发出继续游戏信号
func _on_continue_game_pressed() -> void:
	continue_game_requested.emit()


## 点击某个 SaveSlot 时调用
func _on_save_slot_pressed(panel: Panel) -> void:
	# 获取槽位索引
	var slot_index: int = _save_slots.find(panel)
	if slot_index < 0:
		return
	match _current_mode:
		Mode.SAVE:
			save_requested.emit(slot_index)
		Mode.LOAD:
			load_requested.emit(slot_index)
	# 操作完成后关闭存档面板
	_current_mode = Mode.NONE
	save_load_panel.visible = false
