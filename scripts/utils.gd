extends Node
## 工具类 - 提供公共的纹理生成、特效和屏幕震动功能

# 缓存已生成的纹理，避免重复创建
var _circle_texture_cache: Dictionary = {}
var _light_texture: ImageTexture = null


func get_circle_texture(radius: float, color: Color) -> ImageTexture:
	var key := str(radius) + "_" + color.to_html()
	if _circle_texture_cache.has(key):
		return _circle_texture_cache[key]

	var image := Image.create(int(radius * 2), int(radius * 2), false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				var alpha := 1.0 - (dist / radius)
				image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))

	var texture := ImageTexture.create_from_image(image)
	_circle_texture_cache[key] = texture
	return texture


func get_light_texture() -> ImageTexture:
	if _light_texture:
		return _light_texture

	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				var alpha := 1.0 - (dist / radius)
				image.set_pixel(x, y, Color(1, 1, 1, alpha))

	_light_texture = ImageTexture.create_from_image(image)
	return _light_texture


## 在指定位置生成伤害数字
func spawn_damage_number(parent: Node, amount: float, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = str(int(amount)) if amount > 0 else "LEVEL UP!"
	label.position = pos + Vector2(randf_range(-20, 20), -30)
	label.z_index = 100
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)

	var tween := parent.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 50, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


## 屏幕震动
func screen_shake(camera: Camera2D, intensity: float) -> void:
	if not camera:
		return
	var original_offset := camera.offset
	var tween := camera.create_tween()
	for i in range(6):
		tween.tween_property(camera, "offset", original_offset + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity, 0.05)
	tween.tween_property(camera, "offset", original_offset, 0.05)


## 创建一个圆形特效精灵并自动消失
func spawn_circle_effect(parent: Node, pos: Vector2, radius: float, color: Color, duration: float = 0.3, target_scale: float = 1.5, z: int = 10) -> void:
	var effect := Sprite2D.new()
	effect.texture = get_circle_texture(radius, color)
	effect.position = pos
	effect.z_index = z
	parent.add_child(effect)

	var tween := parent.create_tween()
	tween.tween_property(effect, "scale", Vector2(target_scale, target_scale), duration)
	tween.parallel().tween_property(effect, "modulate:a", 0.0, duration)
	tween.tween_callback(effect.queue_free)
