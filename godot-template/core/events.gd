class_name Events

## 项目所有事件名的集中管理（配合 CoreSystem.event_bus 使用）。
##
## 负载（payload）语义（下面这套规则已在引擎里实测过，不要靠推理）：
##   `push_event(name, payload)` 的 payload **就是订阅者的参数表**（内部走 callv）：
##     非数组     → 自动包成单元素参数表 → 订阅者收到 1 个参数（该对象本身）
##     单元素数组 → 订阅者收到 1 个参数：数组里那个元素本身（**不是**嵌套数组）
##     多元素数组 → 按位置展开成 N 个参数
##     空数组 []  → 0 个参数
##   因此"想传一个数组作为单个参数"就直接传该数组（`push_event(N, items)`），
##   **不要**再包一层（`[[items]]` 会让订阅者收到嵌套数组）。

## 事件没有返回值 → 一律"请求事件 + 结果事件"配对，结果里 MUST 处理 ok == false。

# ===== UI 事件 =====
const OPEN_UI: String =     "open_ui"
const CLOSE_UI: String =    "close_ui"

# ===== 游戏流程事件 =====
## 开始游戏（payload: 关卡场景路径 String，取值来自 core/paths.gd）
const START_GAME: String =       "start_game"
## 回到标题界面（无 payload）
const RETURN_TO_TITLE: String =  "return_to_title"
## 暂停 / 恢复切换（无 payload）。暂停状态的唯一权威是 core/game_flow.gd：
## 暂停界面上的按钮也发这个事件，而不是自己去改 get_tree().paused
const PAUSE_TOGGLE: String =     "pause_toggle"

# ===== 存档事件 =====
## 请求存档（payload: Types.SaveRequest）
const SAVE_REQUEST: String =        "save_request"
## 请求读档（payload: Types.LoadRequest）
const LOAD_REQUEST: String =        "load_request"
## 请求删除存档（payload: Types.DeleteSaveRequest）
const DELETE_SAVE_REQUEST: String = "delete_save_request"
## 请求存档列表，无 payload
const SAVE_LIST_REQUEST: String =   "save_list_request"
## 存档结束（payload: Types.SaveResult）
const SAVE_FINISHED: String =       "save_finished"
## 读档结束（payload: Types.SaveResult）
const LOAD_FINISHED: String =       "load_finished"
## 删档结束（payload: Types.SaveResult）
const DELETE_SAVE_FINISHED: String = "delete_save_finished"
## 存档列表就绪（payload: Array[Dictionary]，注意载荷是数组，订阅时收一个参数）
const SAVE_LIST_READY: String =     "save_list_ready"