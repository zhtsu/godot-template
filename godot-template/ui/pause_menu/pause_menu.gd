extends Control

## 暂停界面。两条要点：
##   1) 不自己改 `get_tree().paused` —— 暂停状态的唯一权威是 core/game_flow.gd，
##      这里只发事件（继续 = PAUSE_TOGGLE，返回标题 = RETURN_TO_TITLE）；
##   2) 场景根节点的 process_mode 已设为 ALWAYS（见 pause_menu.tscn），
##      否则树一暂停，这里的按钮就点不动了。

func _on_resume_pressed() -> void:
	CoreSystem.event_bus.push_event(Events.PAUSE_TOGGLE)


func _on_return_to_title_pressed() -> void:
	CoreSystem.event_bus.push_event(Events.RETURN_TO_TITLE)
