class_name CharacterData
extends Resource

# --- 核心硬指标字典 (Base Stats) ---
# 每个属性包含: level (当前等级, 0-100) 和 exp (当前经验)
var stats: Dictionary = {}

# --- 独占记忆与标签 ---
var exclusive_memories: Array[String] = [] # 物理防泄露的私密记忆
var custom_tags: Array[String] = []        # 风味文本，如"口交天才", "怕黑"

# 基本信息
var id: String = ""
var char_name: String = ""
var description: String = ""

# --- 属性名常量字典定义 ---
# 确保在各处使用统一的键名 (根据企划书附录定义)
const STAT_KEYS = [
	# 1. 心理阻力与基石
	"devotion",        # 接受度/屈服
	"shame",           # 羞耻心
	"rebellion",       # 反抗度/傲娇
	"yuri_obedience",  # 百合顺从
	
	# 2. 生理突破与感觉
	"lust",            # 欲望
	"sensory_M",       # 嘴/唇/舌
	"sensory_B",       # 胸部
	"sensory_A",       # 后庭
	"sensory_C",       # 阴蒂
	"sensory_V",       # 小穴
	"sensory_P",       # 扶她肉棒
	
	# 3. 特殊体质
	"exhibitionism",   # 露出癖
	"semen_addiction", # 精液/体液中毒
	
	# 4. 技巧与执行力 (被调教者特有的高潮管理，其他技巧归入自定义标签)
	"edging_control"   # 寸止技巧/高潮忍耐
]

func _init() -> void:
	# 初始化所有属性，默认等级 0，经验 0
	for key in STAT_KEYS:
		stats[key] = {
			"level": 0,
			"exp": 0
		}

# ---------------------------------------------------------
# 核心机制 1：基于平滑曲线的等级所需经验池计算 (Exp Cap)
# 公式：所需经验 = 2 * (Level^2) + 50 * Level + 100
# 目的：前期极易升级（破冰），后期防锁死，鼓励使用多重高潮结算
# ---------------------------------------------------------
func get_exp_cap_for_level(level: int) -> int:
	if level >= 100:
		return 999999999 # 满级锁定
	return int(2.0 * pow(level, 2.0) + 50.0 * level) + 100

# ---------------------------------------------------------
# 核心机制 2：添加经验并自动处理正向升级 (Positive Training)
# 支持一次性获得巨量多重高潮经验，自动连升多级
# ---------------------------------------------------------
func add_exp(stat_key: String, amount: int) -> void:
	if not stats.has(stat_key):
		push_error("Error: Stat key not found: " + stat_key)
		return
		
	if amount <= 0:
		return # 使用专门的减经验函数
		
	var stat = stats[stat_key]
	stat.exp += amount
	
	# 循环判断升级（可能一次性获得海量经验升多级）
	while stat.level < 100:
		var current_cap = get_exp_cap_for_level(stat.level)
		if stat.exp >= current_cap:
			stat.exp -= current_cap # 溢出的经验带入下一级
			stat.level += 1
		else:
			break
			
	# 如果达到满级，清空溢出经验
	if stat.level >= 100:
		stat.exp = 0

# ---------------------------------------------------------
# 核心机制 3：扣减经验并自动处理负向降级 (Reverse Training)
# 用于【禁欲】(降欲望) 或 【教养】(降反抗，虽然教养有时是加羞耻，此处通用)
# ---------------------------------------------------------
func reduce_exp(stat_key: String, amount: int) -> void:
	if not stats.has(stat_key):
		push_error("Error: Stat key not found: " + stat_key)
		return
		
	if amount <= 0:
		return
		
	var stat = stats[stat_key]
	stat.exp -= amount
	
	# 循环判断降级
	while stat.exp < 0:
		if stat.level > 0:
			stat.level -= 1
			var prev_cap = get_exp_cap_for_level(stat.level)
			# 经验槽回退到上一级的阈值，并减去欠下的经验
			stat.exp += prev_cap
		else:
			# 降到 0 级且经验扣光，归零锁定
			stat.level = 0
			stat.exp = 0
			break

# ---------------------------------------------------------
# 辅助方法：序列化与反序列化，供 LLM 通信及存档使用
# ---------------------------------------------------------
func set_stat_level(stat_key: String, new_level: int) -> void:
	if stats.has(stat_key):
		stats[stat_key]["level"] = clamp(new_level, 0, 100)
		stats[stat_key]["exp"] = 0 # 重置经验为0

func to_dict() -> Dictionary:
	return {
		"id": id,
		"char_name": char_name,
		"description": description,
		"stats": stats,
		"exclusive_memories": exclusive_memories,
		"custom_tags": custom_tags
	}

func load_from_dict(data: Dictionary) -> void:
	if data.has("id"): id = data["id"]
	if data.has("char_name"): char_name = data["char_name"]
	if data.has("description"): description = data["description"]
	
	if data.has("exclusive_memories"):
		exclusive_memories.clear()
		var mems = data["exclusive_memories"]
		if typeof(mems) == TYPE_ARRAY:
			for m in mems: exclusive_memories.append(String(m))
			
	if data.has("custom_tags"):
		custom_tags.clear()
		var tags = data["custom_tags"]
		if typeof(tags) == TYPE_ARRAY:
			for t in tags: custom_tags.append(String(t))
	
	if data.has("stats"):
		for key in data["stats"].keys():
			if stats.has(key):
				stats[key]["level"] = data["stats"][key].get("level", 0)
				stats[key]["exp"] = data["stats"][key].get("exp", 0)

# --- LLM 专用：生成干净的上下文状态 (排除其他角色的独占记忆) ---
func get_prompt_context(include_exclusive_memory: bool = false) -> Dictionary:
	var context = {
		"name": char_name,
		"stats_summary": {},
		"tags": custom_tags
	}
	# 只发送 level，LLM不需要关心具体的 exp 数值
	for key in stats.keys():
		context.stats_summary[key] = stats[key]["level"]
		
	# 物理隔离机制：如果该角色未参与当前交互，强制不携带独占记忆
	if include_exclusive_memory and exclusive_memories.size() > 0:
		context["secret_memories"] = exclusive_memories
		
	return context
