class_name CharacterManager
extends Node

# 全局角色名单，Key 是 char_id (String), Value 是 CharacterData 对象
var roster: Dictionary = {}

# 加载外部图包和角色设定的主目录
# "user://" 代表系统的 AppData 目录，适合发布后玩家自行添加 (PC端)
var mods_dir_path: String = "user://Mods/Characters" 

# ---------------------------------------------------------
# 1. 增删改查基础功能
# ---------------------------------------------------------
func add_character(char_data: CharacterData) -> void:
	if roster.has(char_data.id):
		push_warning("Character ID already exists, overwriting: " + char_data.id)
	roster[char_data.id] = char_data
	print("Character added: ", char_data.char_name)

func get_character(char_id: String) -> CharacterData:
	return roster.get(char_id)

func remove_character(char_id: String) -> void:
	if roster.erase(char_id):
		print("Character removed: ", char_id)

func get_all_characters() -> Array[CharacterData]:
	var list: Array[CharacterData] = []
	for key in roster:
		list.append(roster[key])
	return list

# ---------------------------------------------------------
# 2. 外部 Mod 角色包动态加载 (Runtime Loading)
# 支持玩家手写 JSON 并在外部加载立绘，实现高扩展性
# ---------------------------------------------------------
func load_external_characters() -> void:
	print("Scanning for external characters in: ", mods_dir_path)
	
	var dir = DirAccess.open(mods_dir_path)
	if dir == null:
		push_warning("Mods directory not found or cannot be opened. Creating one...")
		DirAccess.make_dir_recursive_absolute(mods_dir_path)
		_create_template_file()
		return
		
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and folder_name != "." and folder_name != "..":
			_load_character_from_folder(mods_dir_path + "/" + folder_name)
		folder_name = dir.get_next()
		
func _load_character_from_folder(folder_path: String) -> void:
	var json_path = folder_path + "/character_data.json"
	
	if not FileAccess.file_exists(json_path):
		return # 没有 JSON 配置则跳过
		
	var file = FileAccess.open(json_path, FileAccess.READ)
	var json_string = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error == OK:
		var data = json.data
		var new_char = CharacterData.new()
		# 因为外部 JSON 格式可能比较自由，这里做一层安全的映射解析
		if data.has("id"): new_char.id = data["id"]
		if data.has("name"): new_char.char_name = data["name"]
		if data.has("description"): new_char.description = data["description"]
		if data.has("custom_tags"):
			for tag in data["custom_tags"]:
				new_char.custom_tags.append(String(tag))
				
		# 解析初始硬指标
		if data.has("base_stats_init"):
			var init_stats = data["base_stats_init"]
			for key in init_stats.keys():
				if new_char.stats.has(key):
					new_char.stats[key]["level"] = int(init_stats[key])
					new_char.stats[key]["exp"] = 0
		
		# 注册到全局名单
		add_character(new_char)
		print("Successfully loaded Mod Character: ", new_char.char_name)
		
		# TODO: 在此处可以继续补充加载 avatar.png 图片文件的逻辑，供 UI 调用
	else:
		push_error("JSON Parse Error in " + json_path + " at line " + str(json.get_error_line()))

func _create_template_file() -> void:
	# 创建一个基础的模板文件，方便不会代码的玩家照猫画虎
	var template_path = mods_dir_path + "/ExampleChar"
	DirAccess.make_dir_recursive_absolute(template_path)
	var file = FileAccess.open(template_path + "/character_data.json", FileAccess.WRITE)
	if file:
		var json_str = """{
  "id": "custom_01",
  "name": "自建角色示例",
  "base_stats_init": {
	"shame": 90,
	"lust": 10,
	"devotion": 0,
	"yuri_obedience": 50,
	"edging_control": 20,
	"sensory_B": 10,
	"sensory_A": 0,
	"sensory_V": 0,
	"sensory_C": 0,
	"sensory_M": 10,
	"exhibitionism": 0,
	"semen_addiction": 0
  },
  "custom_tags": [
	"这里可以随便写任意文字",
	"比如：黑皮辣妹",
	"对主人有隐藏的好感"
  ]
}"""
		file.store_string(json_str)
		file.close()
		print("Created Example Character template at: ", template_path)

# ---------------------------------------------------------
# 3. 提供给 LLM / Simulation Engine 批量调用的接口
# ---------------------------------------------------------
func apply_stat_change(char_id: String, stat_key: String, change_amount: int) -> void:
	var char_data = get_character(char_id)
	if char_data:
		if change_amount > 0:
			char_data.add_exp(stat_key, change_amount)
		elif change_amount < 0:
			char_data.reduce_exp(stat_key, abs(change_amount))
			
func inject_exclusive_memory(char_ids: Array, memory_text: String) -> void:
	for c_id in char_ids:
		var char_data = get_character(c_id)
		if char_data:
			char_data.exclusive_memories.append(memory_text)
			print("Injected secret memory to ", char_data.char_name)
