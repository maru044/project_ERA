class_name ConsoleCLI
extends Control

# ==============================================================================
# project_ERA MVP 纯文本控制台前端 (CLI-like UI)
# 职责：提供一个极其极客的黑框终端，供社区玩家输入 API Key、切换模式并体验核心流程。
# ==============================================================================

var output_log: RichTextLabel
var input_field: LineEdit
var time_label: RichTextLabel
var stats_window: Window
var stats_content: RichTextLabel
var llm_client: LLMClient
var char_manager: CharacterManager
var task_manager: TaskManager
var tool_registry: ToolRegistry

# 简单的状态机
enum AppState { SETUP_URL, SETUP_KEY, SETUP_MODEL, IDLE, WAITING_FOR_LLM }
var current_state: AppState = AppState.SETUP_URL

# 时间轴变量
var current_day: int = 1
var time_phase: int = 0
const PHASES = ["☀️ 清晨 (任务分配)", "🕛 上午 (后台推演)", "🍴 中午 (中场干预)", "🌇 下午 (后台推演)", "🌙 傍晚 (战报结算)", "🍷 深夜 (夜伽沙盒)"]

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
	margins.add_theme_constant_override("margin_bottom", 100) # [Web/手机端安全区] 强行留白，防底栏遮挡输入框
	margins.set_anchors_preset(PRESET_FULL_RECT)
	margins.add_child(vbox)
	add_child(margins)
	
	# --- 加载全局字体 ---
	var custom_font = load("res://Fonts/SmileySans-Oblique.otf")

	# --- 顶部状态栏 ---
	var header_box = HBoxContainer.new()
	vbox.add_child(header_box)
	
	time_label = RichTextLabel.new()
	time_label.bbcode_enabled = true
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_label.custom_minimum_size.y = 40
	time_label.add_theme_font_size_override("normal_font_size", 22)
	time_label.add_theme_font_size_override("bold_font_size", 22)
	time_label.add_theme_font_override("normal_font", custom_font)
	time_label.add_theme_font_override("bold_font", custom_font)
	header_box.add_child(time_label)
	
	var roster_btn = Button.new()
	roster_btn.text = " 📋 查看后宫状态 "
	roster_btn.add_theme_font_size_override("font_size", 22)
	roster_btn.add_theme_font_override("font", custom_font)
	roster_btn.pressed.connect(_on_roster_button_pressed)
	header_box.add_child(roster_btn)
	
	# --- 角色图鉴弹窗 ---
	stats_window = Window.new()
	stats_window.title = "系统后台面板 - 角色状态档案"
	stats_window.size = Vector2i(800, 600)
	stats_window.visible = false
	stats_window.exclusive = true
	stats_window.close_requested.connect(func(): stats_window.hide())
	add_child(stats_window)
	
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	stats_window.add_child(scroll)
	
	stats_content = RichTextLabel.new()
	stats_content.bbcode_enabled = true
	stats_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_content.custom_minimum_size = Vector2(780, 0)
	stats_content.add_theme_font_size_override("normal_font_size", 20)
	stats_content.add_theme_font_size_override("bold_font_size", 20)
	stats_content.add_theme_font_override("normal_font", custom_font)
	stats_content.add_theme_font_override("bold_font", custom_font)
	scroll.add_child(stats_content)
	
	# 输出框 (RichTextLabel)
	output_log = RichTextLabel.new()
	output_log.bbcode_enabled = true
	output_log.scroll_following = true
	output_log.selection_enabled = true # 允许玩家使用鼠标拖拽选中文字
	output_log.context_menu_enabled = true # 允许玩家右键呼出复制菜单
	output_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_log.add_theme_font_size_override("normal_font_size", 24)
	output_log.add_theme_font_size_override("bold_font_size", 24)
	output_log.add_theme_font_override("normal_font", custom_font)
	output_log.add_theme_font_override("bold_font", custom_font)
	vbox.add_child(output_log)
	
	# --- 底部输入区 (巨型物理按钮，专治 Web/手机端顽疾) ---
	var input_area = VBoxContainer.new()
	input_area.add_theme_constant_override("separation", 15)
	vbox.add_child(input_area)
	
	# 第一行：极宽极高的输入框
	input_field = LineEdit.new()
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.custom_minimum_size.y = 70 # 确保手指极其好点击，呼出虚拟键盘
	input_field.add_theme_font_size_override("font_size", 26)
	input_field.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	input_field.add_theme_font_override("font", custom_font)
	input_field.placeholder_text = "在此输入指令，按下方按钮发送..."
	# 保留键盘回车提交，以防 PC 玩家习惯
	input_field.text_submitted.connect(_on_input_submitted)
	input_area.add_child(input_field)
	
	# 第二行：并排的巨型按钮组
	var btn_box = HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 20)
	input_area.add_child(btn_box)
	
	# 专为 Web 端准备的极巨化“粘贴”按钮
	var paste_btn = Button.new()
	paste_btn.text = " 📋 粘贴内容 "
	paste_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste_btn.custom_minimum_size.y = 70
	paste_btn.add_theme_font_size_override("font_size", 26)
	paste_btn.add_theme_font_override("font", custom_font)
	paste_btn.pressed.connect(func(): input_field.text = DisplayServer.clipboard_get())
	btn_box.add_child(paste_btn)
	
	# 手机端终极拯救者：物理“确认发送”按钮
	var send_btn = Button.new()
	send_btn.text = " 📤 确认发送 "
	send_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_btn.custom_minimum_size.y = 70
	send_btn.add_theme_font_size_override("font_size", 26)
	send_btn.add_theme_color_override("font_color", Color.CYAN)
	send_btn.add_theme_font_override("font", custom_font)
	# 点击按钮时，主动提取文本框里的内容走提交逻辑
	send_btn.pressed.connect(func(): _on_input_submitted(input_field.text))
	btn_box.add_child(send_btn)
	
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
			_print_to_console("或者输入 '/chat 角色ID1,角色ID2... 你的话' 来直接与角色进行【沉浸扮演 (Roleplay)】。")
			input_field.placeholder_text = "输入指令，或 /miku，或 /chat id1 ..."
			current_state = AppState.IDLE
			
		AppState.IDLE:
			if text.strip_edges() == "": return
			_print_to_console(text, true)
			
			var mode = LLMClient.MODE_ASSIGN
			var send_text = text
			var active_char_ids = [] # 记录当前需要参与互动的角色ID，为空则代表所有人
			
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
			elif text.begins_with("/miku "):
				mode = LLMClient.MODE_META
				send_text = text.substr(6)
				
			# 如果指令以 /chat 开头，进入角色扮演对话模式 (内存隔离关键)
			elif text.begins_with("/chat "):
				mode = LLMClient.MODE_ROLEPLAY
				# 解析命令: /chat hina_01,chise_01 你好呀
				var parts = text.substr(6).split(" ", false, 1)
				if parts.size() > 0:
					active_char_ids = parts[0].split(",")
				if parts.size() > 1:
					send_text = parts[1]
				else:
					send_text = "..." # 如果没写对话只@了人
				
			current_state = AppState.WAITING_FOR_LLM
			_print_to_console("[color=gray]...正在请求外部接口 (RPM 控制中)...[/color]")
			
			# 组装上下文发送（严格的记忆隔离）
			var context = {}
			for char_data in char_manager.get_all_characters():
				# 在分配模式和Miku模式下，系统能看到所有人的简略面板，但不一定带独占记忆
				# 在扮演模式下，只有被点名的 active_char_ids 才会被送入上下文，彻底防串戏
				if mode == LLMClient.MODE_ROLEPLAY:
					if char_data.id in active_char_ids:
						context[char_data.id] = char_data.get_prompt_context(true) # 携带独占记忆
				else:
					# Assign 模式全看，但无独占记忆；Meta 模式全看
					context[char_data.id] = char_data.get_prompt_context(false)
				
			llm_client.send_request(mode, send_text, context)

# ---------------------------------------------------------
# 时间推进与顶部横幅更新
# ---------------------------------------------------------
func _update_header() -> void:
	var phase_name = PHASES[time_phase]
	time_label.text = "[color=yellow][b]【 第 " + str(current_day) + " 天 | " + phase_name + " 】[/b][/color]"

func _advance_time() -> void:
	time_phase += 1
	if time_phase >= PHASES.size():
		time_phase = 0
		current_day += 1
	_update_header()

# ---------------------------------------------------------
# 角色图鉴弹窗刷新
# ---------------------------------------------------------
func _on_roster_button_pressed() -> void:
	stats_window.popup_centered()
	var bbcode = "[center][b]=== 系统运行中角色名单与属性总览 ===[/b][/center]\n\n"
	
	for char_data in char_manager.get_all_characters():
		bbcode += "[b]" + char_data.char_name + "[/b] (ID: " + char_data.id + ")"
		
		# 判断是否可以做调教师 (Devotion >= 50)
		if char_data.stats["devotion"]["level"] >= 50:
			bbcode += " [color=pink][b](⭐可担任调教师)[/b][/color]"
		bbcode += "\n"
		
		bbcode += "   [color=gray]羞耻心:[/color] LV " + str(char_data.stats["shame"]["level"]) + " (" + str(char_data.stats["shame"]["exp"]) + " Exp)\n"
		bbcode += "   [color=gray]欲  望:[/color] LV " + str(char_data.stats["lust"]["level"]) + " (" + str(char_data.stats["lust"]["exp"]) + " Exp)\n"
		bbcode += "   [color=gray]接受度:[/color] LV " + str(char_data.stats["devotion"]["level"]) + " (" + str(char_data.stats["devotion"]["exp"]) + " Exp)\n"
		bbcode += "   [color=gray]C感觉:[/color] LV " + str(char_data.stats["sensory_C"]["level"]) + " (" + str(char_data.stats["sensory_C"]["exp"]) + " Exp)\n"
		bbcode += "   [color=gray]Tags:[/color] [color=cyan]" + str(char_data.custom_tags) + "[/color]\n\n"
		
	stats_content.text = bbcode

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
		
		# 推演完成后自动推进时间阶段
		_advance_time()

func _on_llm_error(err_msg: String) -> void:
	current_state = AppState.IDLE
	_print_to_console("[color=red]网络/解析报错 > " + err_msg + "[/color]")
