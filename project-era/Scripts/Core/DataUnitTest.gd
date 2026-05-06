extends SceneTree

# 这是一个极其简单的测试脚本，不需要 UI，直接通过命令行输出验证数据逻辑
func _init() -> void:
	print("--- Project ERA: Data Logic Unit Test ---")
	
	# 测试 1：对数经验槽测试
	var dummy = CharacterData.new()
	print("Level 1 Exp Cap: ", dummy.get_exp_cap_for_level(1))
	print("Level 20 Exp Cap: ", dummy.get_exp_cap_for_level(20))
	print("Level 80 Exp Cap: ", dummy.get_exp_cap_for_level(80))
	
	# 测试 2：正向升级测试 (一次性输入海量经验)
	print("\n--- Test: Positive Training (Level Up) ---")
	dummy.add_exp("yuri_obedience", 1500)
	print("Added 1500 Exp to yuri_obedience.")
	print("Current Level: ", dummy.stats["yuri_obedience"]["level"])
	print("Remaining Exp: ", dummy.stats["yuri_obedience"]["exp"])
	
	# 测试 3：负向降级测试 (教养/禁欲)
	print("\n--- Test: Reverse Training (Level Down) ---")
	dummy.reduce_exp("yuri_obedience", 300)
	print("Reduced 300 Exp from yuri_obedience.")
	print("Current Level: ", dummy.stats["yuri_obedience"]["level"])
	print("Remaining Exp: ", dummy.stats["yuri_obedience"]["exp"])
	
	# 测试 4：极端降级测试 (归零测试)
	print("\n--- Test: Extreme Reverse (Drop to 0) ---")
	dummy.reduce_exp("yuri_obedience", 9999)
	print("Reduced 9999 Exp from yuri_obedience.")
	print("Current Level: ", dummy.stats["yuri_obedience"]["level"])
	print("Remaining Exp: ", dummy.stats["yuri_obedience"]["exp"])
	
	# 测试 5：Mod 加载器测试
	print("\n--- Test: Mod Manager ---")
	var manager = CharacterManager.new()
	manager.load_external_characters()
	
	# 手动造一个测试 Mod
	var mod_dir = "res://Mods/Characters/TestMod"
	DirAccess.make_dir_recursive_absolute(mod_dir)
	var test_json = """
	{
		"id": "char_test_01",
		"name": "Miku",
		"description": "A test character.",
		"base_stats_init": { "shame": 90, "lust": 5 },
		"custom_tags": ["怕黑", "虚拟歌姬"]
	}
	"""
	var file = FileAccess.open(mod_dir + "/character_data.json", FileAccess.WRITE)
	file.store_string(test_json)
	file.close()
	
	print("Scanning again after creating test Mod...")
	manager.load_external_characters()
	
	var miku = manager.get_character("char_test_01")
	if miku:
		print("Loaded Character Name: ", miku.char_name)
		print("Loaded Character Shame Level: ", miku.stats["shame"]["level"])
		print("Loaded Character Tags: ", miku.custom_tags)
	
	print("\n--- Test Completed ---")
	quit()
