# project_ERA 阶段性开发计划与脚本目录清单

本清单梳理了基于 Godot 4 引擎纯原生方案开发《次世代LLM百合调教沙盒系统 (project_ERA)》的阶段性目标与文件脚本目录。

## 优先级定义
- **P0（核心骨架）**: 项目最基础的底层运行环境、数据结构、核心循环流转以及纯 Godot 端数值推演闭环。重点实现主从属性的阶级关系和对数升级机制。
- **P1（AI大脑与通信）**: 接入大语言模型 (LLM)，完成 Function Calling 与 Godot 的双向 JSON 通信、工具路由分发。重点控制API请求次数。
- **P2（UI与沙盒体验）**: 将枯燥的测试日志转化为可视化的玩家面板、交互窗口及突发事件的视觉包装。

---

## 阶段目标与文件结构清单

### P0阶段：核心骨架与本地沙盒模拟
目标：不依赖网络请求，建立起角色、任务、回合流转以及本地数值变化的单机小循环。可以简单地在控制台（Console）看到“安排任务 -> 一帧结算经验与属性”的结果。

* `res://Scripts/Core/MainLoop.gd`
  - **功能**: 全局主循环控制器，负责时间轴的切分（清晨规划、上午结算、中午干预、下午结算、夜晚夜伽），管理状态机流转。
* `res://Scripts/Data/CharacterData.gd`
  - **功能**: 角色数据结构定义。
    - **硬指标**: 包含核心基石（百合顺从）、阻力（羞耻心、傲娇度）、对抗力（欲望、各部位感觉）、以及验收（接受度）。
    - **经验系统**: 维护每个硬指标的当前经验值（Current_Exp）和基于对数扩容的升级槽（Exp_Cap），支持正向升级与负向降级（如禁欲/教养导致经验跌破阈值）。
    - **独占记忆**: `exclusive_memories` 数组，用于存储仅有该角色参与时才发给LLM的私密事件，从物理层面防止AI信息泄露串话。
    - **软标签**: 包含文本形式的 Custom Tags 数组（例如：将“口交天才”、“骑乘位精通”等具体动作技巧和癖好存为文本，供LLM读取并提供额外数值修正）。
  - **序列化**: 内置 `to_json()` 和 `load_from_json()` 方法。
* `res://Scripts/Managers/CharacterManager.gd`
  - **功能**: 角色名单总管。处理新角色的实例化、增删改查以及状态修改（查找空闲/忙碌角色）。
  - **扩展机制**: 实现外部图包与角色包的运行时读取 (Runtime Loading)。通过扫描预设的外部 Mod 文件夹，利用 `DirAccess` 与 `ImageTexture` 动态加载外部角色立绘与手写的 `character_data.json` 并注册进游戏系统，提供类似《青楼之王》的高自由度扩展支持。
* `res://Scripts/Managers/TaskManager.gd`
  - **功能**: 日程与任务管理。接收早晨的安排并维护任务队列。
  - **指令修正定义**: 内部包含不同等级指令的判定修正（如：破冰指令自带高顺从加值、深渊指令自带重度惩罚）。
* `res://Scripts/Systems/SimulationEngine.gd`
  - **功能**: 本地算数“脏活”执行器与检定中心。在上午和下午的一帧内，根据 TaskManager 指令和角色属性抛暗骰（d100对抗判定）。
  - **核心逻辑**: 执行多重高潮检定与寸止状态管理；判定成功则给予高额 Exp 奖励（包括教养/禁欲指令导致的负向降级扣减），失败则增加负面情绪，最终产出干涩的数据变更日志。

---

### P1阶段：原生LLM通信与表现层解耦
目标：通过 Godot 原生的 `HTTPRequest` 节点打通 LLM API。极度严格控制 API 成本（**任何一个交互窗口无论涉及多少角色，仅消耗1次 API 请求**）。**彻底放弃易被审查拦截的原生 Tool API，全面转向“预填充破限 (Prefill Jailbreak) + 文本级正则提取”架构。**

* `res://Scripts/Network/LLM_Client.gd`
  - **功能**: 核心通信模块。封装 `HTTPRequest` 发起 POST 请求，管理 API Key。
  - **动态组装机 (Dynamic Context Builder)**: 针对不同游戏模式拼装极其复杂的提示词。
    - **A模式 (后台分配/结算)**: 注入上帝视角系统提示词，要求输出纯 JSON 供正则提取。
    - **B模式 (深夜夜伽/晚报)**: 注入《性奴沙盒世界观》，拼接角色面板，要求输出含动作判定的扮演文本。
    - **C模式 (元叙事助手)**: 注入 Miku 管理员人设，进行第四面墙交流。
  - **强制破限机制**: 在每次发往 LLM 的 `role: 'model'` 结构中，强行预填充 `</think>\n<thinking>...` 等思考引导词，彻底绕过 Gemini/Claude 等大模型的道德审查。
* `res://Scripts/Network/ToolRegistry.gd`
  - **功能**: 工具注册与提取枢纽（已从原生 Function Calling 进化为正则匹配器）。
  - **工作流**: 拦截 LLM 返回的 `<content>` 文本。如果文本内包含预定义的宏标签（如 ````json [任务数组] ```` 或 `[STAT_CHANGE: lust +10]`），引擎利用正则表达式强行抠出数据并转交给对应 Manager 运行。
* `res://Scripts/Systems/EventGenerator.gd`
  - **功能**: 批量打包器（Batch Processor）。在中午干预节点和夜晚结算节点，收集 `SimulationEngine` 产出的原始变更和角色的 Custom Tags，组装成超级 Prompt 一次性发给 LLM，要求在单一 JSON 内返回事件判定、属性修正和表现层文本。

---

### P2阶段：可视化UI与深度交互界面
目标：脱离控制台打印，构建上帝视角的操作台。让玩家能在UI上分配任务、查看名单、浏览 LLM 包装好的精致晚报，并在夜伽阶段深度交流。

* `res://Scripts/UI/UIManager.gd`
  - **功能**: 全局界面切换管理器，负责协调左侧角色栏、中央分配台、晚报面板的隐藏与显示。
* `res://Scripts/UI/RosterPanel.gd`
  - **功能**: “性奴宿舍”界面控制器。展示各个角色的硬指标面板（等级及经验条）与文本形式的软标签（Custom Tags）。
* `res://Scripts/UI/DispatchBoard.gd`
  - **功能**: 早晨任务分配台。处理玩家在此界面的拖拽或点击操作，将指令传给 `TaskManager`。
* `res://Scripts/UI/EventLogConsole.gd`
  - **功能**: 将 LLM 返回的表现层 JSON 以对话或信件的样式渲染在屏幕上，配合 `RichTextLabel` 的 BBCode 和打字机特效展示晚报与突发事件。
* `res://Scripts/UI/NightChatBox.gd`
  - **功能**: 纯文本的夜伽沙盒深度交互控制台。处理玩家在深夜自由输入的指令，这是唯一的高频率 LLM 交互测试场。