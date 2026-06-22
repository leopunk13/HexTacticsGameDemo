## 六边形坐标工具类
## 使用轴向坐标系 (axial coordinates) 和立方体坐标系 (cube coordinates)
## 支持等距斜视（Isometric）视角 —— 类似 Those Who Rule 的视角风格
class_name HexUtils

const SQRT3: float = 1.7320508075688772

## 六边形大小（外接圆半径）
const HEX_SIZE: float = 50.0

## 等距视角Y轴压缩比（模拟从斜上方俯视的效果）
## 值越小，视角越平（越接近侧面）；值越大，越接近正俯视
## Those Who Rule 风格约为 0.55-0.65
const ISOMETRIC_Y_RATIO: float = 0.98

## 地形类型枚举
enum TerrainType {
	GRASS,    ## 平原
	FOREST,    ## 森林
	WATER,     ## 水域
}



## 地形厚度（等距视角下的视觉高度，像素）
const TERRAIN_HEIGHT: Dictionary = {
	TerrainType.GRASS: 4.0,
	TerrainType.FOREST: 6.0,
	TerrainType.WATER: 2.0,
}

## 地形移动消耗
const TERRAIN_MOVE_COST: Dictionary = {
	TerrainType.GRASS: 1,
	TerrainType.FOREST: 2,
	TerrainType.WATER: 999,  # 不可通行
}

## 地形防御加成
const TERRAIN_DEFENSE_BONUS: Dictionary = {
	TerrainType.GRASS: 0,
	TerrainType.FOREST: 2,
	TerrainType.WATER: 0,
}

## 六边形6个方向的轴向坐标偏移（pointy-top）
const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),   # 右
	Vector2i(1, -1),  # 右上
	Vector2i(0, -1),  # 左上
	Vector2i(-1, 0),  # 左
	Vector2i(-1, 1),  # 左下
	Vector2i(0, 1),   # 右下
]

## 轴向坐标转像素坐标（等距视角 pointy-top）
## X方向不变，Y方向压缩以模拟斜视效果
static func axial_to_pixel(q: int, r: int) -> Vector2:
	var x: float = HEX_SIZE * (SQRT3 * q + SQRT3 / 2.0 * r)
	var y: float = HEX_SIZE * (3.0 / 2.0 * r) * ISOMETRIC_Y_RATIO
	return Vector2(x, y)

## 像素坐标转轴向坐标（等距视角 pointy-top）
## 需要先将Y轴还原再计算
static func pixel_to_axial(px: float, py: float) -> Vector2i:
	# 还原Y轴压缩
	var real_y: float = py / ISOMETRIC_Y_RATIO
	var q: float = (SQRT3 / 3.0 * px - 1.0 / 3.0 * real_y) / HEX_SIZE
	var r: float = (2.0 / 3.0 * real_y) / HEX_SIZE
	return axial_round(q, r)

## 轴向坐标四舍五入到最近的六边形
static func axial_round(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: int = roundi(q)
	var rr: int = roundi(r)
	var rs: int = roundi(s)

	var q_diff: float = absf(rq - q)
	var r_diff: float = absf(rr - r)
	var s_diff: float = absf(rs - s)

	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs

	return Vector2(rq, rr)

## 获取两个轴向坐标之间的距离
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.x + a.y - b.x - b.y) + absi(a.y - b.y)) / 2

## 获取相邻的6个六边形坐标
static func hex_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dir in HEX_DIRECTIONS:
		neighbors.append(coord + dir)
	return neighbors

## 生成立方体坐标的s分量
static func cube_s(q: int, r: int) -> int:
	return -q - r

## 获取六边形的顶点（等距视角 pointy-top，Y轴压缩）
## 用于绘制扁平的等距六边形
static func hex_corners(center: Vector2, size: float = HEX_SIZE) -> PackedVector2Array:
	var corners: PackedVector2Array = []
	for i in range(6):
		var angle_deg: float = 60.0 * i - 30.0
		var angle_rad: float = deg_to_rad(angle_deg)
		#corners.append(Vector2(
			#center.x + size * cos(angle_rad),
			#center.y + size * sin(angle_rad) * ISOMETRIC_Y_RATIO
		#))
		corners.append(Vector2(
			center.x + size * cos(angle_rad),
			center.y + size * sin(angle_rad) * ISOMETRIC_Y_RATIO
		))
	return corners

## 获取六边形顶面顶点（带高度偏移，用于等距视角的3D效果）
static func hex_top_corners(center: Vector2, size: float, height: float) -> PackedVector2Array:
	var offset_center: Vector2 = Vector2(center.x , center.y - height*8)
	return hex_corners(offset_center, size)

## 获取六边形侧面顶点（底边两个点 + 顶面对应两个点）
## 返回4个点构成侧面四边形，side_index: 0-5 对应6条边
static func hex_side_quad(center: Vector2, size: float, height: float, side_index: int) -> PackedVector2Array:
	var top_corners: PackedVector2Array = hex_top_corners(center, size, height)
	var bottom_corners: PackedVector2Array = hex_corners(center, size)

	var i1: int = side_index
	var i2: int = (side_index + 1) % 6

	# 只绘制朝下的边（Y值较大的边，即面向观察者的边）
	var quad: PackedVector2Array = PackedVector2Array()
	quad.append(bottom_corners[i1])
	quad.append(bottom_corners[i2])
	quad.append(top_corners[i2])
	quad.append(top_corners[i1])
	return quad

## 判断某条边是否朝向观察者（在等距视角下可见）
## 等距视角下，只有底部的边（Y值较大的边）需要绘制侧面
static func is_side_visible(side_index: int) -> bool:
	# pointy-top六边形，边0-5从右开始顺时针
	# 等距视角下可见的侧面：底部3条边（索引3,4,5对应左、左下、右下）
	# 实际上需要看边的朝向：底半部分的边可见
	match side_index:
		2, 3, 4:  # 左上、左、左下 —— 等距视角下朝向观察者的边
			return true
		_:
			return false

## 获取等距视角下的排序Y值（用于深度排序）
## Y值越大的对象越靠前（越靠近观察者）
static func get_sort_y(coord: Vector2i) -> float:
	return axial_to_pixel(coord.x, coord.y).y
