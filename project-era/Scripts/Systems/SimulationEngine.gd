class_name SimulationEngine
extends Node

# ==============================================================================
# project_ERA 核心推演引擎 (Simulation Engine)
# 职责：在单一帧内，处理回合内的多重连续指令序列，执行 COC 暗骰检定，
# 管理临时快感槽，以及结算多重高潮。绝对不依赖 LLM 请求。
# ==============================================================================

# --- 模拟运行中的“本回合临时快感槽” ---
var temp_pleasure_pool: Dictionary = {
	"sensory_M": 0, "sensory_B": 0, "sensory_A": 0, 
	"sensory_C": 0, "sensory_V": 0, "sensory_P": 0
}

# ---------------------------------------------------------
# 主入口：执行一个指令序列 (Task Sequence)
# ---------------------------------------------------------
func process_task_sequence(target: CharacterData, instructor: CharacterData, is_edging: bool, actions: Array[Dictionary]) -> Array[String]:
	var turn_logs: Array[String] = []
	var inst_name = instructor.char_name if instructor != null else "无人/系统"
	var mode_text = "【寸止模式】" if is_edging else "【普通模式】"
	turn_logs.append("\n[color=yellow]=== [ " + inst_name + " ] 开始对 [ " + target.char_name + " ] 进行回合连招调教 " + mode_text + " ===[/color]")
	
	# 重置临时快感槽
	for key in temp_pleasure_pool.keys():
		temp_pleasure_pool[key] = 0
		
	# 遍历执行每个动作
	for action in actions:
		var result_log = _execute_single_action(target, instructor, action, is_edging)
		turn_logs.append(result_log)
			
	turn_logs.append("[color=yellow]=== [ " + inst_name + " ] 对 [ " + target.char_name + " ] 的调教回合结束 ===[/color]\n")
	return turn_logs

# ---------------------------------------------------------
# 单一指令执行与 COC 检定核心逻辑 (动态解析版本)
# ---------------------------------------------------------
func _execute_single_action(target: CharacterData, instructor: CharacterData, action: Dictionary, is_edging: bool) -> String:
	var cmd_name = action.get("action_flavor", "未知动作")
	var cmd_type = action.get("type", "NORMAL")
	
	# 1. 终结指令：在寸止模式下引爆多重高潮
	if cmd_type == "FINISHER":
		return _process_orgasm_finisher(target)
	
	# 安全检查：如果 LLM 给的 key 不是硬指标，兜底为 yuri_obedience
	var check_stat = action.get("check_stat", "yuri_obedience")
	var reward_stat = action.get("reward_stat", "yuri_obedience")
	var defend_stat = action.get("defend_stat", "shame") # 可以是 shame, rebellion, 或者 none
	
	if not CharacterData.STAT_KEYS.has(check_stat): check_stat = "yuri_obedience"
	if not CharacterData.STAT_KEYS.has(reward_stat): reward_stat = "yuri_obedience"
	if defend_stat != "none" and not CharacterData.STAT_KEYS.has(defend_stat): defend_stat = "shame"

	# 2. 逆向指令：教养与禁欲
	if cmd_type == "REVERSE":
		var reduce_amount = action.get("difficulty_modifier", 0) # 借用 difficulty_modifier 字段当做扣减值
		reduce_amount = clamp(abs(int(reduce_amount)), 10, 500)
		target.reduce_exp(check_stat, reduce_amount)
		return "[" + cmd_name + "] 成功执行逆向调教。目标属性 " + check_stat + " 经验扣减。 [" + check_stat + " -" + str(reduce_amount) + " Exp]"

	# ================= COC 对抗暗骰计算 =================
	var ob_lvl = target.stats["yuri_obedience"]["level"]
	var lust_lvl = target.stats["lust"]["level"]
	
	var defend_lvl = 0
	if defend_stat != "none":
		defend_lvl = target.stats[defend_stat]["level"]
	
	# 核心机制：百合顺从是基底成功率。欲望和防御属性作为修正 (如80点羞耻心对应-8修正)
	var lust_mod = int(lust_lvl / 10.0)
	var defend_mod = int(defend_lvl / 10.0)
	var base_success = ob_lvl + lust_mod - defend_mod
	var instructor_bonus = 20 if instructor != null else 0 
	
	var cmd_modifier = clamp(int(action.get("difficulty_modifier", 0)), -50, 50)
	var part_bonus = int(target.stats[check_stat]["level"] / 10.0)
		
	var final_chance_raw = base_success + instructor_bonus + cmd_modifier + part_bonus
	var final_chance = clamp(final_chance_raw, 5, 95) 
	
	var roll = randi() % 100 + 1 
	var is_success = roll <= final_chance
	var is_critical = roll <= final_chance / 5 
	
	var log_str = "\n[color=lightblue][" + cmd_name + "][/color] 正在进行 COC 判定...\n"
	log_str += "  > 计算过程: 顺从基础(" + str(ob_lvl) + ") + 欲望修正(" + str(lust_mod) + ") - 阻力修正[" + defend_stat + "](" + str(defend_mod) + ")"
	log_str += " + 导师加成(" + str(instructor_bonus) + ") + 动作修正(" + str(cmd_modifier) + ") + 部位感觉修正(" + str(part_bonus) + ")\n"
	log_str += "  > = 理论成功率 (" + str(final_chance_raw) + "%) -> 实际补正后 (" + str(final_chance) + "%)\n"
	log_str += "  > 判定: " + str(final_chance) + "% | 掷骰: " + str(roll) + " -> "
	
	# ================= 结算结果 =================
	if is_success:
		log_str += "成功"
		if is_critical: log_str += "(大成功!)"
		
		# 获得目标部位的基础经验
		var base_part_exp = 100 if not is_critical else 300
		target.add_exp(reward_stat, base_part_exp)
		log_str += " [" + reward_stat + " +" + str(base_part_exp) + " Exp]"
		
		# === 核心逻辑：临时快感与高潮系统 ===
		var pleasure_gain = 30 if not is_critical else 60
		if temp_pleasure_pool.has(reward_stat):
			temp_pleasure_pool[reward_stat] += pleasure_gain
			log_str += " 临时快感提升."
			
			var current_pleasure = temp_pleasure_pool[reward_stat]
			var ORGASM_THRESHOLD = 100
			
			if not is_edging:
				# 普通模式：快感满 100 立刻触发 1倍自然高潮并清零
				if current_pleasure >= ORGASM_THRESHOLD:
					target.add_exp(reward_stat, 500)
					target.add_exp("devotion", 125)
					target.reduce_exp("shame", 50)
					temp_pleasure_pool[reward_stat] = 0 # 清空
					log_str += "\n  [color=pink]★ 达到高潮阈值，自然释放！[/color] [" + reward_stat + " +500 Exp] [devotion +125 Exp] [shame -50 Exp]"
			else:
				# 寸止模式：快感无上限累积，但检查是否走火
				var max_capacity = 100 + (target.stats["edging_control"]["level"] * 10)
				if current_pleasure > max_capacity:
					# 超过忍耐极限，走火！拿到 1 倍保底，清空快感，增加反抗度
					target.add_exp(reward_stat, 500)
					target.add_exp("rebellion", 100)
					temp_pleasure_pool[reward_stat] = 0
					log_str += "\n  [color=red]⚠ 超过忍耐极限，意外走火绝顶！[/color] 惩罚性结算：[" + reward_stat + " +500 Exp] [rebellion +100 Exp]"

		# 获得底层的真实Exp (顺从和欲望)
		var ob_exp = 10 if not is_critical else 30
		var lust_exp = 5 if not is_critical else 15
		target.add_exp("yuri_obedience", ob_exp)
		target.add_exp("lust", lust_exp)
		log_str += " [yuri_obedience +" + str(ob_exp) + " Exp] [lust +" + str(lust_exp) + " Exp]"
		
	else:
		log_str += "失败"
		target.add_exp("rebellion", 20)
		log_str += " 角色产生抗拒. [rebellion +20 Exp]"
		
	return log_str

# ---------------------------------------------------------
# 终极结算：多重高潮判定 (Finisher)
# ---------------------------------------------------------
func _process_orgasm_finisher(target: CharacterData) -> String:
	var orgasm_count = 0
	var triggered_parts = []
	var total_multiplier = 0
	var ORGASM_THRESHOLD = 100
	
	# 检查有哪些部位的临时快感超过了高潮阈值，并计算深度倍率
	for part in temp_pleasure_pool.keys():
		var p_val = temp_pleasure_pool[part]
		if p_val >= ORGASM_THRESHOLD:
			orgasm_count += 1
			triggered_parts.append(part)
			# 深度倍率：快感溢出越多，该部位倍率越高（如 350 快感 = 3 倍深度）
			total_multiplier += int(p_val / ORGASM_THRESHOLD)
			
	if orgasm_count == 0:
		return "[允许高潮] 失败：快感不足，角色感到空虚。"
		
	var log_str = "[color=pink][允许高潮] 引爆！达成 " + str(orgasm_count) + " 重高潮！部位: " + str(triggered_parts) + "[/color]"
	
	# ===== 核爆级多重高潮收益结算 =====
	var base_exp = 500
	# 广度倍率：多重高潮的指数级放大（1重=1，2重=4，3重=9，4重=16...）
	var breadth_multiplier = pow(orgasm_count, 2.0)
	
	# 总暴击经验 = 基础(500) * 深度倍率和 * 广度倍率
	var final_exp_reward = int(base_exp * total_multiplier * breadth_multiplier)
	
	# 1. 对应爆发部位获得海量 Exp
	for part in triggered_parts:
		target.add_exp(part, final_exp_reward)
		log_str += "\n  [" + part + " +" + str(final_exp_reward) + " Exp]"
		
	# 2. 强行削减羞耻心，击碎心防 (这是最难涨的负向属性，只有多重高潮能有效击破)
	var shame_damage = int(100 * total_multiplier * breadth_multiplier)
	target.reduce_exp("shame", shame_damage)
	log_str += " [shame -" + str(shame_damage) + " Exp]"
	
	# 3. 获得接受度 (Devotion)
	target.add_exp("devotion", final_exp_reward / 2)
	log_str += " | 精神防线彻底崩溃！ [devotion +" + str(final_exp_reward / 2) + " Exp]"
		
	# 清空结算后的临时快感
	for key in temp_pleasure_pool.keys():
		temp_pleasure_pool[key] = 0
		
	return log_str
