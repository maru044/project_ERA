class_name SimulationEngine
extends Node

# ==============================================================================
# project_ERA 核心推演引擎 (Simulation Engine)
# 职责：在单一帧内，处理回合内的多重连续指令序列，执行 COC 暗骰检定，
# 管理临时快感槽，以及结算多重高潮。绝对不依赖 LLM 请求。
# ==============================================================================

# --- 模拟运行中的“本回合高潮层数”与“受击部位” ---
var current_orgasm_layers: int = 1
var targeted_parts: Array[String] = []

# ---------------------------------------------------------
# 主入口：执行一个指令序列 (Task Sequence)
# ---------------------------------------------------------
func process_task_sequence(target: CharacterData, instructor: CharacterData, is_edging: bool, actions: Array[Dictionary]) -> Array[String]:
	var turn_logs: Array[String] = []
	var inst_name = instructor.char_name if instructor != null else "无人/系统"
	var mode_text = "【寸止模式】" if is_edging else "【普通模式】"
	turn_logs.append("\n[color=yellow]=== [ " + inst_name + " ] 开始对 [ " + target.char_name + " ] 进行回合连招调教 " + mode_text + " ===[/color]")
	
	# 记录本回合开始前的所有属性状态，用于最终比对
	var old_stats = {}
	for key in target.stats.keys():
		old_stats[key] = {
			"level": target.stats[key]["level"],
			"exp": target.stats[key]["exp"]
		}
	
	# 重置高潮倍率层数与受击部位
	current_orgasm_layers = 1
	targeted_parts.clear()
	
	# 遍历执行每个动作
	for action in actions:
		var result_log = _execute_single_action(target, instructor, action, is_edging)
		turn_logs.append(result_log)
		
	# === 结算本回合的属性总变化 ===
	var summary = "\n[color=cyan]=== 本回合属性成长总结 ===[/color]\n"
	var has_changes = false
	for key in target.stats.keys():
		var old_lvl = old_stats[key]["level"]
		var new_lvl = target.stats[key]["level"]
		var old_e = old_stats[key]["exp"]
		var new_e = target.stats[key]["exp"]
		
		if old_lvl != new_lvl or old_e != new_e:
			has_changes = true
			var cap = target.get_exp_cap_for_level(new_lvl)
			var level_text = ""
			if new_lvl > old_lvl:
				level_text = " [color=yellow]★ 升级! (Lv." + str(old_lvl) + " -> Lv." + str(new_lvl) + ")[/color]"
			elif new_lvl < old_lvl:
				level_text = " [color=red]▼ 降级! (Lv." + str(old_lvl) + " -> Lv." + str(new_lvl) + ")[/color]"
			else:
				level_text = " (Lv." + str(new_lvl) + ")"
				
			summary += "> " + key + ":" + level_text + " | 当前进度: " + str(new_e) + " / " + str(cap) + " Exp\n"
			
	if has_changes:
		turn_logs.append(summary)
			
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
		
		# 记录本次受击部位，供最终高潮结算使用
		if not targeted_parts.has(reward_stat):
			targeted_parts.append(reward_stat)
		
		# === 核心逻辑：寸止判定与多重高潮倍率叠加 ===
		if is_edging:
			var base_edging_exp = 1000 # 无条件获得基础的寸止经验
			
			var edge_lvl = target.stats["edging_control"]["level"]
			var edge_roll = randi() % 100 + 1
			# 寸止检定：基于角色的寸止忍耐技巧进行判定
			var edge_chance = clamp(edge_lvl + 20, 10, 90) # 给定一个基础胜率
			log_str += "\n  > [寸止检定] 忍耐度(" + str(edge_lvl) + ") | 掷骰: " + str(edge_roll) + " / " + str(edge_chance) + "% -> "
			if edge_roll <= edge_chance:
				current_orgasm_layers += 1
				target.add_exp("edging_control", base_edging_exp + 2000)
				log_str += "[color=pink]成功！高潮倍率累积至 " + str(current_orgasm_layers) + " 重！[/color] [edging_control +" + str(base_edging_exp + 2000) + " Exp]"
			else:
				target.add_exp("edging_control", base_edging_exp)
				log_str += "[color=gray]失败，未能叠加倍率。[/color] [edging_control +" + str(base_edging_exp) + " Exp]"

		# 获得底层的真实Exp (顺从和欲望) 统一按大额基数计算
		var ob_exp = 100 if not is_critical else 300
		var lust_exp = 100 if not is_critical else 300
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
	if targeted_parts.size() == 0:
		return "[允许高潮] 失败：没有任何受击部位，角色感到空虚。"
		
	var log_str = "[color=pink][允许高潮] 引爆！达成 " + str(current_orgasm_layers) + " 重高潮！波及部位: " + str(targeted_parts) + "[/color]"
	
	# ===== 核爆级多重高潮收益结算 =====
	var base_exp = 500
	# 广度倍率：多重高潮的指数级放大（1重=1，2重=4，3重=9，4重=16...）
	var breadth_multiplier = pow(current_orgasm_layers, 2.0)
	
	# 总暴击经验 = 基础(500) * 广度倍率
	var final_exp_reward = int(base_exp * breadth_multiplier)
	
	# 1. 对本回合所有受击部位获得海量 Exp
	for part in targeted_parts:
		target.add_exp(part, final_exp_reward)
		log_str += "\n  [" + part + " +" + str(final_exp_reward) + " Exp]"
		
	# 1.5 欲望与顺从同样吃满多重高潮的暴击红利
	target.add_exp("lust", final_exp_reward)
	target.add_exp("yuri_obedience", final_exp_reward)
	log_str += "\n  [lust +" + str(final_exp_reward) + " Exp] [yuri_obedience +" + str(final_exp_reward) + " Exp]"
		
	# 2. 强行削减羞耻心，击碎心防 (这是最难涨的负向属性，只有多重高潮能有效击破)
	var shame_damage = int(100 * breadth_multiplier)
	target.reduce_exp("shame", shame_damage)
	log_str += " [shame -" + str(shame_damage) + " Exp]"
	
	# 3. 获得接受度 (Devotion)
	target.add_exp("devotion", final_exp_reward / 2)
	log_str += " | 精神防线彻底崩溃！ [devotion +" + str(final_exp_reward / 2) + " Exp]"
		
	# 结算后清空层数
	current_orgasm_layers = 1
	targeted_parts.clear()
		
	return log_str
