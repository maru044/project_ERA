class_name ToolRegistry
extends Node

# ==============================================================================
# project_ERA 工具注册与路由枢纽 (Tool Registry)
# 职责：接收 LLM 传回的原始纯文本，利用强大的正则表达式 (Regex) 提取预设的
# 伪函数指令（JSON块、状态改变标签、私密记忆标签），并自动路由给各大 Manager 执行。
# ==============================================================================

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
	
	# 2. 匹配 [STAT_CHANGE: char_id | stat_key | +amount]
	regex_stat = RegEx.new()
	regex_stat.compile("\\[STAT_CHANGE:\\s*([\\w_]+)\\s*\\|\\s*([\\w_]+)\\s*\\|\\s*([+-]?\\d+)\\s*\\]")
	
	# 3. 匹配 [ADD_MEMORY: char_A, char_B | 发生了一件秘密的事情]
	regex_memory = RegEx.new()
	regex_memory.compile("\\[ADD_MEMORY:\\s*([\\w_,\\s]+)\\s*\\|\\s*([^]]+)\\s*\\]")

# ---------------------------------------------------------
# 主解析入口：接收大模型返回的纯文本
# 返回：去除掉了所有的系统指令宏，只剩下纯净的 Roleplay 文本供 UI 显示
# ---------------------------------------------------------
func parse_and_route(llm_raw_text: String) -> String:
	var clean_text = llm_raw_text
	
	# ==========================================
	# A. 提取宏观任务分配 JSON (parse_and_assign_tasks)
	# ==========================================
	var json_str = ""
	var json_match = regex_json.search(llm_raw_text)
	
	if json_match:
		json_str = json_match.get_string(1)
		# 测试期间不抹除 JSON，方便 debug
		# clean_text = regex_json.sub(clean_text, "", true)
	else:
		# 兜底捕获：尝试寻找裸露的 JSON 数组
		var raw_match = regex_json_raw.search(llm_raw_text)
		if raw_match:
			json_str = raw_match.get_string(1)
			# clean_text = regex_json_raw.sub(clean_text, "", true)
			
	if json_str != "":
		var json = JSON.new()
		if json.parse(json_str) == OK and typeof(json.data) == TYPE_ARRAY:
			task_manager.enqueue_macro_tasks(json.data)
			print("[ToolRegistry] 成功捕获并路由了宏观任务数组。")
		else:
			push_error("[ToolRegistry] JSON 解析失败: " + json_str)
		
	# ==========================================
	# B. 提取动态数值修正 (generate_stage_reports)
	# ==========================================
	var stat_matches = regex_stat.search_all(llm_raw_text)
	for m in stat_matches:
		var target_id = m.get_string(1).strip_edges()
		var stat_key = m.get_string(2).strip_edges()
		var amount = int(m.get_string(3).strip_edges())
		
		char_manager.apply_stat_change(target_id, stat_key, amount)
		print("[ToolRegistry] 捕获并执行数值修正: ", target_id, " | ", stat_key, " | ", amount)
	
	# 抹除数值修改标签
	clean_text = regex_stat.sub(clean_text, "", true)
	
	# ==========================================
	# C. 提取独占记忆 (inject_exclusive_memory)
	# ==========================================
	var mem_matches = regex_memory.search_all(llm_raw_text)
	for m in mem_matches:
		var raw_ids = m.get_string(1)
		var memory_content = m.get_string(2).strip_edges()
		
		# 将 "char_A, char_B" 切割为数组
		var target_ids: Array = []
		for id_str in raw_ids.split(","):
			target_ids.append(id_str.strip_edges())
			
		char_manager.inject_exclusive_memory(target_ids, memory_content)
		print("[ToolRegistry] 捕获独占记忆，分配给: ", target_ids)
		
	# 抹除记忆注入标签
	clean_text = regex_memory.sub(clean_text, "", true)
	
	# 最后，残忍地剥离大模型的全部思考过程（防止存入历史记录污染下文）
	clean_text = regex_think.sub(clean_text, "", true)
	
	# 另外，去掉为了格式必须加的特殊标签，以免破坏沉浸感
	clean_text = clean_text.replace("[使用简体中文开始游戏:]", "")
	
	# 返回抹除了所有 [系统宏] 和思考过程的纯净文本，交给 Console UI 显示与保存
	return clean_text.strip_edges()
