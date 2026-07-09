extends Control

signal new_game_requested

@onready var main_menu: NinePatchRect = $MainMenu
@onready var new_container: VBoxContainer = $MainMenu/NewContainer 
@onready var settings_menu: GridContainer = $SettingsMenu
@onready var save_load_panel: Panel = $"Save&LoadPanel"

@onready var new_game_btn: Button = %NewGameBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var quit_btn: Button = %QuitBtn

var has_saved_game: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 1.绑定按钮信号
	new_game_btn.pressed.connect(_on_new_game_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	# 2.添加按钮按下后的音效——TODO
	# 3.显示主菜单MainMenu
	show_main_menu(has_saved_game)


func show_main_menu(has_saved_game: bool) -> void:
	main_menu.visible = true
	if has_saved_game:
		new_container.visible = false
	else:
		new_container.visible = true
		#设置焦点为NewGameBtn
		new_game_btn.grab_focus()
	settings_menu.visible = false
	save_load_panel.visible = false


func _on_new_game_pressed() -> void:
	new_game_requested.emit()


func _on_settings_pressed() -> void:
	settings_menu.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()
