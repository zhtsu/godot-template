extends CanvasLayer

@onready var bottom_layer: CanvasLayer = $Bottom
@onready var middle_layer: CanvasLayer = $Middle
@onready var top_layer: CanvasLayer = $Top

# 已经打开的 UI 实例
var ui_dict: Dictionary = {}


func _ready() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.subscribe_unique_script(Events.OPEN_UI, _open_ui)
	event_bus.subscribe_unique_script(Events.CLOSE_UI, _close_ui)


func _exit_tree() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.unsubscribe(Events.OPEN_UI, _open_ui)
	event_bus.unsubscribe(Events.CLOSE_UI, _close_ui)


func _on_open_ui_event(request: Types.OpenUiRequest) -> void:
	_open_ui(request)


func _on_close_ui_event(ui_path: String) -> void:
	_close_ui(ui_path)


func _open_ui(request: Types.OpenUiRequest) -> void:
	if not request.path:
		CoreSystem.logger.error("[UiRoot] 打开 UI 请求的路径为空")
		return

	if ui_dict.has(request.path):
		CoreSystem.logger.warning("[UiRoot] UI 已经打开过，清理已经打开的实例: %s" % request.path)
		_close_ui(request.path)

	var packed_scene: PackedScene = CoreSystem.resource_manager.load_resource(request.path) as PackedScene
	if not packed_scene:
		CoreSystem.logger.error("[UiRoot] 无法加载 UI 场景: %s" % request.path)
		return

	var ui_node: Node = packed_scene.instantiate()
	if not ui_node:
		CoreSystem.logger.error("[UiRoot] 无法实例化 UI 场景: %s" % request.path)
		return

	match request.ui_layer:
		Types.UiLayer.BOTTOM:
			bottom_layer.add_child(ui_node)
		Types.UiLayer.MIDDLE:
			middle_layer.add_child(ui_node)
		Types.UiLayer.TOP:
			top_layer.add_child(ui_node)

	ui_dict[request.path] = ui_node


func _close_ui(ui_path: String) -> void:
	if not ui_dict.has(ui_path):
		CoreSystem.logger.warning("[UiRoot] UI 未打开: %s" % ui_path)
		return

	var ui_node: Node = ui_dict[ui_path]
	if ui_node:
		ui_node.queue_free()
		ui_dict.erase(ui_path)
