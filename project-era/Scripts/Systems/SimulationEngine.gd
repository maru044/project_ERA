class_name SimulationEngine
extends Node

# ==============================================================================
# project_ERA 核心推演引擎 (Simulation Engine)
# 职责：在单一帧内，处理回合内的多重连续指令序列，执行 COC 暗骰检定，
# 管理临时快感槽，以及结算多重高潮。绝对不依赖 LLM 请求。
# ==============================================================================

# --- 指令类型常量 (用于判定难度) ---
enum CommandType {
	ICE_BREAK,    # 破冰指令 (如: 爱抚、舔阴。带有高顺从加值，无视大部分羞耻心)
	NORMAL,       # 进阶指令 (如: 后庭开发、抽插。需要顺从与欲望对抗羞耻心)
	ABYSS,        # 深渊指令 (如: 极端露出、寸止地狱。带有极大惩罚，必须多重高潮或破防才可成功)
	FINISHER,     # 终结指令 (如: 允许高潮。用于引爆当前回合累积的临时快感)
	REVERSE       # 逆向指令 (如: 禁欲、教养。用于降低欲望或提升羞耻心)
}

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
	turn_logs.append("--- 开始对 " + target.char_name + " 进行回合连招调教 ---")
	
	# 重置临时快感槽
	for key in temp_pleasure_pool.keys():
		temp_pleasure_pool[key] = 0
		
	var has_finisher = false
	# 遍历执行每个动作
	for action in actions:
		var result_log = _execute_single_action(target, instructor, action)
		turn_logs.append(result_log)
		if action.get("type", CommandType.NORMAL) == CommandType.FINISHER:
			has_finisher = true
			
	# 如果本回合没有主动下达【允许高潮】的指令，但快感已经满了
	# 按照设计意图，进行默认的 1重高潮自然结算
	if not has_finisher:
		var auto_log = _process_auto_orgasm(target)
		if auto_log != "":
			turn_logs.append(auto_log)
			
	turn_logs.append("--- 回合调教结束 ---")
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
# 单一指令执行与 COC 检定核心逻辑
# ---------------------------------------------------------
func _execute_single_action(target: CharacterData, instructor: CharacterData, action: Dictionary) -> String:
	var cmd_name = action.get("name", "Unknown Action")
	var cmd_type = action.get("type", CommandType.NORMAL)
	var target_part = action.get("target_part", "") # 比如 "sensory_C"
	
	# 1. 终结指令：引爆多重高潮
	if cmd_type == CommandType.FINISHER:
		return _process_orgasm_finisher(target)
		
	# 2. 逆向指令：教养与禁欲
	if cmd_type == CommandType.REVERSE:
		return _process_reverse_training(target, action)

	# ================= COC 对抗暗骰计算 =================
	# 基底成功率 = 百合顺从 + 欲望 - 羞耻心 (按面板Level计算，1 Level算 1 点权重)
	var base_success = target.stats["yuri_obedience"]["level"] \
					 + target.stats["lust"]["level"] \
					 - target.stats["shame"]["level"]
					 
	# 导师加成 (导师越强，越容易压制)
	# 假设导师的指导技术被预先转换为了一个数值 (此处简化取 20 作为顶级导师加成)
	var instructor_bonus = 20 if instructor != null else 0 
	
	# 指令特殊修正
	var cmd_modifier = 0
	match cmd_type:
		CommandType.ICE_BREAK:
			cmd_modifier = 50 # 破冰极易成功
		CommandType.NORMAL:
			cmd_modifier = 0
		CommandType.ABYSS:
			cmd_modifier = -50 # 深渊极难成功
			
	# 如果是针对特定部位的，加上目标部位的感觉 Level 作为加成
	var part_bonus = 0
	if target_part != "" and target.stats.has(target_part):
		part_bonus = target.stats[target_part]["level"]
		
	# 最终判定值 (基础 50%，加上所有修正)
	var final_chance = 50 + base_success + instructor_bonus + cmd_modifier + part_bonus
	final_chance = clamp(final_chance, 5, 95) # 保留大成功和大失败的可能
	
	# 掷骰子 d100
	var roll = randi() % 100 + 1 
	var is_success = roll <= final_chance
	var is_critical = roll <= final_chance / 5 # 暴击率是成功率的 1/5
	
	var log_str = "[" + cmd_name + "] 判定: " + str(final_chance) + "% | 掷骰: " + str(roll) + " -> "
	
	# ================= 结算结果 =================
	if is_success:
		log_str += "成功"
		if is_critical: log_str += "(大成功!)"
		
		# [修正] 成功后立刻获得目标部位的基础经验，即使最后没高潮也不亏
		if target_part != "":
			var base_part_exp = 100 if not is_critical else 300
			target.add_exp(target_part, base_part_exp)
			log_str += " [" + target_part + " +" + str(base_part_exp) + " Exp]"
			
			# 成功积累临时快感 (存入寸止池)
			var pleasure_gain = 30 if not is_critical else 60
			_add_temp_pleasure(target, target_part, pleasure_gain)
			log_str += " 临时快感提升."
			
		# 获得底层的真实Exp (顺从和欲望)
		var ob_exp = 10 if not is_critical else 30
		var lust_exp = 5 if not is_critical else 15
		target.add_exp("yuri_obedience", ob_exp)
		target.add_exp("lust", lust_exp)
		log_str += " [yuri_obedience +" + str(ob_exp) + " Exp] [lust +" + str(lust_exp) + " Exp]"
		
	else:
		log_str += "失败"
		# 失败惩罚：增加反抗度
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
