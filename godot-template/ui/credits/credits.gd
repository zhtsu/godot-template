extends Control

## 制作人员界面：和设置界面一样，只经事件开与关（关闭由 UiRoot 按路径记账）。

func _on_back_pressed() -> void:
	CoreSystem.event_bus.push_event(Events.CLOSE_UI, Paths.UI_CREDITS)
