class_name Events

## 项目所有事件名的集中管理（配合 CoreSystem.event_bus 使用）。

# ===== UI 事件 =====
const OPEN_UI: String =     "open_ui"
const CLOSE_UI: String =    "close_ui"

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