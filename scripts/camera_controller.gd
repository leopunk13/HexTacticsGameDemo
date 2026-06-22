## 俯视相机控制器（等距视角适配版）
## 支持WASD/方向键移动、鼠标滚轮缩放、鼠标边缘滚动
extends Camera2D
class_name CameraController

## 移动速度
@export var move_speed: float = 400.0
## 缩放范围
@export var zoom_min: Vector2 = Vector2(0.4, 0.4)
@export var zoom_max: Vector2 = Vector2(2.0, 2.0)
## 缩放步进
@export var zoom_step: float = 0.1
## 边缘滚动区域宽度
@export var edge_scroll_margin: int = 20
## 是否启用边缘滚动
@export var edge_scroll_enabled: bool = true

## 地图边界
var map_bounds: Rect2 = Rect2(-500, -400, 1000, 800)

func _process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO

	# 键盘移动
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1

	# 边缘滚动
	if edge_scroll_enabled:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		if mouse_pos.x < edge_scroll_margin:
			input_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
			input_dir.x += 1
		if mouse_pos.y < edge_scroll_margin:
			input_dir.y -= 1
		elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
			input_dir.y += 1

	if input_dir != Vector2.ZERO:
		position += input_dir.normalized() * move_speed * delta / zoom.x
		# 限制在地图边界内
		position.x = clampf(position.x, map_bounds.position.x, map_bounds.end.x)
		position.y = clampf(position.y, map_bounds.position.y, map_bounds.end.y)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = zoom + Vector2(zoom_step, zoom_step)
			zoom = zoom.clamp(zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = zoom - Vector2(zoom_step, zoom_step)
			zoom = zoom.clamp(zoom_min, zoom_max)

## 聚焦到指定位置
func focus_on(target_pos: Vector2) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", target_pos, 0.3).set_ease(Tween.EASE_OUT)

## 设置地图边界
func set_map_bounds(bounds: Rect2) -> void:
	map_bounds = bounds
