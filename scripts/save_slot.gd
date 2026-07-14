extends Panel

signal pressed(panel: Panel)

## 当前存档数据
var save_data: SaveData = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Line2D.hide()
	_update_label()


## 设置存档数据并更新显示
func set_save_data(data: SaveData) -> void:
	save_data = data
	_update_label()


## 更新标签显示
func _update_label() -> void:
	var label: Label = $Label
	if save_data != null:
		label.text = save_data.title
	else:
		label.text = "EMPTY"


func _on_mouse_entered() -> void:
	$Line2D.show()


func _on_mouse_exited() -> void:
	$Line2D.hide()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(self)
