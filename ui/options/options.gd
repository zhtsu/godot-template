extends Control

## 设置界面：候选值来自 core/options_data.gd，选完立刻写进设置存档（槽位 OptionsSave.SLOT），
## 落盘和应用都由 SaveService 负责。

@onready var _resolution_option: OptionButton = $Rows/RowResolution/ResolutionOption
@onready var _language_option: OptionButton = $Rows/RowLanguageSelect/LanguageOption
@onready var _back_button: Button = $BackButton


func _ready() -> void:
	_fill_options()
	_resolution_option.item_selected.connect(_on_option_selected)
	_language_option.item_selected.connect(_on_option_selected)
	_back_button.pressed.connect(_on_back_pressed)


## 切语言后 Godot 会发这个通知：重填一遍下拉框（"全屏"那条是 tr() 出来的，需要刷新）。
## _fill_options 会按存档里的值重新选中，所以不会丢掉用户的选择。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _resolution_option != null:
		_fill_options()


## 返回：发 CLOSE_UI 事件交给 UiRoot 关闭自己
## （UiRoot 按路径记账，所以这里传打开时用的同一个路径 Paths.UI_OPTIONS）
func _on_back_pressed() -> void:
	CoreSystem.event_bus.push_event(Events.CLOSE_UI, Paths.UI_OPTIONS)


## 用户改了任一下拉框：把当前两个值一起写进设置存档（只发事件，落盘/应用交给 SaveService）
func _on_option_selected(_index: int) -> void:
	var request: Types.SaveRequest = Types.SaveRequest.new()
	request.slot = OptionsSave.SLOT
	request.reason = "options"
	request.data = {
		"options": {
			"resolution": _resolution_option.get_selected_metadata(),
			"language": _language_option.get_selected_metadata(),
		},
	}
	CoreSystem.event_bus.push_event(Events.SAVE_REQUEST, request)


## 按 OptionsData 的候选值填充两个下拉框，并选中存档里当前的值
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


## 补一条候选项并选中（用于"存档里的值不在候选表里"的情况）
func _add_item_with_metadata(option: OptionButton, text: String, value: Variant) -> void:
	option.add_item(text)
	option.set_item_metadata(option.item_count - 1, value)
	option.select(option.item_count - 1)


## 找出 metadata == value 的那一项并选中；返回是否找到
## （程序调用 select 不会触发 item_selected，所以填充时不会反过来触发存档）
func _select_by_metadata(option: OptionButton, value: Variant) -> bool:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return true
	return false


## 把 Vector2i 拼成下拉框里显示的文字
func _format_resolution(resolution: Vector2i) -> String:
	return "%d x %d" % [resolution.x, resolution.y]
