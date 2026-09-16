extends Control

## 主菜单：按钮只负责发事件，实际动作交给对应系统
## （和 entry/main.gd 打开主菜单是同一套写法）。

@onready var _options_button: Button = $MenuList/OptionsButton


func _ready() -> void:
	_options_button.pressed.connect(_on_options_pressed)


## 打开设置界面：发 OPEN_UI 事件，由 UiRoot 负责实例化并挂到对应层
func _on_options_pressed() -> void:
	var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
	request.path = Paths.UI_OPTIONS
	CoreSystem.event_bus.push_event(Events.OPEN_UI, request)
