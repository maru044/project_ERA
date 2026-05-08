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
var help_window: Window
var help_content: RichTextLabel
var settings_window: Window
var koujo_toggle: CheckButton
var hide_thinking_toggle: CheckButton
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

# 系统日志存档，用于给大模型喂入当天发生的事件
var daily_system_logs: Array[String] = []

# 全局对话历史缓存池 (物理隔离记忆的关键)
# 结构: [ {"role": "user/assistant", "content": "text", "participants": ["miku"] 或 ["hina_01", "chise_01"]}, ... ]
var global_chat_pool: Array[Dictionary] = []

# 暂存当前正在请求的模式与参与者，用于回调时压入历史
var current_request_mode: String = ""
var current_request_participants: Array = []

# 暂存的配置
var temp_url: String = "https://gcli.ggchan.dev/v1/chat/completions" # 默认填入公益站代理后缀
var temp_key: String = ""
var temp_model: String = "gemini-3.1-pro-preview"

# --- 属性名中英文对照字典 ---
const STAT_NAMES_CN = {
	"devotion": "接受度",
	"shame": "羞耻心",
	"rebellion": "反抗度/傲娇",
	"yuri_obedience": "百合顺从",
	"lust": "欲望",
	"sensory_M": "M感觉(嘴)",
	"sensory_B": "B感觉(胸)",
	"sensory_A": "A感觉(后庭)",
	"sensory_C": "C感觉(阴蒂)",
	"sensory_V": "V感觉(小穴)",
	"sensory_P": "P感觉(肉棒)",
	"exhibitionism": "露出癖",
	"semen_addiction": "精液中毒",
	"edging_control": "寸止忍耐"
}

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
	
	# 尝试从外部用户目录加载玩家自制的 MOD 角色 (JSON)
	char_manager.load_external_characters()
	
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
	hina.stats["devotion"]["level"] = 90
	hina.stats["yuri_obedience"]["level"] = 95
	hina.stats["edging_control"]["level"] = 90
	hina.stats["sensory_M"]["level"] = 80
	hina.stats["sensory_C"]["level"] = 50
	hina.stats["sensory_V"]["level"] = 60
	hina.stats["semen_addiction"]["level"] = 40
	hina.custom_tags.assign(["风纪委员长", "对主人的命令绝对服从", "偶尔会撒娇", "顶级口交技巧", "极端小恶魔施虐狂"])
	char_manager.add_character(hina)
	
	var ako = CharacterData.new()
	ako.id = "ako_01"
	ako.char_name = "亚子"
	ako.stats["shame"]["level"] = 25
	ako.stats["lust"]["level"] = 85
	ako.stats["devotion"]["level"] = 80
	ako.stats["yuri_obedience"]["level"] = 85
	ako.stats["edging_control"]["level"] = 20
	ako.stats["rebellion"]["level"] = 10
	ako.stats["sensory_B"]["level"] = 80
	ako.stats["sensory_M"]["level"] = 70
	ako.stats["sensory_V"]["level"] = 50
	ako.stats["exhibitionism"]["level"] = 60
	ako.stats["semen_addiction"]["level"] = 50
	ako.custom_tags.assign(["风纪委员", "侧乳暴露", "极度崇拜日奈", "隐性M", "项圈", "精通指交与口交"])
	char_manager.add_character(ako)

	var iori = CharacterData.new()
	iori.id = "iori_01"
	iori.char_name = "伊织"
	iori.stats["shame"]["level"] = 35
	iori.stats["lust"]["level"] = 75
	iori.stats["devotion"]["level"] = 70
	iori.stats["yuri_obedience"]["level"] = 60
	iori.stats["edging_control"]["level"] = 50
	iori.stats["rebellion"]["level"] = 50
	iori.stats["sensory_M"]["level"] = 40
	iori.stats["sensory_V"]["level"] = 70
	iori.custom_tags.assign(["风纪委员", "银色双马尾", "傲娇", "足控诱惑", "经常吃瘪", "熟练的骑乘技巧"])
	char_manager.add_character(iori)

	var chinatsu = CharacterData.new()
	chinatsu.id = "chinatsu_01"
	chinatsu.char_name = "千夏"
	chinatsu.stats["shame"]["level"] = 20
	chinatsu.stats["lust"]["level"] = 80
	chinatsu.stats["devotion"]["level"] = 85
	chinatsu.stats["yuri_obedience"]["level"] = 80
	chinatsu.stats["edging_control"]["level"] = 80
	chinatsu.stats["sensory_M"]["level"] = 60
	chinatsu.stats["sensory_B"]["level"] = 60
	chinatsu.stats["sensory_A"]["level"] = 40
	chinatsu.stats["sensory_V"]["level"] = 60
	chinatsu.custom_tags.assign(["风纪委员", "温泉合宿", "知性", "理疗师", "精通各种体位"])
	char_manager.add_character(chinatsu)

	# ==========================================
	# 待调教对象 (10人) - 细化各种感官与阶梯数值
	# ==========================================
	var targets_data = [
		{"id": "chise_01", "name": "千世", "shame": 90, "lust": 10, "ob": 20, "edge": 10, "reb": 0, "s_b": 60, "s_a": 0, "s_v": 0, "s_c": 0, "s_m": 0, "exh": 0, "sem": 0, "tags": ["怕黑", "容易害羞", "被触碰胸部会颤抖"]},
		{"id": "aru_01", "name": "阿露", "shame": 85, "lust": 20, "ob": 10, "edge": 20, "reb": 60, "s_b": 0, "s_a": 0, "s_v": 0, "s_c": 0, "s_m": 0, "exh": 5, "sem": 0, "tags": ["笨蛋美人", "强行装酷", "容易破防"]},
		{"id": "mutsuki_01", "name": "睦月", "shame": 70, "lust": 40, "ob": 30, "edge": 60, "reb": 40, "s_b": 0, "s_a": 0, "s_v": 0, "s_c": 40, "s_m": 0, "exh": 0, "sem": 0, "tags": ["小恶魔", "喜欢捉弄人", "内心其实很害羞"]},
		{"id": "yuuka_01", "name": "优香", "shame": 95, "lust": 5, "ob": 5, "edge": 80, "reb": 50, "s_b": 0, "s_a": 0, "s_v": 20, "s_c": 0, "s_m": 0, "exh": 0, "sem": 0, "tags": ["计算狂", "大腿丰满", "理智容易崩溃"]},
		{"id": "noa_01", "name": "诺亚", "shame": 40, "lust": 60, "ob": 70, "edge": 90, "reb": 0, "s_b": 0, "s_a": 0, "s_v": 0, "s_c": 0, "s_m": 50, "exh": 40, "sem": 0, "tags": ["白发红眼", "过目不忘", "喜欢记录主人的声音"]},
		{"id": "asuna_01", "name": "明日奈", "shame": 5, "lust": 95, "ob": 95, "edge": 5, "reb": 0, "s_b": 70, "s_a": 0, "s_v": 80, "s_c": 0, "s_m": 0, "exh": 80, "sem": 60, "tags": ["黄金猎犬", "无心机", "肉便器潜质"]},
		{"id": "karin_01", "name": "花凛", "shame": 80, "lust": 30, "ob": 40, "edge": 40, "reb": 20, "s_b": 0, "s_a": 70, "s_v": 0, "s_c": 0, "s_m": 0, "exh": 10, "sem": 0, "tags": ["黑皮女仆", "容易不好意思", "后庭敏感"]},
		{"id": "neru_01", "name": "妮露", "shame": 85, "lust": 15, "ob": 0, "edge": 50, "reb": 95, "s_b": 0, "s_a": 0, "s_v": 0, "s_c": 30, "s_m": 0, "exh": 0, "sem": 0, "tags": ["不良少女", "傲娇", "被夸奖会暴走"]},
		{"id": "toki_01", "name": "时", "shame": 30, "lust": 20, "ob": 80, "edge": 95, "reb": 0, "s_b": 0, "s_a": 0, "s_v": 0, "s_c": 0, "s_m": 0, "exh": 20, "sem": 0, "tags": ["三无女仆", "和平时完全没变化", "面瘫"]},
		{"id": "shiroko_01", "name": "白子", "shame": 45, "lust": 75, "ob": 65, "edge": 70, "reb": 0, "s_b": 0, "s_a": 0, "s_v": 50, "s_c": 0, "s_m": 60, "exh": 0, "sem": 70, "tags": ["狼耳", "行动派", "喜欢运动", "体液敏感"]}
	]

	for t in targets_data:
		var c = CharacterData.new()
		c.id = t["id"]
		c.char_name = t["name"]
		c.stats["shame"]["level"] = t["shame"]
		c.stats["lust"]["level"] = t["lust"]
		c.stats["devotion"]["level"] = 0
		c.stats["yuri_obedience"]["level"] = t["ob"]
		c.stats["edging_control"]["level"] = t["edge"]
		c.stats["rebellion"]["level"] = t["reb"]
		c.stats["sensory_B"]["level"] = t["s_b"]
		c.stats["sensory_A"]["level"] = t["s_a"]
		c.stats["sensory_V"]["level"] = t["s_v"]
		c.stats["sensory_C"]["level"] = t["s_c"]
		c.stats["sensory_M"]["level"] = t["s_m"]
		c.stats["exhibitionism"]["level"] = t["exh"]
		c.stats["semen_addiction"]["level"] = t["sem"]
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
	vbox.add_theme_constant_override("separation", 15)
	var margins = MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 20)
	margins.add_theme_constant_override("margin_right", 20)
	margins.add_theme_constant_override("margin_top", 20)
	margins.add_theme_constant_override("margin_bottom", 150) # [Web/手机端安全区] 加大留白，防底栏与系统键盘遮挡
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
	time_label.custom_minimum_size.y = 50
	time_label.add_theme_font_size_override("normal_font_size", 26)
	time_label.add_theme_font_size_override("bold_font_size", 26)
	time_label.add_theme_font_override("normal_font", custom_font)
	time_label.add_theme_font_override("bold_font", custom_font)
	header_box.add_child(time_label)
	
	var roster_btn = Button.new()
	roster_btn.text = " 📋 查看后宫 "
	roster_btn.add_theme_font_size_override("font_size", 26)
	roster_btn.add_theme_font_override("font", custom_font)
	roster_btn.pressed.connect(_on_roster_button_pressed)
	header_box.add_child(roster_btn)
	
	var help_btn = Button.new()
	help_btn.text = " 📖 调教指南 "
	help_btn.add_theme_font_size_override("font_size", 26)
	help_btn.add_theme_font_override("font", custom_font)
	help_btn.pressed.connect(_on_help_button_pressed)
	header_box.add_child(help_btn)
	
	var settings_btn = Button.new()
	settings_btn.text = " ⚙️ 设置 "
	settings_btn.add_theme_font_size_override("font_size", 26)
	settings_btn.add_theme_font_override("font", custom_font)
	settings_btn.pressed.connect(_on_settings_button_pressed)
	header_box.add_child(settings_btn)
	
	# 初始化不可见状态的全局设置开关
	koujo_toggle = CheckButton.new()
	koujo_toggle.text = "开启 LLM 口上反馈 (跑骰后自动生成对话)"
	koujo_toggle.add_theme_font_size_override("font_size", 20)
	koujo_toggle.add_theme_font_override("font", custom_font)
	koujo_toggle.button_pressed = true # MVP默认开启
	
	hide_thinking_toggle = CheckButton.new()
	hide_thinking_toggle.text = "仅展示正文 (隐藏大模型思考过程)"
	hide_thinking_toggle.add_theme_font_size_override("font_size", 20)
	hide_thinking_toggle.add_theme_font_override("font", custom_font)
	hide_thinking_toggle.button_pressed = false # MVP默认关闭
	
	# 输出框 (RichTextLabel)
	output_log = RichTextLabel.new()
	output_log.bbcode_enabled = true
	output_log.scroll_following = true
	output_log.selection_enabled = true # 允许玩家使用鼠标拖拽选中文字
	output_log.context_menu_enabled = true # 允许玩家右键呼出复制菜单
	output_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_log.add_theme_font_size_override("normal_font_size", 28)
	output_log.add_theme_font_size_override("bold_font_size", 28)
	output_log.add_theme_font_override("normal_font", custom_font)
	output_log.add_theme_font_override("bold_font", custom_font)
	vbox.add_child(output_log)
	
	# --- 底部输入区 ---
	var input_area = HBoxContainer.new()
	input_area.add_theme_constant_override("separation", 15)
	vbox.add_child(input_area)
	
	# 极宽极高的输入框
	input_field = LineEdit.new()
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.custom_minimum_size.y = 80 # 确保好点击
	input_field.add_theme_font_size_override("font_size", 30)
	input_field.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	input_field.add_theme_font_override("font", custom_font)
	input_field.placeholder_text = "在此输入指令..."
	# 回车提交 (PC端为主)
	input_field.text_submitted.connect(_on_input_submitted)
	input_area.add_child(input_field)
	
	var send_btn = Button.new()
	send_btn.text = " ➤ 发送 "
	send_btn.custom_minimum_size.x = 120
	send_btn.add_theme_font_size_override("font_size", 30)
	send_btn.add_theme_font_override("font", custom_font)
	send_btn.pressed.connect(func(): _on_input_submitted(input_field.text))
	input_area.add_child(send_btn)
	
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
			_print_to_console("\n[color=green]====================================================[/color]")
			_print_to_console("[color=green]>>> 游戏初始化完毕！请通过下方输入框开始您的体验 <<<[/color]")
			_print_to_console("[color=yellow]【模式 1：上帝视角沙盒调教 (默认直接输入)】[/color]")
			_print_to_console("无需任何前缀，直接打字下达命令。引擎会自动跑暗骰结算。\n  [color=cyan]示例: 让日奈去调教千世的口交技术，可以粗暴一点。[/color]")
			
			_print_to_console("\n[color=yellow]【模式 2：沉浸式角色扮演对话 (/chat)】[/color]")
			_print_to_console("输入 '/chat 角色名(可多选) 你的对话'，直接与角色互动（带记忆隔离）。\n  [color=cyan]示例: /chat 日奈,千世 你们昨晚感觉怎么样呀？[/color]")
			
			_print_to_console("\n[color=yellow]【模式 3：系统管理员求助 (/miku)】[/color]")
			_print_to_console("输入 '/miku 你的问题' 召唤系统娘，她能看到所有隐藏数据。\n  [color=cyan]示例: /miku 帮我查一下千世为什么老是抗拒调教？[/color]")
			_print_to_console("[color=green]====================================================[/color]\n")
			
			input_field.placeholder_text = "直接输入调教指令，或 /chat 角色名 对话，或 /miku 问题"
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
					# 动态循环打印所有的硬性指标
					for stat_key in CharacterData.STAT_KEYS:
						var lvl = char_data.stats[stat_key]["level"]
						var exp = char_data.stats[stat_key]["exp"]
						msg += "   [color=gray]" + stat_key + ":[/color] LV " + str(lvl) + " (" + str(exp) + " Exp)\n"
						
					msg += "   [color=gray]Tags:[/color] [color=cyan]" + str(char_data.custom_tags) + "[/color]\n\n"
					_print_to_console(msg)
				current_state = AppState.IDLE
				return

			# 如果指令以 /miku 开头，进入元叙事聊天模式
			elif text.to_lower().begins_with("/miku "):
				mode = LLMClient.MODE_META
				send_text = text.substr(6)
				active_char_ids = ["miku_sys"]
				
			# 如果指令以 /chat 开头，进入角色扮演对话模式 (内存隔离关键)
			elif text.to_lower().begins_with("/chat "):
				mode = LLMClient.MODE_ROLEPLAY
				# 解析命令: /chat 日奈,千世 你好呀
				var parts = text.substr(6).split(" ", false, 1)
				if parts.size() > 0:
					# 兼容中文逗号和英文逗号，防止玩家切换输入法烦躁
					var names_str = parts[0].replace("，", ",")
					var input_names = names_str.split(",")
					for n in input_names:
						n = n.strip_edges()
						var found_id = ""
						for c in char_manager.get_all_characters():
							# 兼容玩家输入中文名或者英文ID
							if c.char_name == n or c.id == n:
								found_id = c.id
								break
						if found_id != "":
							active_char_ids.append(found_id)
						else:
							_print_to_console("[color=red]系统提示: 找不到角色 '" + n + "'[/color]")
				
				if parts.size() > 1:
					send_text = parts[1]
				else:
					send_text = "..." # 如果没写对话只@了人
				
			current_state = AppState.WAITING_FOR_LLM
			_print_to_console("[color=gray]...正在请求外部接口 (RPM 控制中)...[/color]")
			
			# 暂存请求状态，供回调函数存入历史
			current_request_mode = mode
			current_request_participants = active_char_ids
			
			# 如果是角色扮演或Miku聊天，把用户的话存入全局记忆池
			if mode == LLMClient.MODE_ROLEPLAY or mode == LLMClient.MODE_META:
				global_chat_pool.append({
					"role": "user",
					"content": send_text,
					"participants": active_char_ids.duplicate()
				})
			
			# 组装上下文发送（严格的记忆隔离与日记互通）
			var context = {
				"roster_data": {},
				"daily_logs": [],
				"active_char_names": []
			}
			
			var history_messages = []
			
			for char_data in char_manager.get_all_characters():
				# 在分配模式和Miku模式下，系统能看到所有人的简略面板，但不一定带独占记忆
				# 在扮演模式下，只有被点名的 active_char_ids 才会被送入上下文，彻底防串戏
				if mode == LLMClient.MODE_ROLEPLAY:
					if active_char_ids.has(char_data.id):
						context["roster_data"][char_data.id] = char_data.get_prompt_context(true) # 携带独占记忆
						if not context["active_char_names"].has(char_data.char_name):
							context["active_char_names"].append(char_data.char_name)
				else:
					# Assign 模式全看，但无独占记忆；Meta 模式全看
					context["roster_data"][char_data.id] = char_data.get_prompt_context(false)
					
			if mode == LLMClient.MODE_META:
				context["daily_logs"] = daily_system_logs
				# 提取 Miku 的专属对话历史
				for msg in global_chat_pool:
					if msg["participants"].has("miku_sys"):
						history_messages.append({"role": msg["role"], "content": msg["content"]})
						
			elif mode == LLMClient.MODE_ROLEPLAY:
				var filtered_logs = []
				for l in daily_system_logs:
					var relevant = false
					for c_id in active_char_ids:
						var c = char_manager.get_character(c_id)
						if c and l.find(c.char_name) != -1:
							relevant = true
					if relevant:
						filtered_logs.append(l)
				context["daily_logs"] = filtered_logs
				
				# 提取这些角色的交集历史对话
				for msg in global_chat_pool:
					var is_relevant = false
					for p in active_char_ids:
						if msg["participants"].has(p):
							is_relevant = true
					if is_relevant and not msg["participants"].has("miku_sys"):
						history_messages.append({"role": msg["role"], "content": msg["content"]})
				
			# 为了防止 Token 爆炸，限制历史记录最大条数 (比如取最后 10 条)
			if history_messages.size() > 10:
				history_messages = history_messages.slice(-10)
				
			llm_client.send_request(mode, send_text, context, history_messages)

# ---------------------------------------------------------
# 时间推进与顶部横幅更新
# ---------------------------------------------------------
func _update_header() -> void:
	var phase_name = PHASES[time_phase]
	time_label.text = "[color=yellow][b]【 第 " + str(current_day) + " 天 | " + phase_name + " 】[/b][/color]"

func _advance_time() -> void:
	time_phase += 1
	var trigger_report = false
	if time_phase == 4: # 4 = "🌙 傍晚 (战报结算)"
		trigger_report = true
		
	if time_phase >= PHASES.size():
		time_phase = 0
		current_day += 1
		daily_system_logs.clear() # 跨天清空日志
	_update_header()
	
	if trigger_report:
		_generate_daily_report()

func _generate_daily_report() -> void:
	if daily_system_logs.size() == 0:
		_print_to_console("\n[color=gray]今日无事发生...系统自动跳过晚报结算。[/color]")
		_advance_time()
		return
		
	current_state = AppState.WAITING_FOR_LLM
	_print_to_console("\n[color=yellow]...正在整理今日所有行为日志，生成最终调教晚报...[/color]")
	current_request_mode = "report"
	
	var context = {"roster_data": {}, "daily_logs": daily_system_logs.duplicate()}
	for char_data in char_manager.get_all_characters():
		context["roster_data"][char_data.id] = char_data.get_prompt_context(false)
		
	llm_client.send_request("report", "请对今天的日志进行总结汇报。", context, [])

# ---------------------------------------------------------
# 角色图鉴弹窗刷新
# ---------------------------------------------------------
func _on_roster_button_pressed() -> void:
	if stats_window == null or not is_instance_valid(stats_window):
		push_warning("stats_window is null, rebuilding...")
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
		# 尝试获取已加载的字体
		var custom_font = load("res://Fonts/SmileySans-Oblique.otf")
		stats_content.add_theme_font_override("normal_font", custom_font)
		stats_content.add_theme_font_override("bold_font", custom_font)
		scroll.add_child(stats_content)
		
	stats_window.popup_centered()
	var bbcode = "[center][b]=== 系统运行中角色名单与属性总览 ===[/b][/center]\n\n"
	
	for char_data in char_manager.get_all_characters():
		bbcode += "[b]" + char_data.char_name + "[/b] (ID: " + char_data.id + ")"
		
		# 判断是否可以做调教师 (Devotion >= 50)
		if char_data.stats["devotion"]["level"] >= 50:
			bbcode += " [color=pink][b](⭐可担任调教师)[/b][/color]"
		bbcode += "\n"
		
		# 动态循环打印所有的硬性指标
		for stat_key in CharacterData.STAT_KEYS:
			var lvl = char_data.stats[stat_key]["level"]
			var exp = char_data.stats[stat_key]["exp"]
			bbcode += "   [color=gray]" + stat_key + ":[/color] LV " + str(lvl) + " (" + str(exp) + " Exp)\n"
		
		bbcode += "   [color=gray]Tags:[/color] [color=cyan]" + str(char_data.custom_tags) + "[/color]\n\n"
		
	stats_content.text = bbcode

# ---------------------------------------------------------
# 系统指南弹窗
# ---------------------------------------------------------
func _on_help_button_pressed() -> void:
	if help_window == null or not is_instance_valid(help_window):
		help_window = Window.new()
		help_window.title = "东方调教典 - 系统指南"
		help_window.size = Vector2i(800, 600)
		help_window.visible = false
		help_window.exclusive = true
		help_window.close_requested.connect(func(): help_window.hide())
		add_child(help_window)
		
		var scroll = ScrollContainer.new()
		scroll.set_anchors_preset(PRESET_FULL_RECT)
		help_window.add_child(scroll)
		
		help_content = RichTextLabel.new()
		help_content.bbcode_enabled = true
		help_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		help_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		help_content.custom_minimum_size = Vector2(780, 0)
		help_content.add_theme_font_size_override("normal_font_size", 20)
		help_content.add_theme_font_size_override("bold_font_size", 20)
		var custom_font = load("res://Fonts/SmileySans-Oblique.otf")
		help_content.add_theme_font_override("normal_font", custom_font)
		help_content.add_theme_font_override("bold_font", custom_font)
		scroll.add_child(help_content)
		
	help_window.popup_centered()
	var help_text = "[center][b]=== 东方调教典 ===[/b][/center]\n\n"
	help_text += "[b]【核心暗骰公式】[/b]\n"
	help_text += "成功率 = 顺从(基础) + 欲望/10 - 防御属性/10 + 导师技巧 + LLM动作修正 + 目标部位感觉/10\n\n"
	help_text += "[b]【多重高潮与寸止系统】[/b]\n"
	help_text += "调教产生的临时快感会积攒在各个部位。寸止忍耐(edging_control)决定了角色能承受多少上限而不走火。当下达【允许高潮】指令时，所有积攒满的部位会同时引爆，产生恐怖的指数级经验暴击，并大幅降低羞耻心！\n\n"
	help_text += "[b]【常见属性对照表】[/b]\n"
	for k in STAT_NAMES_CN.keys():
		help_text += "- " + k + " : " + STAT_NAMES_CN[k] + "\n"
		
	help_content.text = help_text

# ---------------------------------------------------------
# 系统设置弹窗
# ---------------------------------------------------------
func _on_settings_button_pressed() -> void:
	if settings_window == null or not is_instance_valid(settings_window):
		settings_window = Window.new()
		settings_window.title = "系统设置 (Settings)"
		settings_window.size = Vector2i(450, 300)
		settings_window.visible = false
		settings_window.exclusive = true
		settings_window.close_requested.connect(func(): settings_window.hide())
		add_child(settings_window)
		
		var vbox = VBoxContainer.new()
		vbox.set_anchors_preset(PRESET_FULL_RECT)
		vbox.add_theme_constant_override("separation", 15)
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_child(vbox)
		settings_window.add_child(margin)
		
		# 将早就在 _build_ui 实例化好的按钮动态挂载进弹窗
		if koujo_toggle.get_parent():
			koujo_toggle.get_parent().remove_child(koujo_toggle)
		vbox.add_child(koujo_toggle)
		
		if hide_thinking_toggle.get_parent():
			hide_thinking_toggle.get_parent().remove_child(hide_thinking_toggle)
		vbox.add_child(hide_thinking_toggle)
		
	settings_window.popup_centered()

# ---------------------------------------------------------
# 回调：LLM 处理完毕
# ---------------------------------------------------------
func _on_llm_reply(reply_text: String) -> void:
	current_state = AppState.IDLE
	
	# 通过 ToolRegistry 拦截和处理所有的伪函数（JSON 数组或特殊宏标签），并且剔除了 thinking 过程
	var clean_text = tool_registry.parse_and_route(reply_text, current_request_mode)
	
	# 动态组装前端显示文本：判断是否要显示思考过程
	var text_to_print = clean_text
	if hide_thinking_toggle != null and not hide_thinking_toggle.button_pressed:
		var think_match = RegEx.create_from_string("(?s)<think(?:ing)?>.*?</think(?:ing)?>").search(reply_text)
		if think_match:
			text_to_print = "[color=gray]" + think_match.get_string() + "[/color]\n\n" + clean_text
			
	_print_to_console("[color=pink]System/LLM返回 >\n" + text_to_print + "[/color]")
	
	# 如果是角色扮演或Miku聊天，把剔除了废话的纯净正文存入全局记忆池
	if current_request_mode == LLMClient.MODE_ROLEPLAY or current_request_mode == LLMClient.MODE_META:
		global_chat_pool.append({
			"role": "assistant",
			"content": clean_text,
			"participants": current_request_participants.duplicate()
		})
	
	# 如果当前队列里有解析出来的宏观任务，自动在后台推演并打印结算
	if task_manager.current_turn_tasks.size() > 0:
		var sim_engine = SimulationEngine.new()
		var logs = task_manager.execute_all_tasks(char_manager, sim_engine)
		_print_to_console("\n[color=yellow]--- Godot 后台自动推演结算开始 ---[/color]")
		var combined_logs = ""
		for l in logs:
			_print_to_console("[color=gray]" + l + "[/color]")
			daily_system_logs.append(l)
			combined_logs += l + "\n"
		_print_to_console("[color=yellow]--- 推演完毕 ---[/color]\n")
		sim_engine.queue_free()
		
		# 判断是否需要请求口上反馈
		if koujo_toggle.button_pressed:
			current_state = AppState.WAITING_FOR_LLM
			_print_to_console("[color=gray]...正在请求 LLM 生成调教口上反馈...[/color]")
			current_request_mode = "koujo"
			var context = {"roster_data": {}, "daily_logs": []}
			
			# 筛选出本回合互动的角色面板发送给大模型
			for char_data in char_manager.get_all_characters():
				# 此处简单起见，如果日志中提到了该名字，就压入面板
				if combined_logs.find(char_data.char_name) != -1:
					context["roster_data"][char_data.id] = char_data.get_prompt_context(true)
					
			llm_client.send_request("koujo", "【系统战报】：\n" + combined_logs, context, [])
			return # 先不推进时间，等待口上回调
		else:
			# 推演完成后自动推进时间阶段
			_advance_time()
	elif current_request_mode == "koujo":
		# 如果刚刚执行完口上反馈，推进时间
		_advance_time()
	elif current_request_mode == "report":
		# 如果刚刚执行完夜晚简报，自动进入深夜夜伽
		_advance_time()

func _on_llm_error(err_msg: String) -> void:
	current_state = AppState.IDLE
	_print_to_console("[color=red]网络/解析报错 > " + err_msg + "[/color]")
