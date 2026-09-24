extends Control

## 设置界面：**改动即存**。
## 下拉框 / 音量滑块 / 按键重映射任何一处改动，都会立刻发 `Events.SAVE_REQUEST` 写进设置档
## （槽位 `OptionsSave.SLOT`）；SaveService 写完会立即把设置应用到引擎，
## 所以"界面显示 = 实际生效"。没有 Apply / Cancel 这层缓冲。
##
## 音量滑块是**分档**的（档位定义在 `OptionsData.VOLUME_STEPS`，例如 0/2/4/6/8/10）：
## 滑块自带 step 吸附，脚本里还按档位去重 —— 只有"档位真的变了"才写档，
## 同一档内的拖动不会反复落盘。
##
## 节点引用一律用「场景唯一名」`%Name` 或按名字 `find_child`（见 OptionsData 的两张表），
## 不写 `$Rows/RowResolution/ResolutionOption` 这种长路径；按钮/滑块信号用 [connection] 连。

@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _language_option: OptionButton = %LanguageOption

## 音量：字段名 → 滑块 / 显示档位的标签
var _volume_sliders: Dictionary = {}
var _volume_labels: Dictionary = {}
## 字段名 → 已经写进存档的档位（用来"只在档位变化时保存"）
var _saved_steps: Dictionary = {}
## 动作名 → 显示当前按键的按钮
var _key_buttons: Dictionary = {}
## 非空 = 正在等用户按下一个键（用于按键重映射）
var _waiting_action: String = ""


func _ready() -> void:
	_collect_volume_widgets()
	_collect_key_buttons()
	_fill_options()
	_update_key_buttons()
	# 只连一次：_fill_options() 在翻译变化时还会被调用，连在这里就不会重复连接
	_resolution_option.item_selected.connect(_on_option_selected)
	_language_option.item_selected.connect(_on_option_selected)


## 切语言后 Godot 会发这个通知：重填一遍下拉框（"全屏"那条是 tr() 出来的，需要刷新）。
## _fill_options 读的是内存里的当前值，所以不会丢掉用户刚改的设置。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _resolution_option != null:
		_fill_options()


## 返回：发 CLOSE_UI 事件交给 UiRoot 关闭自己
## （UiRoot 按路径记账，所以这里传打开时用的同一个路径 Paths.UI_OPTIONS）
func _on_back_pressed() -> void:
	CoreSystem.event_bus.push_event(Events.CLOSE_UI, Paths.UI_OPTIONS)


#region 改动 → 立刻写进设置档

func _on_option_selected(_index: int) -> void:
	var options: OptionsSave = SaveData.current.options if SaveData.current else null
	if options == null:
		return
	# metadata 的类型由 OptionsData 决定（Vector2i / String），与字段类型一致
	options.resolution = _resolution_option.get_selected_metadata()
	options.language = _language_option.get_selected_metadata()
	_save_options()


func _on_master_volume_changed(value: float) -> void:
	_set_volume("master_volume", value)


func _on_music_volume_changed(value: float) -> void:
	_set_volume("music_volume", value)


func _on_sfx_volume_changed(value: float) -> void:
	_set_volume("sfx_volume", value)


## 音量滑块回调：value 就是档位（滑块 step 已吸附）。
## **只有档位变化才写档** —— 同一档内的拖动只刷新显示，不落盘。
func _set_volume(field: String, step_value: float) -> void:
	var step: int = int(round(step_value))
	_update_volume_label(field, step)

	if int(_saved_steps.get(field, -1)) == step:
		return

	var options: OptionsSave = SaveData.current.options if SaveData.current else null
	if options == null:
		return
	options.set(field, OptionsData.step_to_volume(step))
	_saved_steps[field] = step
	_save_options()


## 把当前内存里的设置写进设置档。
## 写盘成功后 SaveService 会立即应用（音量 / 分辨率 / 语言 / 按键绑定），
## 所以调用方不需要自己再去碰引擎状态。
func _save_options() -> void:
	var request: Types.SaveRequest = Types.SaveRequest.new()
	request.slot = OptionsSave.SLOT
	request.reason = "options"
	CoreSystem.event_bus.push_event(Events.SAVE_REQUEST, request)

#endregion


#region 按键重映射（同样是改动即存）

## 点"暂停键"按钮：进入等待按键状态（按钮文字变成提示）
func _on_pause_key_pressed() -> void:
	_waiting_action = "pause"
	_update_key_buttons()


## 点"恢复默认"：把该动作的覆盖删掉再写档（applier 应用时会先恢复出厂绑定）
func _on_reset_key_pressed() -> void:
	var options: OptionsSave = SaveData.current.options if SaveData.current else null
	if options == null:
		return
	options.input_bindings.erase("pause")
	_save_options()
	_update_key_buttons()


## 等待期间接管输入：第一个按下的键就是新绑定；按 ESC = 放弃这次重映射（不改也不关界面）
func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty() or not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return

	var action: String = _waiting_action
	_waiting_action = ""
	if key.keycode != KEY_ESCAPE and key.physical_keycode != 0:
		var options: OptionsSave = SaveData.current.options if SaveData.current else null
		if options != null:
			options.input_bindings[action] = key.physical_keycode
			_save_options()
	_update_key_buttons()
	get_viewport().set_input_as_handled()


## 把每个动作对应的按钮找出来（按名字找，避免写长节点路径）
func _collect_key_buttons() -> void:
	for entry in OptionsData.REMAPPABLE_ACTIONS:
		var button: Button = find_child(entry["button_name"], true, false) as Button
		if button == null:
			push_warning("[Options] 找不到重映射按钮 '%s'" % entry["button_name"])
			continue
		_key_buttons[entry["action"]] = button


## 刷新按钮文字：等待按键时给提示，否则显示当前生效的按键名
func _update_key_buttons() -> void:
	for entry in OptionsData.REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		var button: Button = _key_buttons.get(action)
		if button == null:
			continue
		if _waiting_action == action:
			button.text = tr("ui.options.waiting_key")
		else:
			button.text = OS.get_keycode_string(_current_keycode(action))


## 当前生效的键码：优先存档里的覆盖，否则取 InputMap 里的默认绑定
func _current_keycode(action: String) -> int:
	var options: OptionsSave = SaveData.current.options if SaveData.current else null
	if options != null and options.input_bindings.has(action):
		return int(options.input_bindings[action])
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: InputEventKey = event
			return key.physical_keycode if key.physical_keycode != 0 else key.keycode
	return 0

#endregion


#region 填充

## 按 OptionsData 的候选值填充两个下拉框 + 三路音量滑块，并选中 / 填入内存里的当前值
func _fill_options() -> void:
	var saved: OptionsSave = SaveData.current.options if SaveData.current else null

	# 分辨率：metadata 存 Vector2i（全屏那条存 OptionsData.FULLSCREEN）
	_resolution_option.clear()
	for index in OptionsData.RESOLUTIONS.size():
		var resolution: Vector2i = OptionsData.RESOLUTIONS[index]
		_resolution_option.add_item(_format_resolution(resolution))
		_resolution_option.set_item_metadata(index, resolution)
	if OptionsData.SHOW_FULLSCREEN_OPTION:
		_resolution_option.add_item(tr("ui.options.fullscreen"))
		_resolution_option.set_item_metadata(
			_resolution_option.item_count - 1, OptionsData.FULLSCREEN)
	if _resolution_option.item_count > 0:
		_resolution_option.select(0)
	if saved and not _select_by_metadata(_resolution_option, saved.resolution):
		# 存档里的分辨率不在候选表里（窗口被手动改过 / 候选表改过）：补一条进去，
		# 这样界面显示的是真实值，下次改动也不会被兜底值悄悄覆盖
		_add_item_with_metadata(_resolution_option,
			_format_resolution(saved.resolution), saved.resolution)

	# 语言：metadata 存 locale 代码
	_language_option.clear()
	for index in OptionsData.LANGUAGES.size():
		var language: Dictionary = OptionsData.LANGUAGES[index]
		_language_option.add_item(language["name"])
		_language_option.set_item_metadata(index, language["locale"])
	if _language_option.item_count > 0:
		_language_option.select(0)
	if saved and not _select_by_metadata(_language_option, saved.language):
		_add_item_with_metadata(_language_option, saved.language, saved.language)

	# 音量：把内存里的线性值换算成档位回填。
	# set_value_no_signal：否则会触发 value_changed → 反过来又写一次档
	if saved != null:
		for entry in OptionsData.VOLUME_WIDGETS:
			var field: String = entry["field"]
			var slider: HSlider = _volume_sliders.get(field)
			if slider == null:
				continue
			var step: int = OptionsData.volume_to_step(float(saved.get(field)))
			slider.set_value_no_signal(float(step))
			_saved_steps[field] = step
			_update_volume_label(field, step)

#endregion


#region 小工具

## 按 OptionsData.VOLUME_WIDGETS 收集三路音量的滑块与数值标签
func _collect_volume_widgets() -> void:
	for entry in OptionsData.VOLUME_WIDGETS:
		var field: String = entry["field"]
		var slider: HSlider = find_child(entry["slider"], true, false) as HSlider
		var label: Label = find_child(entry["value_label"], true, false) as Label
		if slider == null or label == null:
			push_warning("[Options] 音量控件缺失：%s" % str(entry))
			continue
		_volume_sliders[field] = slider
		_volume_labels[field] = label


## 刷新某一路音量旁边显示的档位数字
func _update_volume_label(field: String, step: int) -> void:
	var label: Label = _volume_labels.get(field)
	if label != null:
		label.text = str(step)


## 补一条候选项并选中（用于"存档里的值不在候选表里"的情况）
func _add_item_with_metadata(option: OptionButton, text: String, value: Variant) -> void:
	option.add_item(text)
	option.set_item_metadata(option.item_count - 1, value)
	option.select(option.item_count - 1)


## 找出 metadata == value 的那一项并选中；返回是否找到
## （程序调用 select 不会触发 item_selected，所以填充时不会反过来触发写档）
func _select_by_metadata(option: OptionButton, value: Variant) -> bool:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return true
	return false


## 把 Vector2i 拼成下拉框里显示的文字
func _format_resolution(resolution: Vector2i) -> String:
	return "%d x %d" % [resolution.x, resolution.y]

#endregion
