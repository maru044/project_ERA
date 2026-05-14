class_name ToolRegistry
extends Node

# ==============================================================================
# project_ERA 工具注册与路由枢纽 (Tool Registry)
# 职责：接收 LLM 传回的原始纯文本，利用强大的正则表达式 (Regex) 提取预设的
# 伪函数指令（JSON块、状态改变标签、私密记忆标签），并自动路由给各大 Manager 执行。
# ==============================================================================

signal on_system_log_generated(log_text: String)

var regex_json: RegEx
var regex_json_raw: RegEx
var regex_stat: RegEx
var regex_memory: RegEx
var regex_think: RegEx

# 注入所需的外部管理器依赖
var task_manager: TaskManager
var char_manager: CharacterManager

func _init(t_mgr: TaskManager, c_mgr: CharacterManager) -> void:
	task_manager = t_mgr
	char_manager = c_mgr
	_compile_regex()

func _compile_regex() -> void:
	# 0. 剥离大模型思考过程的正则
	regex_think = RegEx.new()
	regex_think.compile("(?s)<think(?:ing)?>.*?</think(?:ing)?>")
	
	# 1. 匹配包裹在 ```json [...] ``` 中的 JSON 数组
	regex_json = RegEx.new()
	regex_json.compile("(?s)```(?:json)?\\s*(\\[.*?\\])\\s*```")
	
	# 1.5 兜底匹配：提取裸露的 [...] 数组结构
	regex_json_raw = RegEx.new()
	regex_json_raw.compile("(?s)(\\[\\s*\\{.*?\\}\\s*\\])")
	
	# 2. 匹配 [STAT_CHANGE: char_id | stat_key | +amount] (兼容逗号和竖线)
	regex_stat = RegEx.new()
	regex_stat.compile("\\[STAT_CHANGE:\\s*([\\w_]+)\\s*[,|]\\s*([\\w_]+)\\s*[,|]\\s*([+-]?\\d+)\\s*\\]")
	
	# 3. 匹配 [ADD_MEMORY: char_A, char_B | 发生了一件秘密的事情] (兼容逗号和竖线)
	regex_memory = RegEx.new()
	regex_memory.compile("\\[ADD_MEMORY:\\s*([\\w_,\\s]+)\\s*[,|]\\s*([^]]+)\\s*\\]")

# ---------------------------------------------------------
# 主解析入口：接收大模型返回的纯文本
# 返回：去除掉了所有的系统指令宏，只剩下纯净的 Roleplay 文本供 UI 显示
# ---------------------------------------------------------
func parse_and_route(llm_raw_text: String, current_mode: String) -> String:
	var clean_text = llm_raw_text
	
	# ==========================================
	# A. 提取宏观任务分配 JSON (parse_and_assign_tasks)
	# 只有在 MODE_ASSIGN 时，才允许解析 JSON 任务，防止 Miku/聊天模式误触
	# ==========================================
	if current_mode == LLMClient.MODE_ASSIGN:
		var json_str = ""
		var json_match = regex_json.search(llm_raw_text)
		
		if json_match:
			json_str = json_match.get_string(1)
		else:
			# 兜底捕获：尝试寻找裸露的 JSON 数组
			var raw_match = regex_json_raw.search(llm_raw_text)
			if raw_match:
				json_str = raw_match.get_string(1)
				
		if json_str != "":
			var json = JSON.new()
			if json.parse(json_str) == OK and typeof(json.data) == TYPE_ARRAY:
				task_manager.enqueue_macro_tasks(json.data)
				print("[ToolRegistry] 成功捕获并路由了宏观任务数组。")
			else:
				push_error("[ToolRegistry] JSON 解析失败: " + json_str)
		
	# ==========================================
	# B. 提取动态数值修正 (generate_stage_reports)
	# 仅在角色扮演模式和口上模式允许手动修改数值，防止 Miku 复读产生二次叠加
	# ==========================================
	if current_mode == LLMClient.MODE_ROLEPLAY or current_mode == LLMClient.MODE_KOUJO:
		var stat_matches = regex_stat.search_all(llm_raw_text)
		for m in stat_matches:
			var target_id = m.get_string(1).strip_edges()
			var stat_key = m.get_string(2).strip_edges()
			var amount = int(m.get_string(3).strip_edges())
			
			char_manager.apply_stat_level_change(target_id, stat_key, amount)
			var target = char_manager.get_character(target_id)
			var t_name = target.char_name if target else target_id
			on_system_log_generated.emit("[系统提示: " + t_name + " 的 " + stat_key + " 等级变动了 " + str(amount) + " 级]")
	
	# 无论是否执行，只要出现都把标签抹除，保证前端显示干净
	clean_text = regex_stat.sub(clean_text, "", true)
	
	# ==========================================
	# C. 提取独占记忆 (inject_exclusive_memory)
	# ==========================================
	if current_mode == LLMClient.MODE_ROLEPLAY or current_mode == LLMClient.MODE_KOUJO:
		var mem_matches = regex_memory.search_all(llm_raw_text)
		for m in mem_matches:
			var raw_ids = m.get_string(1)
			var memory_content = m.get_string(2).strip_edges()
			
			var target_ids: Array = []
			var target_names: Array = []
			for id_str in raw_ids.split(","):
				var c_id = id_str.strip_edges()
				target_ids.append(c_id)
				var target = char_manager.get_character(c_id)
				target_names.append(target.char_name if target else c_id)
				
			char_manager.inject_exclusive_memory(target_ids, memory_content)
			on_system_log_generated.emit("[系统提示: 成功为 " + ", ".join(target_names) + " 注入了新的私密记忆]")
			
	# 无论是否执行，都抹除记忆注入标签
	clean_text = regex_memory.sub(clean_text, "", true)
	
	return clean_text.strip_edges()
