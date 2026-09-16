class_name OptionsSave
extends SaveSection

## 设置界面选中的项。候选列表（能选哪些）在 core/options_data.gd，这里只存"选了哪个"。

## 这些设置单独占一个存档槽位，不和游戏进度混在一起
const SLOT: String = "options"

## 默认值（同时也是"存档里数值非法"时的兜底值）。
## 注意是真实分辨率，不要用 FULLSCREEN 哨兵 —— 否则首次运行会出现
## "界面显示全屏、实际窗口化"，而且第一次改设置就会把全屏写进档。
const DEFAULT_RESOLUTION: Vector2i = Vector2i(1152, 648)
const DEFAULT_LANGUAGE: String = "en"

## 选中的分辨率；OptionsData.FULLSCREEN（Vector2i.ZERO）表示「全屏」
var resolution: Vector2i = DEFAULT_RESOLUTION
## 选中的语言代码，对应 locale/*.po（如 "en" / "zh_CN"）
var language: String = DEFAULT_LANGUAGE


## 自检：分辨率必须是候选表里的值（或全屏哨兵），语言必须在支持列表里。
## 存档被改坏 / 候选表被改过时，这里会把非法值改回默认，避免把垃圾值喂给引擎。
func validate() -> void:
	if resolution != OptionsData.FULLSCREEN and not OptionsData.RESOLUTIONS.has(resolution):
		push_warning("[OptionsSave] 分辨率 %s 不在候选表里，改回默认 %s" % [resolution, DEFAULT_RESOLUTION])
		resolution = DEFAULT_RESOLUTION

	if not _is_supported_language(language):
		push_warning("[OptionsSave] 语言 '%s' 不受支持，改回默认 '%s'" % [language, DEFAULT_LANGUAGE])
		language = DEFAULT_LANGUAGE


func _is_supported_language(locale: String) -> bool:
	for entry in OptionsData.LANGUAGES:
		if str(entry.get("locale", "")) == locale:
			return true
	return false
