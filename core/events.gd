class_name Events

## 项目所有事件名的集中管理（配合 CoreSystem.event_bus 使用）。
##
## 负载（payload）语义 —— 完整契约见
## specs/001-core-save-refactor/contracts/event-payload-contract.md：
##   `push_event(name, payload)` 的 payload **就是订阅者的参数表**（内部走 callv）：
##     非数组     → 自动包成单元素参数表 → 订阅者收到 1 个参数（该对象本身）
##     单元素数组 → 订阅者收到 1 个参数：数组里那个元素本身（**不是**嵌套数组）
##     多元素数组 → 按位置展开成 N 个参数
##     空数组 []  → 0 个参数
##   因此"想传一个数组作为单个参数"就直接传该数组（`push_event(N, items)`），
##   **不要**再包一层（`[[items]]` 会让订阅者收到嵌套数组）。
##   该语义已由探针 `_probe_us2.gd`（SCR-5）实测固化，不要靠推理。

## 事件没有返回值 → 一律"请求事件 + 结果事件"配对，结果里 MUST 处理 ok == false。

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