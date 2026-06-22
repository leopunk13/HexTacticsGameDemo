## 六边形地块（等距视角版）
## 每个地块包含地形类型、坐标、占据单位等信息
## 等距视角下绘制扁平六边形 + 侧面厚度，模拟3D效果
extends Area2D
class_name HexTile

signal tile_clicked(tile: HexTile)
signal tile_hovered(tile: HexTile)

## 轴向坐标
var axial_coord: Vector2i = Vector2i.ZERO
## 地形类型
var terrain: int = HexUtils.TerrainType.GRASS

## 高亮类型
enum HighlightType { NONE, MOVE, ATTACK, SELECTED }
var highlight_type: int = HighlightType.NONE:
	set(v):
		highlight_type = v
		_update_visual()

## 占据该地块的单位
var occupying_unit: Unit = null

## 子节点引用
var polygon: Polygon2D       # 顶面
var outline: Line2D          # 顶面边框
var highlight_overlay: Polygon2D  # 高亮覆盖
var coord_label: Label       # 坐标标签
var side_polygons: Array[Polygon2D] = []  # 侧面多边形列表

## 地形高度
var terrain_height: float = 4.0

func _ready() -> void:
	#input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)

func setup(coord: Vector2i, terrain_type: int) -> void:
	axial_coord = coord
	terrain = terrain_type
	terrain_height = HexUtils.TERRAIN_HEIGHT.get(terrain, 4.0)
	position = HexUtils.axial_to_pixel(coord.x, coord.y)
	#_draw_hex()
	_update_visual()

## 更新视觉表现
func _update_visual() -> void:
	pass
	#if polygon == null:
		#return
	#for coord in HexGrids.tiles:
		#match HexGrids.tiles[coord].highlight_type:
			#HighlightType.NONE:
				#HexGrids.tiles[coord].highlight_overlay.color = Color.TRANSPARENT
			#HighlightType.MOVE:
				#HexGrids.tiles[coord].highlight_overlay.color = Color(0.2, 0.6, 1.0, 0.35)
			#HighlightType.ATTACK:
				#HexGrids.tiles[coord].highlight_overlay.color = Color(1.0, 0.2, 0.2, 0.35)
			#HighlightType.SELECTED:
				#HexGrids.tiles[coord].highlight_overlay.color = Color(1.0, 1.0, 0.2, 0.4)
	

## 获取移动消耗
func get_move_cost() -> int:
	return HexUtils.TERRAIN_MOVE_COST.get(terrain, 1)

## 是否可通行
func is_passable() -> bool:
	return get_move_cost() < 999

## 是否被占据
func is_occupied() -> bool:
	return occupying_unit != null

## 获取等距视角下的排序Y值
func get_sort_y() -> float:
	return HexUtils.get_sort_y(axial_coord)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		DebugLog.debug_nospam("participant_turn",true)
		tile_clicked.emit(self)

func _on_mouse_entered() -> void:
	tile_hovered.emit(self)
