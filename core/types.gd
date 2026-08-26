class_name Types

## 项目所有自定义枚举与结构体的集中定义。

enum UiLayer { BOTTOM, MIDDLE, TOP }

class OpenUiRequest:
    var path: String
    var ui_layer: int = UiLayer.MIDDLE
    var data: Dictionary = {}