class_name TaskManager
extends Node

# ==============================================================================
# project_ERA 任务分发与调度管理器 (Task Manager)
# 职责：接收 LLM 传回的动态微观指令序列 (Action Sequence)，并管理当前回合的任务队列。
# 完全摒弃固定指令套餐。
# ==============================================================================

# --- 当前回合的待执行任务队列 ---
# 结构：[ {"instructor_id": String, "target_id": String, "action_sequence": Array}, ... ]
var current_turn_tasks: Array[Dictionary] = []

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
		
		var action_sequence = task.get("action_sequence", [])
		if typeof(action_sequence) != TYPE_ARRAY:
			push_warning("LLM 没有返回有效的 action_sequence 数组，使用空数组兜底。")
			action_sequence = []
			
		current_turn_tasks.append({
			"instructor_id": instructor_id,
			"target_id": target_id,
			"action_sequence": action_sequence
		})
		print("Task Enqueued: [", instructor_id, "] -> [", target_id, "], Actions: ", action_sequence.size())

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
			
		# LLM 已经直接提供了动作数组，不需要再翻译
		var action_sequence: Array[Dictionary] = []
		for raw_act in task["action_sequence"]:
			if typeof(raw_act) == TYPE_DICTIONARY:
				action_sequence.append(raw_act)
		
		# 丢给仿真引擎一帧跑完
		var result_logs = sim_engine.process_task_sequence(target, instructor, action_sequence)
		all_logs.append_array(result_logs)
		
	# 清空队列，准备下个回合
	current_turn_tasks.clear()
	all_logs.append("=== 回合任务执行完毕 ===")
	
	return all_logs
