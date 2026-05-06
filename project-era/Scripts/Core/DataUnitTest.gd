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
	
	# 测试 6：推演引擎连招测试 (结合 TaskManager)
	print("\n--- Test: Simulation Engine Task Sequence via TaskManager ---")
	var engine = SimulationEngine.new()
	var task_manager = TaskManager.new()
	
	var chise = CharacterData.new()
	chise.id = "chise_01"
	chise.char_name = "Chise"
	chise.stats["shame"]["level"] = 50 # 设定较高的初始羞耻心
	chise.stats["edging_control"]["level"] = 5 # 给一点寸止能力
	manager.add_character(chise)
	
	var hina = CharacterData.new()
	hina.id = "hina_01"
	hina.char_name = "Hina_Instructor"
	manager.add_character(hina)
	
	# 模拟 LLM 返回了一个批量任务分配 JSON 数组
	var mock_llm_response = [
		{
			"instructor_id": "hina_01",
			"target_id": "chise_01",
			"action_sequence": [
				{"action_flavor": "强制脱衣", "check_stat": "shame", "reward_stat": "yuri_obedience", "difficulty_modifier": -20},
				{"action_flavor": "强迫含住", "check_stat": "sensory_M", "reward_stat": "sensory_M", "difficulty_modifier": -10},
				{"action_flavor": "允许高潮", "type": "FINISHER"}
			]
		},
		{
			"instructor_id": "none",
			"target_id": "char_test_01", # 这是上面 Mod 测加载的 Miku
			"action_sequence": [
				{"action_flavor": "抄写女德", "type": "REVERSE", "check_stat": "lust", "difficulty_modifier": 200}
			]
		}
	]
	
	# 解析意图进入队列
	task_manager.enqueue_macro_tasks(mock_llm_response)
	
	# 一次性执行所有任务并获取日志
	var logs = task_manager.execute_all_tasks(manager, engine)
	for l in logs:
		print(l)
		
	print("\n结算后 Chise 面板变化:")
	print("- M感觉 Level: ", chise.stats["sensory_M"]["level"], " (Exp: ", chise.stats["sensory_M"]["exp"], ")")
	print("- C感觉 Level: ", chise.stats["sensory_C"]["level"], " (Exp: ", chise.stats["sensory_C"]["exp"], ")")
	print("- 羞耻心 Level: ", chise.stats["shame"]["level"], " (Exp: ", chise.stats["shame"]["exp"], ")")
	print("- 接受度 Level: ", chise.stats["devotion"]["level"], " (Exp: ", chise.stats["devotion"]["exp"], ")")

	print("\n结算后 Miku 面板变化 (禁欲逆向调教):")
	var miku2 = manager.get_character("char_test_01")
	print("- 欲望 Level: ", miku2.stats["lust"]["level"], " (Exp: ", miku2.stats["lust"]["exp"], ")")

	print("\n--- Test Completed ---")
	quit()
