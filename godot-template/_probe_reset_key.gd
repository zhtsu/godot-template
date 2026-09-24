extends SceneTree

## 一次性探针：暂停键重映射的**按钮文本**刷新。用完即删。
## 覆盖：
##   1) 初始：按钮显示当前绑定（Escape）
##   2) 改成空格：按钮显示 Space
##   3) 点「恢复默认」：按钮必须回到 Escape（用户报告的问题）
##   4) 边界：处于"请按键…"等待状态时点「恢复默认」，按钮也必须回到 Escape（不能卡在提示文字）
##
## 用法：pwsh scripts/verify-engine.ps1 -Probe res://_probe_reset_key.gd

const MAIN_SCENE: String = "res://entry/main.tscn"
const PROBE_SAVE_DIR: String = "res://_probe_saves"
const SETTING_SAVE_DIR: String = "godot_core_system/save_system/save_directory"

var _pass: int = 0
var _fail: int = 0
var _stage: int = 0
var _wait_until_ms: int = 0
var _finished: bool = false
var _bus: Node = null
var _main: Node = null
var _ui_root: Node = null


func _initialize() -> void:
	print("=== PROBE RESET KEY: button label after reset-to-default ===")


func _process(_delta: float) -> bool:
	if _finished:
		return true
	if Time.get_ticks_msec() < _wait_until_ms:
		return false

	match _stage:
		0:
			_setup()
			_wait_ms(200)
		1:
			_open_options()
			_wait_ms(200)
		2:
			_check_label("初始", _escape_text())
			print("--- 点「暂停键」→ 按空格 ---")
			_press("PauseKeyButton")
			Input.parse_input_event(_key_event(KEY_SPACE))
			_wait_ms(250)
		3:
			_check_label("改键后", OS.get_keycode_string(KEY_SPACE))
			print("--- 点「恢复默认」 ---")
			_press("ResetKeyButton")
			_wait_ms(250)
		4:
			_check_label("恢复默认后", _escape_text())
			print("--- 边界：点「暂停键」进入等待，再点「恢复默认」 ---")
			_press("PauseKeyButton")
			_wait_ms(150)
			_press("ResetKeyButton")
			_wait_ms(250)
		5:
			_check_label("等待中点恢复默认后", _escape_text())
			_finish()
			return true
	return false


# --- 流程 ---------------------------------------------------------------

func _wait_ms(ms: int) -> void:
	_wait_until_ms = Time.get_ticks_msec() + ms
	_stage += 1


func _setup() -> void:
	_remove_probe_dir()
	DirAccess.make_dir_recursive_absolute(PROBE_SAVE_DIR)
	ProjectSettings.set_setting(SETTING_SAVE_DIR, PROBE_SAVE_DIR)

	var core: Node = root.get_node_or_null("/root/CoreSystem")
	_bus = core.get("event_bus") if core != null else null
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	_ui_root = _main.get_node_or_null("UiRoot")
	if _bus == null or _ui_root == null:
		_fail_line("main.tscn 缺 CoreSystem / UiRoot")
		return
	print("--- 已实例化 main.tscn（首次运行，无设置档）---")


func _open_options() -> void:
	var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
	request.path = Paths.UI_OPTIONS
	request.ui_layer = Types.UiLayer.MIDDLE
	_bus.push_event(Events.OPEN_UI, request)


func _press(button_name: String) -> void:
	var button: Button = _main.find_child(button_name, true, false) as Button
	if button == null:
		_fail_line("找不到按钮 %s" % button_name)
		return
	button.pressed.emit()


func _key_event(code: int) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _escape_text() -> String:
	return OS.get_keycode_string(KEY_ESCAPE)


func _key_button_text() -> String:
	var button: Button = _main.find_child("PauseKeyButton", true, false) as Button
	return button.text if button != null else "<找不到按钮>"


# --- 断言 ---------------------------------------------------------------

func _check_label(when: String, expected: String) -> void:
	var actual: String = _key_button_text()
	if actual == expected:
		_pass_line("%s按钮文本 = '%s'" % [when, actual])
	else:
		_fail_line("%s按钮文本 = '%s'，期望 '%s'" % [when, actual, expected])


# --- 辅助 ---------------------------------------------------------------

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_remove_probe_dir()
	print("--- 结果：PASS=%d FAIL=%d ---" % [_pass, _fail])
	print("PROBE_RESET_KEY_RESULT=%s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _remove_probe_dir() -> void:
	var dir: DirAccess = DirAccess.open(PROBE_SAVE_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(PROBE_SAVE_DIR)


func _pass_line(message: String) -> void:
	_pass += 1
	print("  [PASS] %s" % message)


func _fail_line(message: String) -> void:
	_fail += 1
	print("  [FAIL] %s" % message)
