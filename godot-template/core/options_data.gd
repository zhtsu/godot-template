class_name OptionsData

## 设置界面（Options）的可配置数据。
## 只改这个文件，运行时两个下拉框就会显示对应条目；
## 显示文字由 ui/options/options.gd 在填充时拼接。

## 分辨率下拉框的候选值（Vector2i，显示时拼成 "1152 x 648"）
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),
	Vector2i(1152, 648),
	Vector2i(1920, 1080),
]

## 是否在分辨率下拉框最底下追加一条「全屏」
## 显示文字取翻译键 ui.options.fullscreen，选中时 metadata 是 FULLSCREEN
const SHOW_FULLSCREEN_OPTION: bool = true

## 「全屏」那一项在 metadata 里的标记值（Vector2i.ZERO 不是有效分辨率）
const FULLSCREEN: Vector2i = Vector2i.ZERO

## 语言下拉框的候选值。
## locale 是 TranslationServer 用的语言代码（对应 locale/*.po），name 是下拉框里显示的文字。
const LANGUAGES: Array[Dictionary] = [
	{"locale": "en", "name": "English"},
	{"locale": "zh_CN", "name": "简体中文"},
]
