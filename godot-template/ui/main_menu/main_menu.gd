extends Control

## 主菜单：按钮只负责发事件，实际动作交给对应系统。
##
## 按钮的 pressed 信号在 main_menu.tscn 里用 [connection] 连接（引擎自己写的那种），
## 所以这里不需要 `$MenuList/XXX` 这种长节点路径 —— 节点改名不会等到运行时才崩。

## 开始游戏：只发"开始"，关主菜单 + 转场 + 换场景都由 core/game_flow.gd 负责
func _on_start_pressed() -> void:
	CoreSystem.event_bus.push_event(Events.START_GAME, Paths.GAME_EXAMPLE_LEVEL)


## 打开设置界面：发 OPEN_UI，由 UiRoot 负责实例化并挂到对应层
func _on_options_pressed() -> void:
	var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
	request.path = Paths.UI_OPTIONS
	CoreSystem.event_bus.push_event(Events.OPEN_UI, request)


## 制作人员
func _on_credits_pressed() -> void:
	var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
	request.path = Paths.UI_CREDITS
	CoreSystem.event_bus.push_event(Events.OPEN_UI, request)


## 退出游戏：直接退。
## 模板不自动保存；真项目若要"退出前保存"，在这里发 SAVE_REQUEST 并在结果事件里再 quit。
func _on_quit_pressed() -> void:
	get_tree().quit()
