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
var stats_vbox: VBoxContainer
var help_window: Window
var help_content: RichTextLabel
var settings_window: Window
var lore_window: Window
var lore_text_edit: TextEdit
var current_lore_char_id: String
var koujo_toggle: CheckButton
var hide_thinking_toggle: CheckButton
var save_window: Window
var save_list_vbox: VBoxContainer
var save_name_input: LineEdit
var llm_client: LLMClient
var char_manager: CharacterManager
var task_manager: TaskManager
var tool_registry: ToolRegistry

var pending_system_logs: Array[String] = []

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
	tool_registry.on_system_log_generated.connect(func(log_text: String):
		pending_system_logs.append(log_text)
	)
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
	
	var save_btn = Button.new()
	save_btn.text = " 💾 存/读档 "
	save_btn.add_theme_font_size_override("font_size", 26)
	save_btn.add_theme_font_override("font", custom_font)
	save_btn.pressed.connect(_on_save_menu_pressed)
	header_box.add_child(save_btn)
	
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
	
	var paste_btn = Button.new()
	paste_btn.text = " 📋 粘贴 "
	paste_btn.custom_minimum_size.x = 100
	paste_btn.add_theme_font_size_override("font_size", 30)
	paste_btn.add_theme_font_override("font", custom_font)
	paste_btn.pressed.connect(func():
		var clipboard_text = DisplayServer.clipboard_get()
		if clipboard_text != "":
			# 在当前光标位置或者直接追加文本
			input_field.text += clipboard_text
	)
	input_area.add_child(paste_btn)
	
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
			_print_to_console("输入 '/chat 角色名(可多选) 你的对话'，直接与角色互动（带记忆隔离）。\n  [color=cyan]示例: /chat 日奈,千世 你们昨晚感觉怎么样呀？[/color]\n大模型会根据剧情发展自动修改并提升角色的【属性等级】（言出法随，跳过挂机练级）。\n  [color=cyan]示例: /chat 优香 请你为我提供口交服务，我要提升你的技巧并降低你的反抗。[/color]")
			
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
				
			# 修复：必须在提取完 history_messages 之后，再把当前玩家说的话压入全局记忆池。
			# 否则这句最新的话会被当做历史记录发送一遍，又被当做 user_input 发送一遍，造成两次重复！
			if mode == LLMClient.MODE_ROLEPLAY or mode == LLMClient.MODE_META:
				global_chat_pool.append({
					"role": "user",
					"content": send_text,
					"participants": active_char_ids.duplicate()
				})
				
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
# 角色图鉴与调试面板弹窗刷新
# ---------------------------------------------------------
func _on_roster_button_pressed() -> void:
	var custom_font = load("res://Fonts/SmileySans-Oblique.otf")
	
	if stats_window == null or not is_instance_valid(stats_window):
		push_warning("stats_window is null, rebuilding...")
		# --- 角色图鉴弹窗 ---
		stats_window = Window.new()
		stats_window.title = "系统后台面板 - 角色状态档案与动态调试"
		stats_window.size = Vector2i(800, 700)
		stats_window.visible = false
		stats_window.exclusive = true
		stats_window.close_requested.connect(func(): stats_window.hide())
		add_child(stats_window)
		
		var scroll = ScrollContainer.new()
		scroll.set_anchors_preset(PRESET_FULL_RECT)
		stats_window.add_child(scroll)
		
		stats_vbox = VBoxContainer.new()
		stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_vbox.add_theme_constant_override("separation", 20)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		margin.add_child(stats_vbox)
		
		scroll.add_child(margin)
		
	# 每次打开前清空旧的数据节点
	for child in stats_vbox.get_children():
		child.queue_free()
		
	var title_lbl = Label.new()
	title_lbl.text = "=== 系统运行中角色名单与属性总览 ==="
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_font_override("font", custom_font)
	stats_vbox.add_child(title_lbl)
	
	for char_data in char_manager.get_all_characters():
		var panel = PanelContainer.new()
		stats_vbox.add_child(panel)
		
		var char_vbox = VBoxContainer.new()
		var p_margin = MarginContainer.new()
		p_margin.add_theme_constant_override("margin_left", 15)
		p_margin.add_theme_constant_override("margin_right", 15)
		p_margin.add_theme_constant_override("margin_top", 15)
		p_margin.add_theme_constant_override("margin_bottom", 15)
		p_margin.add_child(char_vbox)
		panel.add_child(p_margin)
		
		# 角色名与徽章
		var name_lbl = Label.new()
		var badge = " [color=pink](⭐可担任调教师)[/color]" if char_data.stats["devotion"]["level"] >= 50 else ""
		name_lbl.text = char_data.char_name + " (ID: " + char_data.id + ")"
		if badge != "":
			var r = RichTextLabel.new()
			r.bbcode_enabled = true
			r.text = "[b]" + name_lbl.text + badge + "[/b]"
			r.fit_content = true
			r.add_theme_font_size_override("normal_font_size", 22)
			r.add_theme_font_size_override("bold_font_size", 22)
			r.add_theme_font_override("normal_font", custom_font)
			r.add_theme_font_override("bold_font", custom_font)
			char_vbox.add_child(r)
		else:
			name_lbl.add_theme_font_size_override("font_size", 22)
			name_lbl.add_theme_font_override("font", custom_font)
			char_vbox.add_child(name_lbl)
		
		# 属性动态调节网格 (每行显示 3 或 4 个属性)
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 30)
		grid.add_theme_constant_override("v_separation", 10)
		char_vbox.add_child(grid)
		
		for stat_key in CharacterData.STAT_KEYS:
			var stat_hbox = HBoxContainer.new()
			
			var s_lbl = Label.new()
			s_lbl.text = stat_key + ":"
			s_lbl.custom_minimum_size.x = 140
			s_lbl.add_theme_font_size_override("font_size", 18)
			s_lbl.add_theme_font_override("font", custom_font)
			s_lbl.add_theme_color_override("font_color", Color.LIGHT_GRAY)
			stat_hbox.add_child(s_lbl)
			
			var spin = SpinBox.new()
			spin.min_value = 0
			spin.max_value = 100
			spin.value = char_data.stats[stat_key]["level"]
			spin.custom_minimum_size.x = 80
			# 当数值改变时，使用 lambda 表达式将修改同步到底层
			var current_char_id = char_data.id
			var current_stat_key = stat_key
			spin.value_changed.connect(func(new_val: float):
				var target = char_manager.get_character(current_char_id)
				if target:
					target.set_stat_level(current_stat_key, int(new_val))
			)
			stat_hbox.add_child(spin)
			
			grid.add_child(stat_hbox)
			
		# Tags 设定书编辑按钮
		var lore_btn = Button.new()
		lore_btn.text = " 📝 编辑专属设定书 (Lorebook) "
		lore_btn.add_theme_font_size_override("font_size", 20)
		lore_btn.add_theme_font_override("font", custom_font)
		
		var char_id_for_lore = char_data.id
		lore_btn.pressed.connect(func(): _open_lore_editor(char_id_for_lore))
		char_vbox.add_child(lore_btn)
		
	stats_window.popup_centered()

# ---------------------------------------------------------
# Lorebook 编辑器弹窗
# ---------------------------------------------------------
func _open_lore_editor(c_id: String) -> void:
	current_lore_char_id = c_id
	var char_data = char_manager.get_character(c_id)
	if not char_data: return
	
	if lore_window == null or not is_instance_valid(lore_window):
		lore_window = Window.new()
		lore_window.title = "世界设定书 (Lorebook)"
		lore_window.size = Vector2i(700, 500)
		lore_window.visible = false
		lore_window.exclusive = true
		lore_window.close_requested.connect(func(): lore_window.hide())
		add_child(lore_window)
		
		var vbox = VBoxContainer.new()
		vbox.set_anchors_preset(PRESET_FULL_RECT)
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 15)
		margin.add_theme_constant_override("margin_right", 15)
		margin.add_theme_constant_override("margin_top", 15)
		margin.add_theme_constant_override("margin_bottom", 15)
		margin.set_anchors_preset(PRESET_FULL_RECT)
		margin.add_child(vbox)
		lore_window.add_child(margin)
		
		var tip = Label.new()
		tip.text = "在此处可以畅所欲言地输入角色的背景、隐藏癖好、变态体质等设定。\n不需要加引号和括号，像写日记一样直接写即可。"
		var custom_font = load("res://Fonts/SmileySans-Oblique.otf")
		tip.add_theme_font_override("font", custom_font)
		tip.add_theme_color_override("font_color", Color.LIGHT_GRAY)
		vbox.add_child(tip)
		
		lore_text_edit = TextEdit.new()
		lore_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lore_text_edit.add_theme_font_size_override("font_size", 22)
		lore_text_edit.add_theme_font_override("font", custom_font)
		lore_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		vbox.add_child(lore_text_edit)
		
		var save_btn = Button.new()
		save_btn.text = " 💾 保存设定并关闭 "
		save_btn.add_theme_font_size_override("font_size", 24)
		save_btn.add_theme_font_override("font", custom_font)
		save_btn.pressed.connect(_save_lore_and_close)
		vbox.add_child(save_btn)
		
	lore_window.title = char_data.char_name + " 的专属设定书"
	# 将之前散落的数组通过换行符合并成一大段文字
	lore_text_edit.text = "\n".join(char_data.custom_tags)
	lore_window.popup_centered()

func _save_lore_and_close() -> void:
	var char_data = char_manager.get_character(current_lore_char_id)
	if char_data:
		# 直接把整个长文本作为唯一的一个元素塞入 custom_tags
		char_data.custom_tags.clear()
		if lore_text_edit.text.strip_edges() != "":
			char_data.custom_tags.append(lore_text_edit.text.strip_edges())
	lore_window.hide()

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
	help_text += "只要在指令中要求开启寸止，成功执行动作后会额外进行一次【寸止检定】（忍耐度 vs 固定难度）。如果忍住了，就能叠加一层【高潮倍率】。当下达【允许高潮】指令时，所有积攒的高潮倍率会同时引爆，产生恐怖的指数级经验暴击，并大幅降低羞耻心！\n\n"
	help_text += "[b]【对数升级经验表】[/b]\n"
	help_text += "单次普通动作获得 100 经验，大成功 300 经验。随着等级升高，所需经验会平滑增长：\n"
	help_text += " 0 -> 1 级: 100 Exp\n"
	help_text += " 10 -> 11 级: 800 Exp\n"
	help_text += " 20 -> 21 级: 1,900 Exp\n"
	help_text += " 30 -> 31 级: 3,400 Exp\n"
	help_text += " 40 -> 41 级: 5,300 Exp\n"
	help_text += " 50 -> 51 级: 7,600 Exp\n"
	help_text += " 60 -> 61 级: 10,300 Exp\n"
	help_text += " 70 -> 71 级: 13,400 Exp\n"
	help_text += " 80 -> 81 级: 16,900 Exp\n"
	help_text += " 90 -> 91 级: 20,800 Exp\n"
	help_text += "（注：后期必须依靠多重高潮的指数级暴击才能快速升级）\n\n"
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
# 存读档管理弹窗
# ---------------------------------------------------------
func _on_save_menu_pressed() -> void:
	if save_window == null or not is_instance_valid(save_window):
		save_window = Window.new()
		save_window.title = "系统存储 (Save/Load)"
		save_window.size = Vector2i(600, 500)
		save_window.visible = false
		save_window.exclusive = true
		save_window.close_requested.connect(func(): save_window.hide())
		add_child(save_window)
		
		var vbox = VBoxContainer.new()
		vbox.set_anchors_preset(PRESET_FULL_RECT)
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		margin.set_anchors_preset(PRESET_FULL_RECT)
		margin.add_child(vbox)
		save_window.add_child(margin)
		
		var custom_font = load("res://Fonts/SmileySans-Oblique.otf")
		
		# 顶部新建存档区
		var top_hbox = HBoxContainer.new()
		save_name_input = LineEdit.new()
		save_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		save_name_input.placeholder_text = "输入新存档名称..."
		save_name_input.add_theme_font_override("font", custom_font)
		top_hbox.add_child(save_name_input)
		
		var create_save_btn = Button.new()
		create_save_btn.text = " ➕ 创建新存档 "
		create_save_btn.add_theme_font_override("font", custom_font)
		create_save_btn.pressed.connect(func(): 
			if save_name_input.text.strip_edges() != "":
				_save_game(save_name_input.text.strip_edges())
				save_name_input.text = ""
				_refresh_save_list()
		)
		top_hbox.add_child(create_save_btn)
		vbox.add_child(top_hbox)
		
		var sep = HSeparator.new()
		vbox.add_child(sep)
		
		# 存档列表区
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		save_list_vbox = VBoxContainer.new()
		save_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(save_list_vbox)
		vbox.add_child(scroll)
		
	_refresh_save_list()
	save_window.popup_centered()

func _save_game(save_name: String) -> void:
	var save_dir = "user://Saves"
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
		
	var save_data = {
		"current_day": current_day,
		"time_phase": time_phase,
		"daily_system_logs": daily_system_logs,
		"global_chat_pool": global_chat_pool,
		"characters": []
	}
	
	for c in char_manager.get_all_characters():
		save_data["characters"].append(c.to_dict())
		
	var file_path = save_dir + "/" + save_name + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		_print_to_console("\n[color=green]系统提示: 游戏进度已保存至 -> " + save_name + "[/color]")

func _load_game(file_name: String) -> void:
	var file_path = "user://Saves/" + file_name
	if not FileAccess.file_exists(file_path): return
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_str = file.get_as_text()
	var json = JSON.new()
	if json.parse(json_str) == OK:
		var data = json.data
		current_day = data.get("current_day", 1)
		time_phase = data.get("time_phase", 0)
		
		daily_system_logs.clear()
		var loaded_logs = data.get("daily_system_logs", [])
		if typeof(loaded_logs) == TYPE_ARRAY:
			for l in loaded_logs: daily_system_logs.append(String(l))
			
		global_chat_pool.clear()
		var loaded_pool = data.get("global_chat_pool", [])
		if typeof(loaded_pool) == TYPE_ARRAY:
			for p in loaded_pool: global_chat_pool.append(p as Dictionary)
		
		var loaded_chars = data.get("characters", [])
		for c_data in loaded_chars:
			var existing_c = char_manager.get_character(c_data["id"])
			if existing_c:
				existing_c.load_from_dict(c_data)
				
		_update_header()
		save_window.hide()
		output_log.text = ""
		_print_to_console("[color=green]>>> 读档成功！欢迎回来，Master。 <<<[/color]")
		_print_to_console("[color=gray]加载了存档: " + file_name + " | 当前时间: 第 " + str(current_day) + " 天[/color]")

func _refresh_save_list() -> void:
	for child in save_list_vbox.get_children():
		child.queue_free()
		
	var custom_font = load("res://Fonts/SmileySans-Oblique.otf")
	var save_dir = "user://Saves"
	if not DirAccess.dir_exists_absolute(save_dir): return
	
	var dir = DirAccess.open(save_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var hbox = HBoxContainer.new()
				var lbl = Label.new()
				lbl.text = "📄 " + file_name.replace(".json", "")
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl.add_theme_font_override("font", custom_font)
				hbox.add_child(lbl)
				
				var load_btn = Button.new()
				load_btn.text = "读取"
				load_btn.add_theme_font_override("font", custom_font)
				var fn_for_load = file_name
				load_btn.pressed.connect(func(): _load_game(fn_for_load))
				hbox.add_child(load_btn)
				
				var del_btn = Button.new()
				del_btn.text = "删除"
				del_btn.add_theme_font_override("font", custom_font)
				var fn_for_del = file_name
				del_btn.pressed.connect(func(): 
					DirAccess.remove_absolute("user://Saves/" + fn_for_del)
					_refresh_save_list()
				)
				hbox.add_child(del_btn)
				
				save_list_vbox.add_child(hbox)
			file_name = dir.get_next()

# ---------------------------------------------------------
# 回调：LLM 处理完毕
# ---------------------------------------------------------
func _on_llm_reply(reply_text: String) -> void:
	current_state = AppState.IDLE
	
	# ======= 调试打印：输出最原始的、未经任何处理的大模型返回 =======
	print("\n[RAW LLM RESPONSE START]")
	print(reply_text)
	print("[RAW LLM RESPONSE END]\n")
	# =========================================================
	
	pending_system_logs.clear() # 执行前清空
	
	# 通过 ToolRegistry 拦截和处理所有的伪函数（JSON 数组或特殊宏标签）
	var clean_text = tool_registry.parse_and_route(reply_text, current_request_mode)
	
	# 过滤大模型的思考过程（确保不会存入历史记录污染下文）
	# 注意：因为使用了预填充，大模型的输出往往是从思考过程的后半截开始，所以必须从 ^ 匹配到第一个 </thinking>
	var regex_think = RegEx.new()
	regex_think.compile("(?s)^.*?</think(?:ing)?>")
	var text_without_think = regex_think.sub(clean_text, "", true)
	
	var final_pure_text = text_without_think.strip_edges()
	
	# 动态组装前端显示文本：判断是否要显示思考过程
	var text_to_print = final_pure_text
	if hide_thinking_toggle != null and not hide_thinking_toggle.button_pressed:
		var think_match = regex_think.search(reply_text)
		if think_match:
			# 将抠出来的半截思考过程染成灰色
			var thoughts = think_match.get_string().replace("</thinking>", "").replace("</think>", "").strip_edges()
			if thoughts != "":
				text_to_print = "[color=gray]" + thoughts + "[/color]\n\n" + final_pure_text
			
	_print_to_console("[color=pink]System/LLM返回 >\n" + text_to_print + "[/color]")
	
	# 如果有截获的系统提示（如数值变动），在对话后方统一打印出一个总结区域
	if pending_system_logs.size() > 0:
		var summary = "\n[color=cyan]=== 互动属性结算 ===[/color]\n"
		for log in pending_system_logs:
			summary += "[color=yellow]" + log + "[/color]\n"
		_print_to_console(summary)
	
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
