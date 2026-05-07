class_name SimulationEngine
extends Node

# ==============================================================================
# project_ERA 核心推演引擎 (Simulation Engine)
# 职责：在单一帧内，处理回合内的多重连续指令序列，执行 COC 暗骰检定，
# 管理临时快感槽，以及结算多重高潮。绝对不依赖 LLM 请求。
# ==============================================================================

# --- 模拟运行中的“本回合临时快感槽” ---
# 在单次回合 (如: 上午的 10 连指令) 结束后会被清空或结算
var temp_pleasure_pool: Dictionary = {
	"sensory_M": 0, "sensory_B": 0, "sensory_A": 0, 
	"sensory_C": 0, "sensory_V": 0, "sensory_P": 0
}

# ---------------------------------------------------------
# 主入口：执行一个指令序列 (Task Sequence)
# 例如传入 7 次开发指令，最后 1 次允许高潮
# ---------------------------------------------------------
func process_task_sequence(target: CharacterData, instructor: CharacterData, actions: Array[Dictionary]) -> Array[String]:
	var turn_logs: Array[String] = []
	var inst_name = instructor.char_name if instructor != null else "无人/系统"
	turn_logs.append("\n[color=yellow]=== [ " + inst_name + " ] 开始对 [ " + target.char_name + " ] 进行回合连招调教 ===[/color]")
	
	# 重置临时快感槽
	for key in temp_pleasure_pool.keys():
		temp_pleasure_pool[key] = 0
		
	var has_finisher = false
	# 遍历执行每个动作
	for action in actions:
		var result_log = _execute_single_action(target, instructor, action)
		turn_logs.append(result_log)
		if action.get("type", "NORMAL") == "FINISHER":
			has_finisher = true
			
	# 如果本回合没有主动下达【允许高潮】的指令，但快感已经满了
	# 按照设计意图，进行默认的 1重高潮自然结算
	if not has_finisher:
		var auto_log = _process_auto_orgasm(target)
		if auto_log != "":
			turn_logs.append(auto_log)
			
	turn_logs.append("[color=yellow]=== [ " + inst_name + " ] 对 [ " + target.char_name + " ] 的调教回合结束 ===[/color]\n")
	return turn_logs

# ---------------------------------------------------------
# 自然高潮结算 (Auto Orgasm - 没有 Finisher 时触发)
# ---------------------------------------------------------
func _process_auto_orgasm(target: CharacterData) -> String:
	var triggered_parts = []
	var ORGASM_THRESHOLD = 80
	for part in temp_pleasure_pool.keys():
		if temp_pleasure_pool[part] >= ORGASM_THRESHOLD:
			triggered_parts.append(part)
			
	if triggered_parts.size() == 0:
		return ""
		
	var log_str = "[自然高潮] 达到极限，自动释放！部位: " + str(triggered_parts)
	var base_exp = 500
	
	# 默认1倍基础经验
	for part in triggered_parts:
		target.add_exp(part, base_exp)
		target.add_exp("devotion", base_exp / 4)
		log_str += " [" + part + " +" + str(base_exp) + " Exp]"
		
	# 自然高潮不带有强力击碎心防的效果，仅轻微减羞耻
	target.reduce_exp("shame", 50)
	log_str += " [devotion +" + str(base_exp / 4) + " Exp] [shame -50 Exp]"
	
	for key in temp_pleasure_pool.keys():
		temp_pleasure_pool[key] = 0
		
	return log_str

# ---------------------------------------------------------
# 单一指令执行与 COC 检定核心逻辑 (动态解析版本)
# ---------------------------------------------------------
func _execute_single_action(target: CharacterData, instructor: CharacterData, action: Dictionary) -> String:
	var cmd_name = action.get("action_flavor", "未知动作")
	var cmd_type = action.get("type", "NORMAL")
	
	# 1. 终结指令：引爆多重高潮
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
		# 限制逆向扣除在合理范围内
		reduce_amount = clamp(abs(int(reduce_amount)), 10, 500)
		target.reduce_exp(check_stat, reduce_amount)
		return "[" + cmd_name + "] 成功执行逆向调教。目标属性 " + check_stat + " 经验扣减。 [" + check_stat + " -" + str(reduce_amount) + " Exp]"

	# ================= COC 对抗暗骰计算 =================
	var ob_lvl = target.stats["yuri_obedience"]["level"]
	var lust_lvl = target.stats["lust"]["level"]
	
	# 根据 LLM 决定的 defend_stat 动态提取防御属性减值
	var defend_lvl = 0
	if defend_stat != "none":
		defend_lvl = target.stats[defend_stat]["level"]
	
	# 基底成功率 = 百合顺从 + 欲望 - 防御属性
	var base_success = ob_lvl + lust_lvl - defend_lvl
					 
	var instructor_bonus = 20 if instructor != null else 0 
	
	# LLM 自定义的难度修正 (强制封顶 -50 到 50 之间防乱填)
	var cmd_modifier = clamp(int(action.get("difficulty_modifier", 0)), -50, 50)
	
	# 目标部位/属性的感觉 Level 作为加成
	var part_bonus = target.stats[check_stat]["level"]
		
	# 最终判定值
	var final_chance_raw = 50 + base_success + instructor_bonus + cmd_modifier + part_bonus
	var final_chance = clamp(final_chance_raw, 5, 95) 
	
	var roll = randi() % 100 + 1 
	var is_success = roll <= final_chance
	var is_critical = roll <= final_chance / 5 
	
	var log_str = "\n[color=lightblue][" + cmd_name + "][/color] 正在进行 COC 判定...\n"
	log_str += "  > 计算过程: 基础(50) + 顺从(" + str(ob_lvl) + ") + 欲望(" + str(lust_lvl) + ") - 阻力[" + defend_stat + "](" + str(defend_lvl) + ")"
	log_str += " + 导师技巧(" + str(instructor_bonus) + ") + 动作修正(" + str(cmd_modifier) + ") + 部位加成(" + str(part_bonus) + ")\n"
	log_str += "  > = 理论成功率 (" + str(final_chance_raw) + "%) -> 实际补正后 (" + str(final_chance) + "%)\n"
	log_str += "  > 判定: " + str(final_chance) + "% | 掷骰: " + str(roll) + " -> "
	
	# ================= 结算结果 =================
	if is_success:
		log_str += "成功"
		if is_critical: log_str += "(大成功!)"
		
		# 成功后立刻获得目标部位的基础经验，即使最后没高潮也不亏
		var base_part_exp = 100 if not is_critical else 300
		target.add_exp(reward_stat, base_part_exp)
		log_str += " [" + reward_stat + " +" + str(base_part_exp) + " Exp]"
		
		# 成功积累临时快感 (存入寸止池)
		var pleasure_gain = 30 if not is_critical else 60
		_add_temp_pleasure(target, reward_stat, pleasure_gain)
		log_str += " 临时快感提升."
			
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
# 寸止池管理：添加临时快感
# ---------------------------------------------------------
func _add_temp_pleasure(target: CharacterData, part: String, amount: int) -> void:
	if not temp_pleasure_pool.has(part): return
	
	var current_p = temp_pleasure_pool[part]
	var new_p = current_p + amount
	
	# 读取角色的寸止极限 (Edging Control Level 决定了快感上限，等级越高能憋的数值越大，默认为 100)
	# 假设每 1 级寸止技巧，快感池容量提升 10点。0级为100，10级能憋到200
	var max_capacity = 100 + (target.stats["edging_control"]["level"] * 10)
	
	# 如果快感没有超过容量，说明角色“憋住了”，处于寸止状态
	if new_p <= max_capacity:
		temp_pleasure_pool[part] = new_p
	else:
		# TODO: 走火机制 (Unintended Orgasm)
		# 如果快感超过了她的忍耐极限，这里本该触发被动的“绝顶走火”，强制结算该单一部位，并清空该部位的快感。
		# 且因为是被迫走火，拿不到多重高潮的暴击奖励。为了测试简便，这里直接锁死在 max_capacity 模拟成功憋住。
		temp_pleasure_pool[part] = max_capacity 

# ---------------------------------------------------------
# 终极结算：多重高潮判定 (Finisher)
# ---------------------------------------------------------
func _process_orgasm_finisher(target: CharacterData) -> String:
	var orgasm_count = 0
	var triggered_parts = []
	
	# 检查有哪些部位的临时快感超过了高潮阈值 (假设阈值固定为 80)
	var ORGASM_THRESHOLD = 80
	
	for part in temp_pleasure_pool.keys():
		if temp_pleasure_pool[part] >= ORGASM_THRESHOLD:
			orgasm_count += 1
			triggered_parts.append(part)
			
	if orgasm_count == 0:
		return "[允许高潮] 失败：快感不足，角色感到空虚。"
		
	var log_str = "[允许高潮] 引爆！达成 " + str(orgasm_count) + " 重高潮！部位: " + str(triggered_parts)
	
	# ===== 核爆级多重高潮收益结算 =====
	# 基础经验基数
	var base_exp = 500
	# [修正] 多重乘数：遵循ERA设定。2重高潮每个部位得2倍，3重得3倍...
	# 总倍率 = orgasm_count * orgasm_count
	var multiplier = orgasm_count
	var final_exp_reward = int(base_exp * multiplier)
	
	# 1. 对应爆发部位获得海量 Exp
	for part in triggered_parts:
		target.add_exp(part, final_exp_reward)
		log_str += " [" + part + " +" + str(final_exp_reward) + " Exp]"
		
	# 2. 强行削减羞耻心，击碎心防 (这是最难涨的负向属性，只有多重高潮能有效击破)
	var shame_damage = int(pow(orgasm_count, 2.0)) * 100 # 几百点甚至上千经验的强制扣减
	target.reduce_exp("shame", shame_damage)
	log_str += " [shame -" + str(shame_damage) + " Exp]"
	
	# 3. 获得接受度 (Devotion) - 只有二重以上才给接受度
	if orgasm_count >= 2:
		target.add_exp("devotion", final_exp_reward / 2)
		log_str += " | 精神防线崩溃，接受度大幅提升！ [devotion +" + str(final_exp_reward / 2) + " Exp]"
		
	# 清空结算后的临时快感
	for key in temp_pleasure_pool.keys():
		temp_pleasure_pool[key] = 0
		
	return log_str

# ---------------------------------------------------------
# 逆向指令结算 (禁欲/教养)
# ---------------------------------------------------------
func _process_reverse_training(target: CharacterData, action: Dictionary) -> String:
	var cmd_name = action.get("name", "Reverse Action")
	var target_stat = action.get("target_stat", "") # 例如 "lust"
	var reduce_amount = action.get("amount", 200)   # 扣除的经验量
	
	if target_stat != "":
		target.reduce_exp(target_stat, reduce_amount)
		return "[" + cmd_name + "] 成功执行逆向调教。目标属性 " + target_stat + " 经验大幅扣减。 [" + target_stat + " -" + str(reduce_amount) + " Exp]"
	return "[" + cmd_name + "] 无效的逆向指令。"
