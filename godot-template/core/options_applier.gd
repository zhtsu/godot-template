extends RefCounted

## 把设置**应用到引擎**（纯函数式：不持状态、不订阅事件、不读存档、不认识事件 / 结果类型）。
##
## 约束：
##   - 只做"内存值 → 引擎状态"这一步；"什么时候应用"由 core/save_service.gd 决定
##   - **不加 class_name**：由 core/save_service.gd 经 Paths.SCRIPT_OPTIONS_APPLIER 用 preload 引用
##   - 设置项以后增加时改这里，调用方不需要动
##
## 项目特有的部分就是这里；core/ 的其它地方 SHOULD NOT 直接调 DisplayServer / TranslationServer。

## 应用设置：音量 + 语言 + 分辨率（含全屏）
static func apply(options: OptionsSave) -> void:
	if options == null:
		return

	# 音量（三条总线都在工程根的 default_bus_layout.tres 里定义）
	_apply_bus_volume(OptionsSave.BUS_MASTER, options.master_volume)
	_apply_bus_volume(OptionsSave.BUS_MUSIC, options.music_volume)
	_apply_bus_volume(OptionsSave.BUS_SFX, options.sfx_volume)

	# 语言
	if TranslationServer.get_locale() != options.language:
		TranslationServer.set_locale(options.language)

	# 按键重映射
	_apply_input_bindings(options.input_bindings)

	# 分辨率：OptionsData.FULLSCREEN（Vector2i.ZERO）代表全屏
	if options.resolution == OptionsData.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(options.resolution)


## 线性音量 0.0~1.0 → 总线分贝。0.0 直接给 -80dB（等价静音；linear_to_db(0) 是 -inf，不能直接喂）。
static func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		push_warning("[OptionsApplier] 音频总线 '%s' 不存在，跳过音量应用（检查 default_bus_layout.tres）" % bus_name)
		return

	var clamped: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(clamped) if clamped > 0.0 else -80.0)


## 动作的"出厂绑定"备份：第一次套用重映射之前抓一份，供 Cancel 回滚 / 恢复默认使用。
## static var：整个进程里只抓一次（每次启动重新抓，正好对应 project.godot 的当前内容）。
static var _default_bindings: Dictionary = {}


## 把重映射套到 InputMap 上。
## 语义是**幂等**的：先把所有"可重映射动作"恢复成出厂绑定，再套用存档里的覆盖 ——
## 所以"取消改动"或"恢复默认"只要把 input_bindings 改掉再应用一次就够了。
static func _apply_input_bindings(bindings: Dictionary) -> void:
	for entry in OptionsData.REMAPPABLE_ACTIONS:
		var action: StringName = StringName(entry["action"])
		_restore_default_binding(action)

	for action_name in bindings:
		var action: StringName = StringName(action_name)
		if not InputMap.has_action(action):
			push_warning("[OptionsApplier] 存档里有未知动作 '%s'，已忽略（检查 OptionsData.REMAPPABLE_ACTIONS）"
				% action_name)
			continue

		var keycode: int = int(bindings[action_name])
		if keycode <= 0:
			continue

		InputMap.action_erase_events(action)
		var event: InputEventKey = InputEventKey.new()
		# 用物理键码：同一个物理键在不同键盘布局下位置一致，玩家按的还是那个键
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)


static func _ensure_default_bindings(action: StringName) -> void:
	if _default_bindings.has(action):
		return
	_default_bindings[action] = InputMap.action_get_events(action).duplicate()


static func _restore_default_binding(action: StringName) -> void:
	_ensure_default_bindings(action)
	InputMap.action_erase_events(action)
	for event in _default_bindings[action]:
		InputMap.action_add_event(action, event)
