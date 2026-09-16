extends CanvasLayer

@onready var bottom_layer: CanvasLayer = $Bottom
@onready var middle_layer: CanvasLayer = $Middle
@onready var top_layer: CanvasLayer = $Top

# 已经打开的 UI 实例（key: 场景路径）
var ui_dict: Dictionary = {}


func _ready() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.subscribe_unique_script(Events.OPEN_UI, _open_ui)
	event_bus.subscribe_unique_script(Events.CLOSE_UI, _close_ui)


func _exit_tree() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.unsubscribe(Events.OPEN_UI, _open_ui)
	event_bus.unsubscribe(Events.CLOSE_UI, _close_ui)


func _open_ui(request: Types.OpenUiRequest) -> void:
	if not request.path:
		CoreSystem.logger.error("[UiRoot] 打开 UI 请求的路径为空")
		return

	# 已经打开过就重建；ui_dict 里可能留着已被释放的实例，交给 _close_ui 处理
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
		_:
			# ui_layer 是普通 int，写错了也要有个明确归宿，不能实例化了却不入树
			CoreSystem.logger.warning("[UiRoot] 未知的 UI 层级 %d，按 MIDDLE 处理" % request.ui_layer)
			middle_layer.add_child(ui_node)

	ui_dict[request.path] = ui_node

	# UI 自己离开场景树（自己 queue_free / 父节点被释放）时自动清掉记录，
	# 否则 ui_dict 会留下悬空引用，下次打开同一路径就会报错
	ui_node.tree_exited.connect(_on_ui_tree_exited.bind(request.path))


func _close_ui(ui_path: String) -> void:
	if not ui_dict.has(ui_path):
		CoreSystem.logger.warning("[UiRoot] UI 未打开: %s" % ui_path)
		return

	# 先摘记录再释放。用 Variant 接：把"已被释放的实例"赋给 Node 类型会直接报脚本错误
	var ui_node: Variant = ui_dict[ui_path]
	ui_dict.erase(ui_path)
	if is_instance_valid(ui_node):
		ui_node.queue_free()


## UI 离开场景树时清理记录
func _on_ui_tree_exited(ui_path: String) -> void:
	var ui_node: Variant = ui_dict.get(ui_path)
	if ui_node == null:
		return

	# 只有"记录里还是那个已经离开树的实例"才清；
	# 若是重新打开的新实例（还在树里），保留记录
	if not is_instance_valid(ui_node) or not ui_node.is_inside_tree():
		ui_dict.erase(ui_path)
