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
	
	# 测试 6：推演引擎连招测试
	print("\n--- Test: Simulation Engine Task Sequence ---")
	var engine = SimulationEngine.new()
	
	var chise = CharacterData.new()
	chise.char_name = "Chise"
	chise.stats["shame"]["level"] = 50 # 设定较高的初始羞耻心
	chise.stats["edging_control"]["level"] = 5 # 给一点寸止能力
	
	var hina = CharacterData.new()
	hina.char_name = "Hina_Instructor"
	
	# 构造一个一上午的调教连招序列
	var morning_actions: Array[Dictionary] = [
		{"name": "爱抚", "type": SimulationEngine.CommandType.ICE_BREAK, "target_part": "sensory_C"},
		{"name": "舔阴", "type": SimulationEngine.CommandType.ICE_BREAK, "target_part": "sensory_C"},
		{"name": "揉胸", "type": SimulationEngine.CommandType.ICE_BREAK, "target_part": "sensory_B"},
		{"name": "手指插入", "type": SimulationEngine.CommandType.NORMAL, "target_part": "sensory_V"},
		{"name": "允许高潮", "type": SimulationEngine.CommandType.FINISHER}
	]
	
	var logs = engine.process_task_sequence(chise, hina, morning_actions)
	for l in logs:
		print(l)
		
	print("\n结算后 Chise 面板变化:")
	print("- C感觉 Level: ", chise.stats["sensory_C"]["level"], " (Exp: ", chise.stats["sensory_C"]["exp"], ")")
	print("- B感觉 Level: ", chise.stats["sensory_B"]["level"], " (Exp: ", chise.stats["sensory_B"]["exp"], ")")
	print("- V感觉 Level: ", chise.stats["sensory_V"]["level"], " (Exp: ", chise.stats["sensory_V"]["exp"], ")")
	print("- 羞耻心 Level: ", chise.stats["shame"]["level"], " (Exp: ", chise.stats["shame"]["exp"], ")")
	print("- 接受度 Level: ", chise.stats["devotion"]["level"], " (Exp: ", chise.stats["devotion"]["exp"], ")")

	
	print("\n--- Test Completed ---")
	quit()
