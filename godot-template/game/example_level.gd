extends Node2D

## 模板自带的最小示例关卡。
##
## 游戏项目把这个场景换掉即可（core/paths.gd 的 GAME_EXAMPLE_LEVEL 指向它）。
## 暂停（ESC）与"返回标题"都由 core/game_flow.gd 统一处理，关卡内不需要写这些逻辑；
## 关卡自己只关心玩法。

func _ready() -> void:
	CoreSystem.logger.info("[ExampleLevel] 示例关卡已加载（按 ESC 暂停）")
