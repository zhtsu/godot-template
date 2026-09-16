class_name Types

## 项目所有自定义枚举与结构体的集中定义。

enum UiLayer { BOTTOM, MIDDLE, TOP }

class OpenUiRequest:
    var path: String
    var ui_layer: int = UiLayer.MIDDLE
    var data: Dictionary = {}

# ===== 存档 =====

class SaveRequest:
    ## 存档槽位 ID，留空则自动生成 save_<时间戳>
    var slot: String = ""
    ## 存档原因：manual / quick / auto / checkpoint，方便监听者用 filter 过滤
    var reason: String = "manual"
    ## 可选的字段补丁：写盘前由 SaveService 合并进 SaveData（不方便持有它的调用方用）
    var data: Dictionary = {}

class LoadRequest:
    ## 存档槽位 ID
    var slot: String

class DeleteSaveRequest:
    ## 存档槽位 ID
    var slot: String

class SaveResult:
    ## 操作是否成功
    var ok: bool = false
    ## 实际的存档槽位 ID（请求里留空时，这里是自动生成的那个）
    var slot: String = ""
    ## 原样带回请求里的 reason，便于结果订阅者过滤
    var reason: String = "manual"
    ## 失败原因，成功时为空
    var error: String = ""
    ## 存档元数据（version / slot / saved_at / game_version / playtime）
    var metadata: Dictionary = {}
    ## 当前的内存存档对象：存档成功 / 读档成功时都有值，监听者可直接取用
    var data: SaveData = null