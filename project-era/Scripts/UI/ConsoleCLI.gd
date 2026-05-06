class_name ConsoleCLI
extends Control

# ==============================================================================
# project_ERA MVP 纯文本控制台前端 (CLI-like UI)
# 职责：提供一个极其极客的黑框终端，供社区玩家输入 API Key、切换模式并体验核心流程。
# ==============================================================================

var output_log: RichTextLabel
var input_field: LineEdit
var llm_client: LLMClient
var char_manager: CharacterManager
var task_manager: TaskManager
var tool_registry: ToolRegistry

# 简单的状态机
enum AppState { SETUP_URL, SETUP_KEY, SETUP_MODEL, IDLE, WAITING_FOR_LLM }
var current_state: AppState = AppState.SETUP_URL

# 暂存的配置
var temp_url: String = "https://gcli.ggchan.dev/v1/chat/completions" # 默认填入公益站代理后缀
var temp_key: String = ""
var temp_model: String = "gemini-3.1-pro-preview"

func _ready() -> void:
	# 动态构建 CLI UI
	_build_ui()
	
	# 初始化底层通信模块
	llm_client = LLMClient.new()
	add_child(llm_client)
	llm_client.request_completed.connect(_on_llm_reply)
	llm_client.request_failed.connect(_on_llm_error)
	
	# 初始化测试用的角色与任务管理器
	char_manager = CharacterManager.new()
	_init_mock_characters()
	
	task_manager = TaskManager.new()
	add_child(task_manager)
	
	# 初始化正则路由枢纽
	tool_registry = ToolRegistry.new(task_manager, char_manager)
	add_child(tool_registry)
	
	# 启动终端欢迎词
	_print_to_console("[color=green]>>> project_ERA MVP 控制台已启动 <<<[/color]")
	_print_to_console("欢迎使用！为了接入大语言模型进行沙盒推演，我们需要配置 API。")
	_print_to_console("考虑到本社区多使用公益站反向代理，系统默认采用 OpenAI 格式发起请求。")
	_print_to_console("\n[color=yellow]1/3 请输入代理服务器 URL (直接回车默认: https://api.openai.com/v1/chat/completions):[/color]")
	input_field.placeholder_text = temp_url

func _init_mock_characters() -> void:
	# ==========================================
	# 调教师队伍 (风纪委员会) - 初始属性较高
	# ==========================================
	var hina = CharacterData.new()
	hina.id = "hina_01"
	hina.char_name = "日奈"
	hina.stats["shame"]["level"] = 15
	hina.stats["lust"]["level"] = 90
	hina.stats["skill_oral"]["level"] = 80
	hina.stats["sadism_femdom"]["level"] = 85
	hina.custom_tags.assign(["风纪委员长", "小恶魔调教师", "对主人的命令绝对服从", "偶尔会撒娇"])
	char_manager.add_character(hina)
	
	var ako = CharacterData.new()
	ako.id = "ako_01"
	ako.char_name = "亚子"
	ako.stats["shame"]["level"] = 25
	ako.stats["lust"]["level"] = 85
	ako.stats["skill_oral"]["level"] = 75
	ako.custom_tags.assign(["风纪委员", "侧乳暴露", "极度崇拜日奈", "隐性M", "项圈"])
	char_manager.add_character(ako)

	var iori = CharacterData.new()
	iori.id = "iori_01"
	iori.char_name = "伊织"
	iori.stats["shame"]["level"] = 35
	iori.stats["lust"]["level"] = 75
	iori.stats["skill_oral"]["level"] = 60
	iori.custom_tags.assign(["风纪委员", "银色双马尾", "傲娇", "足控诱惑", "经常吃瘪"])
	char_manager.add_character(iori)

	var chinatsu = CharacterData.new()
	chinatsu.id = "chinatsu_01"
	chinatsu.char_name = "千夏"
	chinatsu.stats["shame"]["level"] = 20
	chinatsu.stats["lust"]["level"] = 80
	chinatsu.stats["skill_oral"]["level"] = 70
	chinatsu.custom_tags.assign(["风纪委员", "温泉合宿", "知性", "理疗师"])
	char_manager.add_character(chinatsu)

	# ==========================================
	# 待调教对象 (10人) - 初始羞耻心极高，欲望低
	# ==========================================
	var target_names = [
		{"id": "chise_01", "name": "千世", "tags": ["怕黑", "容易害羞", "被触碰胸部会颤抖"]},
		{"id": "aru_01", "name": "阿露", "tags": ["笨蛋美人", "强行装酷", "容易破防"]},
		{"id": "mutsuki_01", "name": "睦月", "tags": ["小恶魔", "喜欢捉弄人", "内心其实很害羞"]},
		{"id": "yuuka_01", "name": "优香", "tags": ["计算狂", "大腿丰满", "理智容易崩溃"]},
		{"id": "noa_01", "name": "诺亚", "tags": ["白发红眼", "过目不忘", "喜欢记录主人的声音"]},
		{"id": "asuna_01", "name": "明日奈", "tags": ["黄金猎犬", "无心机", "肉便器潜质"]},
		{"id": "karin_01", "name": "花凛", "tags": ["黑皮女仆", "容易不好意思", "后庭敏感"]},
		{"id": "neru_01", "name": "妮露", "tags": ["不良少女", "傲娇", "被夸奖会暴走"]},
		{"id": "toki_01", "name": "时", "tags": ["三无女仆", "和平时完全没变化", "面瘫"]},
		{"id": "shiroko_01", "name": "白子", "tags": ["狼耳", "行动派", "喜欢运动", "体液敏感"]}
	]

	for t in target_names:
		var c = CharacterData.new()
		c.id = t["id"]
		c.char_name = t["name"]
		c.stats["shame"]["level"] = 80 + randi() % 15 # 80~94的极高羞耻心
		c.stats["lust"]["level"] = randi() % 10 # 0~9的极低欲望
		c.stats["devotion"]["level"] = 0
		c.stats["edging_control"]["level"] = 5 + randi() % 5 # 给一点微弱的寸止基础
		c.custom_tags.assign(t["tags"])
		char_manager.add_character(c)


# ---------------------------------------------------------
# 动态生成极其简洁的黑客风 UI
# ---------------------------------------------------------
func _build_ui() -> void:
	# 全屏黑背景
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 1) # 深灰偏黑
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	# 垂直布局容器
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	var margins = MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 20)
	margins.add_theme_constant_override("margin_right", 20)
	margins.add_theme_constant_override("margin_top", 20)
	margins.add_theme_constant_override("margin_bottom", 20)
	margins.set_anchors_preset(PRESET_FULL_RECT)
	margins.add_child(vbox)
	add_child(margins)
	
	# 输出框 (RichTextLabel)
	output_log = RichTextLabel.new()
	output_log.bbcode_enabled = true
	output_log.scroll_following = true
	output_log.selection_enabled = true # 允许玩家使用鼠标拖拽选中文字
	output_log.context_menu_enabled = true # 允许玩家右键呼出复制菜单
	output_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_log.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(output_log)
	
	# 输入框 (LineEdit)
	input_field = LineEdit.new()
	input_field.add_theme_font_size_override("font_size", 18)
	input_field.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	input_field.placeholder_text = "在此输入指令，按 Enter 键发送..."
	input_field.text_submitted.connect(_on_input_submitted)
	vbox.add_child(input_field)
	
	# 启动后自动聚焦
	input_field.grab_focus()

# ---------------------------------------------------------
# 控制台打印辅助函数
# ---------------------------------------------------------
func _print_to_console(text: String, is_user: bool = false) -> void:
	if is_user:
		output_log.append_text("\n[color=cyan]Master > [/color]" + text + "\n")
	else:
		output_log.append_text("\n[color=white]" + text + "[/color]\n")

# ---------------------------------------------------------
# 用户输入处理逻辑状态机
# ---------------------------------------------------------
func _on_input_submitted(text: String) -> void:
	if current_state == AppState.WAITING_FOR_LLM:
		return # 请求中，锁死输入
		
	input_field.text = "" # 清空输入框
	
	# 处理阶段逻辑
	match current_state:
		AppState.SETUP_URL:
			if text.strip_edges() != "": temp_url = text.strip_edges()
			_print_to_console("设置 URL 为: " + temp_url)
			_print_to_console("\n[color=yellow]2/3 请输入 API Key / 代理密码 (如不需验证可填任意字符):[/color]")
			input_field.placeholder_text = "sk-xxxxxxxx..."
			current_state = AppState.SETUP_KEY
			
		AppState.SETUP_KEY:
			temp_key = text.strip_edges()
			_print_to_console("设置 API Key 为: [已隐藏]")
			_print_to_console("\n[color=yellow]3/3 请输入模型名称 (直接回车默认: gemini-3.1-pro-preview):[/color]")
			input_field.placeholder_text = temp_model
			current_state = AppState.SETUP_MODEL
			
		AppState.SETUP_MODEL:
			if text.strip_edges() != "": temp_model = text.strip_edges()
			_print_to_console("设置模型名称为: " + temp_model)
			llm_client.setup_api(temp_url, temp_key, temp_model)
			_print_to_console("\n[color=green]>>> 系统初始化完毕 <<<[/color]")
			_print_to_console("现在您可以直接输入指令。系统将向 LLM 发起【意图解析 (Assign)】。")
			_print_to_console("或者输入 '/miku 你的问题' 来召唤管理员进行【元叙事交流 (Meta)】。")
			input_field.placeholder_text = "输入游戏指令或 /miku ..."
			current_state = AppState.IDLE
			
		AppState.IDLE:
			if text.strip_edges() == "": return
			_print_to_console(text, true)
			
			var mode = LLMClient.MODE_ASSIGN
			var send_text = text
			
			# 如果指令以 /stats 开头，打印所有角色状态
			if text.begins_with("/stats"):
				_print_to_console("[color=yellow]=== 当前系统内所有角色面板数据 ===[/color]")
				for char_data in char_manager.get_all_characters():
					var msg = char_data.char_name + " (ID: " + char_data.id + ")\n"
					msg += "   [羞耻心]: LV " + str(char_data.stats["shame"]["level"]) + " (EXP: " + str(char_data.stats["shame"]["exp"]) + ")\n"
					msg += "   [欲  望]: LV " + str(char_data.stats["lust"]["level"]) + " (EXP: " + str(char_data.stats["lust"]["exp"]) + ")\n"
					msg += "   [接受度]: LV " + str(char_data.stats["devotion"]["level"]) + " (EXP: " + str(char_data.stats["devotion"]["exp"]) + ")\n"
					msg += "   [C 感觉]: LV " + str(char_data.stats["sensory_C"]["level"]) + " (EXP: " + str(char_data.stats["sensory_C"]["exp"]) + ")\n"
					msg += "   [Tags]: " + str(char_data.custom_tags)
					_print_to_console(msg)
				current_state = AppState.IDLE
				return

			# 如果指令以 /miku 开头，进入元叙事聊天模式
			if text.begins_with("/miku "):
				mode = LLMClient.MODE_META
				send_text = text.substr(6)
				
			current_state = AppState.WAITING_FOR_LLM
			_print_to_console("[color=gray]...正在请求外部接口 (RPM 控制中)...[/color]")
			
			# 组装上下文发送
			var context = {}
			for char_data in char_manager.get_all_characters():
				context[char_data.id] = char_data.get_prompt_context(false)
				
			llm_client.send_request(mode, send_text, context)

# ---------------------------------------------------------
# 回调：LLM 处理完毕
# ---------------------------------------------------------
func _on_llm_reply(reply_text: String) -> void:
	current_state = AppState.IDLE
	
	# 通过 ToolRegistry 拦截和处理所有的伪函数（JSON 数组或特殊宏标签）
	var clean_text = tool_registry.parse_and_route(reply_text)
	
	_print_to_console("[color=pink]System/LLM返回 >\n" + clean_text + "[/color]")
	
	# 如果当前队列里有解析出来的宏观任务，自动在后台推演并打印结算
	if task_manager.current_turn_tasks.size() > 0:
		var sim_engine = SimulationEngine.new()
		var logs = task_manager.execute_all_tasks(char_manager, sim_engine)
		_print_to_console("\n[color=yellow]--- Godot 后台自动推演结算开始 ---[/color]")
		for l in logs:
			_print_to_console("[color=gray]" + l + "[/color]")
		_print_to_console("[color=yellow]--- 推演完毕 ---[/color]\n")
		sim_engine.queue_free()

func _on_llm_error(err_msg: String) -> void:
	current_state = AppState.IDLE
	_print_to_console("[color=red]网络/解析报错 > " + err_msg + "[/color]")
