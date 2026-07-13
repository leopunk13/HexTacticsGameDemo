## 六边形网格管理器（等距视角版）
## 负责生成和管理整个六边形地图
## 支持Y排序以实现正确的深度遮挡
extends Node2D
class_name HexGrid

## 地图半径（六边形地图的环数）
@export var map_radius: int = 6
## 随机地形种子
@export var terrain_seed: int = 42

## 所有地块的字典，键为轴向坐标 Vector2i
var tiles: Dictionary = {}

signal tile_clicked(tile: HexTile)
signal tile_hovered(tile: HexTile)

func _ready() -> void:
	# 启用Y排序，确保等距视角下深度正确
	y_sort_enabled = true
	#generate_map()

## 集中处理地块点击：用 pixel_to_axial 精确定位唯一点击地块
## 避免每个 HexTile 各自判定导致相邻地块同时 emit tile_clicked
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		var mouse_pos: Vector2 = get_global_mouse_position()
		var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
		var tile: HexTile = get_tile(clicked_coord)
		if tile != null:
			tile_clicked.emit(tile)

## 生成六边形地图
func generate_map() -> void:
	_clear_map()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = terrain_seed

	# 收集所有坐标，按Y值排序以正确绘制
	var all_coords: Array[Vector2i] = []
	for q in range(-map_radius, map_radius + 1):
		for r in range(-map_radius, map_radius + 1):
			var s: int = -q - r
			if absi(s) <= map_radius:
				all_coords.append(Vector2i(q, r))

	# 按等距视角Y值排序（从远到近绘制）
	all_coords.sort_custom(func(a, b): return HexUtils.get_sort_y(a) < HexUtils.get_sort_y(b))


## 创建单个地块
func _create_tile(coord: Vector2i, terrain_type: int) -> void:
	var tile: HexTile = _make_tile_instance(coord)
	tile.setup(coord, terrain_type)
	tile.tile_clicked.connect(_on_hex_tile_tile_clicked)
	tile.tile_hovered.connect(_on_tile_hovered)
	add_child(tile)
	tiles.set(coord,tile)

## 创建地块实例（等距视角版）
func _make_tile_instance(coord: Vector2i) -> HexTile:
	var tile: HexTile = HexTile.new()
	# 碰撞区域 - 使用顶面形状
	# Area2D 需要 CollisionPolygon2D 子节点才能触发 mouse_entered 信号，
	# 进而驱动 tile_hovered 信号链（用于伤害预览等悬停功能）
	# visible=false 隐藏默认的红色碰撞调试绘制，不影响碰撞检测
	var collision: CollisionPolygon2D = CollisionPolygon2D.new()
	var top_corners: PackedVector2Array = HexUtils.hex_top_corners(
		Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
	)
	collision.polygon = top_corners
	collision.visible = false
	tile.add_child(collision)
	## 多边形 - 直接赋值引用
	#var poly: Polygon2D = Polygon2D.new()
	#tile.polygon = poly
	#tile.add_child(poly)
	## 边框
	#var line: Line2D = Line2D.new()
	#tile.outline = line
	#tile.add_child(line)
	# 高亮层
	var highlight: Polygon2D = Polygon2D.new()
	highlight.polygon = PackedVector2Array(top_corners)
	highlight.position = HexUtils.axial_to_pixel(coord.x, coord.y)
	highlight.color = Color.TRANSPARENT
	highlight.z_index = 1
	highlight.offset = Vector2(0,4)
	tile.highlight_overlay = highlight
	tile.highlight_type = HexTile.HighlightType.NONE
	#if tile.highlight_overlay:
		#tile.highlight_overlay.color = Color(0.2, 0.6, 1.0, 0.35)
	add_child(highlight)
	
	## 坐标标签
	#var label: Label = Label.new()
	#label.add_theme_font_size_override("font_size", 8)
	#label.modulate = Color(1, 1, 1, 0.4)
	#tile.coord_label = label
	#tile.add_child(label)
	return tile

## 清除地图
func _clear_map() -> void:
	for child in get_children():
		child.queue_free()
	tiles.clear()

## 获取指定坐标的地块
func get_tile(coord: Vector2i) -> HexTile:
	var tile: HexTile = tiles.get(coord, null)
	return tile

## 判断某格是否处于敌方单位的控制区域内（ZOC）
## ZOC = 敌方单位相邻的6个格子，进入敌方ZOC后必须停止移动
func is_in_enemy_zoc(coord: Vector2i, friendly_team: int) -> bool:
	for neighbor_coord in HexUtils.hex_neighbors(coord):
		var tile: HexTile = get_tile(neighbor_coord)
		if tile != null and tile.is_occupied() and tile.occupying_unit.team != friendly_team:
			return true
	return false

## 获取可移动范围内的所有地块（BFS）
func get_reachable_tiles(start: Vector2i, move_range: int) -> Dictionary:
	# 返回 {coord: cost} 的字典
	var reachable: Dictionary = {}
	var visited: Dictionary = {}
	var start_tile: HexTile = get_tile(start)
	var friendly_team: int = -1
	if start_tile and start_tile.occupying_unit:
		friendly_team = start_tile.occupying_unit.team
	var queue: Array = [{"coord": start, "cost": 0}]
	visited[start] = 0

	while queue.size() > 0:
		var current: Dictionary = queue.pop_front()
		var current_coord: Vector2i = current["coord"]
		var current_cost: int = current["cost"]

		if current_cost > 0:  # 不包含起点
			reachable[current_coord] = current_cost

		# ZOC检查：非起点且处于敌方ZOC内时，可到达但不再继续扩展
		if current_coord != start and is_in_enemy_zoc(current_coord, friendly_team):
			continue

		for neighbor_coord in HexUtils.hex_neighbors(current_coord):
			var tile = get_tile(neighbor_coord)
			if tile == null or not tile.is_passable():
				continue
			if tile.is_occupied() and tile.occupying_unit.team != friendly_team:
				continue  # 敌方单位阻挡
			var new_cost: int = current_cost + tile.get_move_cost()
			if new_cost <= move_range:
				if not visited.has(neighbor_coord) or visited[neighbor_coord] > new_cost:
					visited[neighbor_coord] = new_cost
					queue.append({"coord": neighbor_coord, "cost": new_cost})
					queue.sort_custom(func(a, b): return a["cost"] < b["cost"])

	return reachable

## 获取攻击范围内的所有地块
## 未移动时：显示当前位置可直接攻击 + 移动后可攻击的所有敌方单位（移动+攻击威胁范围）
## 已移动时：仅显示当前位置可直接攻击的敌方单位
func get_attackable_tiles(start: Vector2i, attack_range: int, friendly_team: int, is_moved: bool, move_range: int) -> Array[Vector2i]:
	var attackable: Array[Vector2i] = []
	# 待检查的起点集合：当前位置 + （未移动时）所有可移动到达的地块
	var origins: Array[Vector2i] = [start]
	if not is_moved and move_range > 0:
		var reachable: Dictionary = get_reachable_tiles(start, move_range)
		for coord in reachable:
			origins.append(coord)
	# 对每个起点，收集攻击范围内的敌方单位
	for origin in origins:
		for coord in tiles:
			if coord == start:
				continue
			if HexUtils.hex_distance(origin, coord) <= attack_range:
				var tile: HexTile = tiles[coord]
				if tile == null:
					continue
				if tile.is_occupied() and tile.occupying_unit.team != friendly_team:
					if not attackable.has(coord):
						attackable.append(coord)
	return attackable

## 找到攻击目标的最优移动位置（移动消耗最少且在攻击范围内）
## 若当前位置直接可攻击，返回 start；否则在可移动范围内寻找最优位置
func find_best_attack_position(start: Vector2i, target_coord: Vector2i, attack_range: int, move_range: int) -> Vector2i:
	# 当前位置直接可攻击
	if HexUtils.hex_distance(start, target_coord) <= attack_range:
		return start
	var reachable: Dictionary = get_reachable_tiles(start, move_range)
	var best_pos: Vector2i = start
	var best_cost: int = 999
	for coord in reachable:
		if HexUtils.hex_distance(coord, target_coord) <= attack_range:
			var cost: int = reachable[coord]
			if cost < best_cost:
				best_cost = cost
				best_pos = coord
	return best_pos

## 清除所有高亮
func clear_highlights() -> void:
	for coord in tiles:
		var tile: HexTile = tiles[coord]
		tile.highlight_type = HexTile.HighlightType.NONE
		if tile.highlight_overlay != null and is_instance_valid(tile.highlight_overlay):
			tile.highlight_overlay.color = Color.TRANSPARENT

## 高亮移动范围
func highlight_move_range(start: Vector2i, move_range: int) -> void:
	var reachable: Dictionary = get_reachable_tiles(start, move_range)
	for coord in reachable:
		var tile: HexTile = get_tile(coord)
		if tile:
			tile.highlight_type = HexTile.HighlightType.MOVE

## 高亮攻击范围
func highlight_attack_range(start: Vector2i, attack_range: int, friendly_team: int, is_moved: bool, move_range: int) -> void:
	var attackable: Array[Vector2i] = get_attackable_tiles(start, attack_range, friendly_team, is_moved, move_range)
	for coord in attackable:
		var tile: HexTile = get_tile(coord)
		if tile:
			tile.highlight_type = HexTile.HighlightType.ATTACK

## 获取从start到target的路径（A*寻路）
func find_path(start: Vector2i, target: Vector2i, max_cost: int = 999) -> Array[Vector2i]:
	if start == target:
		return []

	var friendly_team: int = -1
	var start_tile: HexTile = get_tile(start)
	if start_tile and start_tile.occupying_unit:
		friendly_team = start_tile.occupying_unit.team

	var open_set: Array = [{"coord": start, "g": 0, "f": HexUtils.hex_distance(start, target)}]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}

	while open_set.size() > 0:
		open_set.sort_custom(func(a, b): return a["f"] < b["f"])
		var current: Dictionary = open_set.pop_front()
		var current_coord: Vector2i = current["coord"]

		if current_coord == target:
			var path: Array[Vector2i] = []
			var c: Variant = target
			while c != start:
				path.append(c)
				c = came_from[c]
			path.reverse()
			return path

		# ZOC检查：非起点且处于敌方ZOC内时，不继续扩展路径
		if current_coord != start and is_in_enemy_zoc(current_coord, friendly_team):
			continue

		for neighbor_coord in HexUtils.hex_neighbors(current_coord):
			var tile: HexTile = get_tile(neighbor_coord)
			if tile == null or not tile.is_passable():
				continue
			var tentative_g: int = current["g"] + tile.get_move_cost()
			if tentative_g > max_cost:
				continue
			if not g_score.has(neighbor_coord) or tentative_g < g_score[neighbor_coord]:
				g_score[neighbor_coord] = tentative_g
				came_from[neighbor_coord] = current_coord
				var f: int = tentative_g + HexUtils.hex_distance(neighbor_coord, target)
				open_set.append({"coord": neighbor_coord, "g": tentative_g, "f": f})

	return []

#func _on_tile_clicked(tile: HexTile) -> void:
	#tile_clicked.emit(tile)

func _on_tile_hovered(tile: HexTile) -> void:
	tile_hovered.emit(tile)


func _on_hex_tile_tile_clicked(tile: HexTile) -> void:
	tile_clicked.emit(tile)
