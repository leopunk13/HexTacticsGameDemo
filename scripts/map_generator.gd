extends Node2D
class_name MapGenerator

var terrain_dict = {}
var terrain_types = {}

var polygon: Polygon2D       # 顶面
var outline: Line2D          # 顶面边框
var highlight_overlay: Polygon2D  # 高亮覆盖
var coord_label: Label       # 坐标标签
## 地形高度
var terrain_height: float = 4.0

@export_dir var terrains_folder_path = "res://prefabs/terrains"
@export_file var terrains_dict_path = "res://prefabs/terrains/terrains.json"
@export_file var map_file_path = "res://scenes/maps/map01.csv"
@export_file var map_saved_path = "res://scenes/maps/map01.tscn"


const RANDOM_SEED = 24

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	seed(RANDOM_SEED)
	#读取terrains字典
	var json_text: String = FileAccess.get_file_as_string(terrains_dict_path)
	if json_text.is_empty():
		push_error("terrains.json 读取失败: %s" % terrains_dict_path)
		return
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		push_error("terrains.json 解析失败: %s (行 %d)" % [json.get_error_message(), json.get_error_line()])
		return
	var terrains_dicts: Dictionary = json.data
	for key in terrains_dicts:
		var index = int(key)
		terrain_dict[index] = []
		terrain_types[index] = terrains_dicts[key]["type"]
		for terrain_path in terrains_dicts[key]["terrains"]:
			var terrain_res_path = terrains_folder_path + "/" + terrain_path + ".tscn"
			var terrain_res := load(terrain_res_path)
			terrain_dict[index].append(terrain_res)
	generate_map_from_file(map_file_path)


func generate_map_from_file(file_path):
	#创建一个文件读取对象
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file.is_open():
		DebugLog.debug_nospam("read_file",false)
		return
	
	var map_data = []
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0].length() > 0:
			map_data.append(line)
			
	file.close()
	
	var map_size_x = map_data[0].size()
	var map_size_y = map_data.size()
	
	# 计算地图的起始位置，使中心点处于世界原点
	var start_x = -map_size_x / 2
	var start_y = -map_size_y / 2

	# 遍历地图数据并生成地图
	for y in range(map_size_y):
		for x in range(map_size_x):
			if map_data[y][x] == '#':
				continue
			var terrain_type = int(map_data[y][x])
			if terrain_type in terrain_dict:
				var rand_index:int = randi() % terrain_dict[terrain_type].size()
				var terrain_instance =  terrain_dict[terrain_type][rand_index].instantiate()
				# axial_to_pixel 返回 Vector2（像素坐标），变量类型必须匹配
				var pixel_pos: Vector2 = HexUtils.axial_to_pixel((start_x + x), (start_y + y))
				terrain_instance.transform.origin = pixel_pos
				terrain_instance.set_name("{0}_{1}_{2}".format([terrain_types[terrain_type],y,x]))
				add_child(terrain_instance)
				terrain_instance.set_owner(self)

				# _create_tile 需要 Vector2i（轴向坐标）作为 key，不能传 Vector2
				var axial_coord: Vector2i = Vector2i((start_x + x), (start_y + y))
				HexGrids._create_tile(axial_coord, terrain_type)

				# 坐标标签
				var label: Label = Label.new()
				label.add_theme_font_size_override("font_size", 8)
				label.modulate = Color(1, 1, 1, 0.4)
				coord_label = label
				# === 坐标标签 ===
				if coord_label:
					coord_label.text = "%d,%d" % [(start_x + x), (start_y + y)]
					coord_label.position = Vector2(pixel_pos.x-15, pixel_pos.y-6 - terrain_height)
				add_child(label)
				
				
	#save_scene_as_file(map_saved_path)

func save_scene_as_file(path):
	var scene = PackedScene.new()
	var result = scene.pack(self)
	
	if result == OK:
		var error = ResourceSaver.save(scene, path)
		if error != OK:
			push_error("将场景保存到磁盘时出错。")
		else:
			print("保存场景成功：{0}".format([path]))
