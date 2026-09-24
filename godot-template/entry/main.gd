extends Node


func _ready() -> void:
    var request: Types.OpenUiRequest = Types.OpenUiRequest.new()
    request.path = Paths.UI_MAIN_MENU
    CoreSystem.event_bus.push_event(Events.OPEN_UI, request)