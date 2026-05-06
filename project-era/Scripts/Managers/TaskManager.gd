class_name TaskManager
extends Node

# ==============================================================================
# project_ERA 任务分发与调度管理器 (Task Manager)
# 职责：接收 LLM 传回的“宏观意图 (Macro Strategy)”，将其翻译成供 
# SimulationEngine 消费的“10连微观指令序列 (Action Sequence)”，并管理当前回合的任务队列。
# ==============================================================================

# --- 当前回合的待执行任务队列 ---
# 结构：[ {"instructor": String, "target": String, "strategy": String, "location": String}, ... ]
var current_turn_tasks: Array[Dictionary] = []

# --- 系统支持的宏观策略字典 (Macro Strategy Dictionary) ---
# LLM 只能返回字典中有的 keys
const MACRO_STRATEGIES = {
	"oral_training": "口交特训",
	"anal_development": "后庭开发",
	"shame_breaking": "羞耻心破坏 (露出/羞辱)",
	"yuri_bonding": "温和百合贴贴 (破冰)",
	"solitary_confinement": "小黑屋禁欲 (逆向调教)",
	"etiquette_lessons": "礼仪教养 (逆向调教)"
}

# ---------------------------------------------------------
# 1. 接收 LLM 批量返回的任务并压入队列
# ---------------------------------------------------------
func enqueue_macro_tasks(task_list: Array) -> void:
	current_turn_tasks.clear()
	for task in task_list:
		var inst_raw = task.get("instructor_id", task.get("instructor", "none"))
		var target_raw = task.get("target_id", task.get("target", "none"))
		
		# 强制防御 LLM 的格式幻觉 (防止它把 ID 包装成数组 ["chise_01"])
		var instructor_id = inst_raw[0] if typeof(inst_raw) == TYPE_ARRAY and inst_raw.size() > 0 else str(inst_raw)
		var target_id = target_raw[0] if typeof(target_raw) == TYPE_ARRAY and target_raw.size() > 0 else str(target_raw)
		
		var strategy = str(task.get("macro_strategy", "yuri_bonding"))
		
		# 验证策略合法性，防 LLM 幻觉
		if not MACRO_STRATEGIES.has(strategy):
			push_warning("Unknown macro strategy from LLM: " + strategy + ". Defaulting to yuri_bonding.")
			strategy = "yuri_bonding"
			
		current_turn_tasks.append({
			"instructor_id": instructor_id,
			"target_id": target_id,
			"strategy": strategy
		})
		print("Task Enqueued: [", instructor_id, "] -> [", target_id, "] via [", MACRO_STRATEGIES[strategy], "]")

# ---------------------------------------------------------
# 2. 将宏观策略“解包/翻译”为微观连招序列 (Action Sequence)
# ---------------------------------------------------------
func _translate_strategy_to_actions(strategy: String) -> Array[Dictionary]:
	var sequence: Array[Dictionary] = []
	var CE = SimulationEngine.CommandType # 简写引用
	
	match strategy:
		"yuri_bonding":
			# 极其温和的破冰连招：高顺从加值，全套爱抚
			sequence.append({"name": "温和对话", "type": CE.ICE_BREAK})
			sequence.append({"name": "牵手", "type": CE.ICE_BREAK})
			sequence.append({"name": "拥抱爱抚", "type": CE.ICE_BREAK, "target_part": "sensory_B"})
			sequence.append({"name": "轻柔舔阴", "type": CE.ICE_BREAK, "target_part": "sensory_C"})
			# 破冰一般不追求高潮，以积累好感和欲望为主
			
		"oral_training":
			# 口交特训：先破冰，中途强制要求服务，最后高潮结算
			sequence.append({"name": "命令脱衣", "type": CE.NORMAL})
			sequence.append({"name": "爱抚安抚", "type": CE.ICE_BREAK, "target_part": "sensory_C"})
			sequence.append({"name": "强迫含住", "type": CE.NORMAL, "target_part": "sensory_M"})
			sequence.append({"name": "深喉抽插", "type": CE.NORMAL, "target_part": "sensory_M"})
			sequence.append({"name": "深喉抽插", "type": CE.NORMAL, "target_part": "sensory_M"})
			sequence.append({"name": "允许高潮", "type": CE.FINISHER})
			
		"anal_development":
			# 极度困难的后庭开发：大量铺垫，甚至涉及深渊指令
			sequence.append({"name": "强制灌肠", "type": CE.ABYSS, "target_part": "sensory_A"})
			sequence.append({"name": "大量润滑", "type": CE.ICE_BREAK, "target_part": "sensory_A"})
			sequence.append({"name": "手指扩张", "type": CE.NORMAL, "target_part": "sensory_A"})
			sequence.append({"name": "粗暴抽插", "type": CE.NORMAL, "target_part": "sensory_A"})
			sequence.append({"name": "粗暴抽插", "type": CE.NORMAL, "target_part": "sensory_A"})
			sequence.append({"name": "允许高潮", "type": CE.FINISHER})
			
		"solitary_confinement":
			# 逆向指令连招：扣减大量欲望
			sequence.append({"name": "贞操带上锁", "type": CE.REVERSE, "target_stat": "lust", "amount": 100})
			sequence.append({"name": "放置Play", "type": CE.REVERSE, "target_stat": "lust", "amount": 300})
			
		"etiquette_lessons":
			# 逆向指令连招：恢复羞耻心
			sequence.append({"name": "抄写女德", "type": CE.REVERSE, "target_stat": "shame", "amount": -100}) # 负负得正，即增加经验
			sequence.append({"name": "仪态纠正", "type": CE.REVERSE, "target_stat": "shame", "amount": -200})
			
		_:
			sequence.append({"name": "未知操作", "type": CE.NORMAL})
			
	return sequence

# ---------------------------------------------------------
# 3. 消费队列并执行推演 (由 MainLoop 在时间推进时调用)
# ---------------------------------------------------------
func execute_all_tasks(char_manager: CharacterManager, sim_engine: SimulationEngine) -> Array[String]:
	var all_logs: Array[String] = []
	all_logs.append("=== 回合任务开始执行 ===")
	
	for task in current_turn_tasks:
		var target = char_manager.get_character(task["target_id"])
		var instructor = null
		if task["instructor_id"] != "none":
			instructor = char_manager.get_character(task["instructor_id"])
			
		if target == null:
			all_logs.append("[警告] 找不到目标角色: " + task["target_id"])
			continue
			
		# 将 LLM 给的宏观策略，解包为 10 连招微观序列
		var action_sequence = _translate_strategy_to_actions(task["strategy"])
		
		# 丢给仿真引擎一帧跑完
		var result_logs = sim_engine.process_task_sequence(target, instructor, action_sequence)
		all_logs.append_array(result_logs)
		
	# 清空队列，准备下个回合
	current_turn_tasks.clear()
	all_logs.append("=== 回合任务执行完毕 ===")
	
	return all_logs
