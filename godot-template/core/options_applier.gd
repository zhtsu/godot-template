extends RefCounted

## 把设置**应用到引擎**（纯函数式：不持状态、不订阅事件、不读存档、不认识事件 / 结果类型）。
##
## 约束（FR-008，见 specs/001-core-save-refactor/data-model.md §5.3）：
##   - 只做"内存值 → 引擎状态"这一步；"什么时候应用"由 core/save_service.gd 决定
##   - **不加 class_name**：由 core/save_service.gd 经 Paths.SCRIPT_OPTIONS_APPLIER 用 preload 引用
##   - 设置项以后增加时改这里，调用方不需要动
##
## 项目特有的部分就是这里；core/ 的其它地方 SHOULD NOT 直接调 DisplayServer / TranslationServer。

## 应用设置：语言 + 分辨率（含全屏）
static func apply(options: OptionsSave) -> void:
	if options == null:
		return

	# 语言
	if TranslationServer.get_locale() != options.language:
		TranslationServer.set_locale(options.language)

	# 分辨率：OptionsData.FULLSCREEN（Vector2i.ZERO）代表全屏
	if options.resolution == OptionsData.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(options.resolution)
