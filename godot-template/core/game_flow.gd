extends Node

## 游戏流程（常驻壳架构）：
##   boot（entry/main.tscn，本节点所在场景）
##     → title（主菜单，UiRoot 的 MIDDLE 层）
##     → gameplay（关卡场景挂进自己的 SceneRoot）
##     → pause（暂停界面，UiRoot 的 TOP 层；`get_tree().paused = true`）
##
## 为什么不是"整场景切换"：本节点与 UiRoot / SaveService 一起挂在 entry/main.tscn 上，
## 切关卡只替换 SceneRoot 里的内容 —— 存档状态、已打开的界面都不受切场景影响。
## 框架的 `CoreSystem.scene_manager` 是"替换 current_scene"的用法（会把这层壳一起 queue_free），
## 所以这里不用它的切换逻辑；但**转场动画复用了它的 `FadeTransition`**，没有自己重写一遍 tween。
##
## 两条与暂停有关的硬要求：
##   1) 本节点 `process_mode = ALWAYS` —— 否则暂停后收不到 ESC，就再也恢复不了；
##   2) 暂停界面自身也要在暂停中可交互（见 ui/pause_menu/pause_menu.tscn 的 process_mode）。
##
## 暂停状态的**唯一权威是本节点**：暂停界面上的按钮只发事件，不自己改 `get_tree().paused`。

## 与 project.godot 的 [input] 段同名（改按键或做重映射时两处要一起动）
const ACTION_PAUSE: String = "pause"
## 转场时长（秒）
const FADE_DURATION: float = 0.25

## 关卡场景的挂载点（本节点的子节点，见 entry/main.tscn）
@onready var _scene_root: Node = $SceneRoot

var _bus: Node = null
var _transition: BaseTransition = null
var _transition_rect: ColorRect = null
## 当前关卡实例（没有 = 在标题界面）
var _current_level: Node = null
## 转场动画期间为 true，用来挡住重复的切换请求
var _switching: bool = false


func _ready() -> void:
	# 暂停时也要继续跑：ESC 的监听与本节点在同一处
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_transition()

	_bus = CoreSystem.event_bus
	_bus.subscribe_unique_script(Events.START_GAME, _on_start_game)
	_bus.subscribe_unique_script(Events.RETURN_TO_TITLE, _on_return_to_title)
	_bus.subscribe_unique_script(Events.PAUSE_TOGGLE, _on_pause_toggle)


func _exit_tree() -> void:
	if _bus == null:
		return
	_bus.unsubscribe(Events.START_GAME, _on_start_game)
	_bus.unsubscribe(Events.RETURN_TO_TITLE, _on_return_to_title)
	_bus.unsubscribe(Events.PAUSE_TOGGLE, _on_pause_toggle)


## ESC 在这里统一处理：发事件而不是直接改状态，保持"暂停权威只有一处"
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_PAUSE):
		get_viewport().set_input_as_handled()
		_bus.push_event(Events.PAUSE_TOGGLE)


#region 流程动作

## 开始游戏：关主菜单 → 淡黑 → 换关卡 → 淡回
func _on_start_game(level_path: String) -> void:
	if _switching:
		return
	_switching = true
	CoreSystem.event_bus.push_event(Events.CLOSE_UI, Paths.UI_MAIN_MENU)

	await _fade_out()
	_free_current_level()

	var packed: PackedScene = CoreSystem.resource_manager.load_resource(level_path) as PackedScene
	if packed == null:
		CoreSystem.logger.error("[GameFlow] 无法加载关卡场景: %s" % level_path)
		await _fade_in()
		_switching = false
		return

	_current_level = packed.instantiate()
	_scene_root.add_child(_current_level)
	CoreSystem.logger.info("[GameFlow] 进入关卡: %s" % level_path)
	await _fade_in()
	_switching = false


## 回到标题：恢复暂停 → 关暂停界面 → 淡黑 → 释放关卡 → 打开主菜单 → 淡回
func _on_return_to_title() -> void:
	if _switching:
		return
	_switching = true

	if get_tree().paused:
		get_tree().paused = false
		CoreSystem.event_bus.push_event(Events.CLOSE_UI, Paths.UI_PAUSE_MENU)

	await _fade_out()
	_free_current_level()

	var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
	request.path = Paths.UI_MAIN_MENU
	request.ui_layer = Types.UiLayer.MIDDLE
	CoreSystem.event_bus.push_event(Events.OPEN_UI, request)
	CoreSystem.logger.info("[GameFlow] 回到标题")

	await _fade_in()
	_switching = false


## 暂停 / 恢复。ESC 与暂停界面上的按钮都走到这里。
func _on_pause_toggle() -> void:
	# 不在关卡里（标题界面）或正在切场景时，ESC 不生效
	if _current_level == null or _switching:
		return

	var will_pause: bool = not get_tree().paused
	get_tree().paused = will_pause

	if will_pause:
		var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
		request.path = Paths.UI_PAUSE_MENU
		request.ui_layer = Types.UiLayer.TOP
		CoreSystem.event_bus.push_event(Events.OPEN_UI, request)
		CoreSystem.logger.info("[GameFlow] 已暂停")
	else:
		CoreSystem.event_bus.push_event(Events.CLOSE_UI, Paths.UI_PAUSE_MENU)
		CoreSystem.logger.info("[GameFlow] 已继续")

#endregion


#region 内部实现

## 转场遮罩：一个盖住全部 UI 的 CanvasLayer + ColorRect，动画借框架的 FadeTransition
func _setup_transition() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	# 与框架 scene_manager 的转场层同层号：保证盖在任何界面之上
	layer.layer = 128
	add_child(layer)

	_transition_rect = ColorRect.new()
	_transition_rect.color = Color(0, 0, 0, 0)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.size = get_viewport().get_visible_rect().size
	layer.add_child(_transition_rect)
	get_viewport().size_changed.connect(_resize_transition_rect)

	_transition = FadeTransition.new()
	_transition.init(_transition_rect)


func _resize_transition_rect() -> void:
	if _transition_rect != null:
		_transition_rect.size = get_viewport().get_visible_rect().size


## 变黑（切场景前）
func _fade_out() -> void:
	_transition_rect.visible = true
	await _transition.start(FADE_DURATION)


## 变亮（切场景后）
func _fade_in() -> void:
	await _transition.end(FADE_DURATION)
	_transition_rect.visible = false


func _free_current_level() -> void:
	if _current_level == null:
		return
	_current_level.queue_free()
	_current_level = null

#endregion
