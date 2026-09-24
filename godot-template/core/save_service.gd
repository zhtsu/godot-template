extends Node

## 存档服务：持有唯一一份 SaveData，把「存档事件」变成对它的读写 + 落盘纯二进制数据。
## 挂在 entry/main.tscn 上（与 UiRoot 同级）。
##
## 文件格式：4 字节魔数 "GTSV" + var_to_bytes(纯数据字典)，扩展名 .sav。
## 读回来用 bytes_to_var() —— 注意是"不解码对象"的那一版，不是 bytes_to_var_with_objects()。
## 也就是说：存档文件里就算被塞进对象 / 脚本引用，读出来也只是 null，不可能执行任何逻辑。
##
## 写入是原子的：先写 <slot>.sav.tmp，确认无误后再改名覆盖正式文件；
## 中途崩溃只会留下 .tmp，旧存档始终完整。
##
## 两类文件分开放：
##   options.sav（槽位 OptionsSave.SLOT）= 机器级设置，只有元数据 + options 段；
##   其它槽位                          = 游戏进度，元数据 + 除 options 外的所有分段。
##
## 所有请求都进同一个任务队列按顺序执行，一次 drain 有上限，剩下的下一帧继续
## （避免监听者在结果事件里继续投任务造成同一帧死循环）。
##
## 职责边界：本类管「什么时候做、以什么顺序做、对外发什么结果」；
##   - 纯文件 IO（路径 / 槽位名 / 魔数 / 原子写 / 目录枚举）→ core/save_storage.gd
##   - 把设置应用到引擎（语言 / 分辨率 / 全屏）        → core/options_applier.gd
## 两者都不持状态、不订阅事件；本类只经参数把 save_dir 与设置对象交给它们。
##
## 为什么不用 save_manager.create_save()：那套数据来源固定是「saveable 节点组 + save()」、
## 结构固定是 {metadata, nodes}，塞不下自定义的存档类。这里只借它的存档目录设置。
##
## 游戏代码两种用法：
##   1) 有引用就直接改：save_service.save_data.options.language = "zh_CN"
##   2) 没有引用就在请求里带补丁：request.data = {"options": {"language": "zh_CN"}}
## 然后 push_event(Events.SAVE_REQUEST, request)；结果听 SAVE_FINISHED。

## 纯文件 IO 模块（不加 class_name；路径经 Paths 里的常量 preload）
const SaveStorage: GDScript = preload(Paths.SCRIPT_SAVE_STORAGE)
## 设置应用模块（同上）
const OptionsApplier: GDScript = preload(Paths.SCRIPT_OPTIONS_APPLIER)

## 一次 drain 最多执行多少个任务，剩下的下一帧继续
const MAX_JOBS_PER_DRAIN: int = 16

## 唯一的存档数据对象（存档 = 序列化它）
var save_data: SaveData = SaveData.new()

## 任务队列（存 / 读 / 删 / 列表都排队执行）
var _jobs: Array[Callable] = []
var _draining: bool = false

## 存档目录（取自项目的 save_system/save_directory 设置，默认 user://saves）
var _save_dir: String = ""

## 最近一次载入被拒绝的原因（由 _prepare_load 填写）。
## 用途：结果事件的 error 必须可区分 —— "文件不存在" 与 "结构版本不兼容"
## 对调用方是两件不同的事，不能都报同一句笼统的话。
var _load_reject_reason: String = ""


func _ready() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.subscribe_unique_script(Events.SAVE_REQUEST, _on_save_request)
	event_bus.subscribe_unique_script(Events.LOAD_REQUEST, _on_load_request)
	event_bus.subscribe_unique_script(Events.DELETE_SAVE_REQUEST, _on_delete_request)
	event_bus.subscribe_unique_script(Events.SAVE_LIST_REQUEST, _on_save_list_request)

	_save_dir = CoreSystem.save_manager.save_directory
	DirAccess.make_dir_recursive_absolute(_save_dir)

	# 让各处能只读拿到当前存档（写数据仍然走事件）
	SaveData.current = save_data

	_options_ready()


func _exit_tree() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.unsubscribe(Events.SAVE_REQUEST, _on_save_request)
	event_bus.unsubscribe(Events.LOAD_REQUEST, _on_load_request)
	event_bus.unsubscribe(Events.DELETE_SAVE_REQUEST, _on_delete_request)
	event_bus.unsubscribe(Events.SAVE_LIST_REQUEST, _on_save_list_request)

	if SaveData.current == save_data:
		SaveData.current = null


#region 请求入口（只做校验 + 入队，具体干活在任务里）

## 请求存档
func _on_save_request(request: Types.SaveRequest) -> void:
	if not request:
		CoreSystem.logger.error("[SaveService] 存档请求为空")
		_emit(Events.SAVE_FINISHED, _make_result(false, "", "请求为空"))
		return
	if not SaveStorage.is_valid_slot(request.slot, true):
		CoreSystem.logger.error("[SaveService] 非法槽位名: '%s'" % request.slot)
		_emit(Events.SAVE_FINISHED, _make_result(false, request.slot, "非法槽位名", request.reason))
		return

	_enqueue(_do_save.bind(request))


## 请求读档
func _on_load_request(request: Types.LoadRequest) -> void:
	if not request or not SaveStorage.is_valid_slot(request.slot, false):
		var bad_slot: String = request.slot if request else ""
		CoreSystem.logger.error("[SaveService] 读档请求的 slot 为空或非法: '%s'" % bad_slot)
		_emit(Events.LOAD_FINISHED, _make_result(false, bad_slot, "slot 为空或非法"))
		return

	_enqueue(_do_load.bind(request))


## 请求删除存档
func _on_delete_request(request: Types.DeleteSaveRequest) -> void:
	if not request or not SaveStorage.is_valid_slot(request.slot, false):
		var bad_slot: String = request.slot if request else ""
		CoreSystem.logger.error("[SaveService] 删除存档请求的 slot 为空或非法: '%s'" % bad_slot)
		_emit(Events.DELETE_SAVE_FINISHED, _make_result(false, bad_slot, "slot 为空或非法"))
		return

	_enqueue(_do_delete.bind(request))


## 请求存档列表（无 payload），结果用 SAVE_LIST_READY 发回
func _on_save_list_request() -> void:
	_enqueue(_do_save_list)

#endregion


#region 任务队列

func _enqueue(job: Callable) -> void:
	_jobs.append(job)
	if not _draining:
		_drain_jobs()


## 顺序执行任务；一次最多 MAX_JOBS_PER_DRAIN 个，剩下的下一帧继续
func _drain_jobs() -> void:
	_draining = true
	var processed: int = 0
	while not _jobs.is_empty() and processed < MAX_JOBS_PER_DRAIN:
		var job: Callable = _jobs.pop_front()
		job.call()
		processed += 1
	_draining = false

	if not _jobs.is_empty():
		_drain_jobs.call_deferred()

#endregion


#region 具体任务

## 存档：合并补丁 → 自检 → 补元数据 → 原子写 → （设置档）立刻应用 → 发结果
func _do_save(request: Types.SaveRequest) -> void:
	if not request.data.is_empty():
		save_data.apply_dict(request.data)

	# 写入路径也跑一次自检：范围 / 白名单类问题在落盘前被兜住。
	# 与 apply_dict 的分工：类型不兼容属"调用方写错"→ 告警 + 保持原值；
	# 值不合理属"值不行"→ 由各分段的 validate() 修正。两者不合并。
	save_data.validate_tree()

	var slot: String = request.slot if not request.slot.is_empty() else SaveStorage.make_slot(_save_dir)
	var previous_slot: String = save_data.meta.slot
	_stamp(slot)

	var ok: bool = SaveStorage.write(_save_dir, slot, _payload_for(slot))
	if not ok:
		save_data.meta.slot = previous_slot
		CoreSystem.logger.error("[SaveService] 存档失败: %s" % SaveStorage.path_for(_save_dir, slot))
	elif slot == OptionsSave.SLOT:
		# 设置档写完立刻应用，改动即时生效
		_apply_options()

	var result: Types.SaveResult = _make_result(ok, slot, "" if ok else "写入失败", request.reason)
	result.metadata = save_data.metadata()
	if ok:
		result.data = save_data
	_emit(Events.SAVE_FINISHED, result)


## 读档：解码 → 校验版本 → 填回 → 自检 → 发结果
func _do_load(request: Types.LoadRequest) -> void:
	var dict: Dictionary = _prepare_load(SaveStorage.read(_save_dir, request.slot))
	var ok: bool = not dict.is_empty()
	var error: String = ""

	if ok:
		save_data.from_dict(dict)
		save_data.validate_tree()
		CoreSystem.logger.info("[SaveService] 读档成功: %s" % request.slot)
	else:
		# 用 _prepare_load 给出的可区分原因，不再用一句笼统的话
		error = _load_reject_reason if not _load_reject_reason.is_empty() else "存档不存在 / 版本不兼容 / 读取失败"
		CoreSystem.logger.error("[SaveService] 读档失败: %s（%s）" % [request.slot, error])

	var result: Types.SaveResult = _make_result(ok, request.slot, error)
	if ok:
		result.metadata = save_data.metadata()
		result.data = save_data
	_emit(Events.LOAD_FINISHED, result)


## 删档
func _do_delete(request: Types.DeleteSaveRequest) -> void:
	var path: String = SaveStorage.path_for(_save_dir, request.slot)
	var ok: bool = FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK
	if not ok:
		CoreSystem.logger.error("[SaveService] 删除存档失败: %s" % path)
	_emit(Events.DELETE_SAVE_FINISHED, _make_result(ok, request.slot, "" if ok else "删除失败"))


## 列存档（不含设置档）
func _do_save_list() -> void:
	var saves: Array[Dictionary] = []
	for slot in SaveStorage.list_slots(_save_dir, OptionsSave.SLOT):
		var dict: Dictionary = SaveStorage.read(_save_dir, slot)
		if dict.is_empty():
			continue
		# 借一个临时实例取元数据，字段表只有 SaveData 一份，不在这里重复维护
		var probe: SaveData = SaveData.new()
		probe.from_dict(dict)
		saves.append({"slot": slot, "metadata": probe.metadata()})

	# payload 是数组 → 它本身就是订阅者的参数表，所以 [saves] 让订阅者收到 saves 本身
	CoreSystem.event_bus.push_event(Events.SAVE_LIST_READY, [saves])

#endregion


#region 启动时的设置

## 设置档的启动处理：
## 有存档且能载入 → 读进来并应用；没有存档 / 载入被拒（版本不兼容、文件损坏）→
## 把**当前引擎状态**当成默认值写进内存，让"界面显示的选择"和"实际生效的值"始终一致
## （否则会出现界面显示 English、实际界面是中文这种情况）。
func _options_ready() -> void:
	if FileAccess.file_exists(SaveStorage.path_for(_save_dir, OptionsSave.SLOT)):
		if _autoload_options():
			return
		CoreSystem.logger.warning("[SaveService] 设置档无法载入，按首次运行处理：以当前引擎状态作为设置默认值")

	_seed_options_from_engine()


## 当前引擎状态 → 内存设置值（首次运行 / 设置档不可用时的兜底）
func _seed_options_from_engine() -> void:
	save_data.options.language = TranslationServer.get_locale()
	var window_size: Vector2i = DisplayServer.window_get_size()
	if window_size.x > 0 and window_size.y > 0:
		save_data.options.resolution = window_size
	CoreSystem.logger.info("[SaveService] 以当前引擎状态作为设置默认值（%s / %s）"
		% [save_data.options.resolution, save_data.options.language])


## 启动时读设置存档并应用；返回是否成功载入
func _autoload_options() -> bool:
	var dict: Dictionary = _prepare_load(SaveStorage.read(_save_dir, OptionsSave.SLOT))
	if dict.is_empty():
		return false

	save_data.from_dict(dict)
	save_data.validate_tree()
	_apply_options()
	CoreSystem.logger.info("[SaveService] 已读入并应用设置存档: %s" % OptionsSave.SLOT)

	var result: Types.SaveResult = _make_result(true, OptionsSave.SLOT, "", "options")
	result.metadata = save_data.metadata()
	result.data = save_data
	_emit(Events.LOAD_FINISHED, result)
	return true


## 把存档里的设置应用到引擎（具体动作在 options_applier.gd；这里只管救场与日志）
func _apply_options() -> void:
	var options: OptionsSave = save_data.options
	if options == null:
		# 正常不会发生（from_dict 会拒绝把分段设成 null），这里兜一手
		CoreSystem.logger.error("[SaveService] options 段丢失，已重建默认值")
		save_data.options = OptionsSave.new()
		options = save_data.options

	OptionsApplier.apply(options)
	CoreSystem.logger.info("[SaveService] 已应用设置：resolution=%s language=%s"
		% [options.resolution, TranslationServer.get_locale()])

#endregion


#region 内部实现

## 要写进文件的字典（v2 起两类存档都是"version + meta + 各自的分段"）。
## 设置档 = version + meta + options；其它槽位 = version + meta + 除 options 外的所有分段
## （机器级设置不跟着游戏存档跑）。
func _payload_for(slot: String) -> Dictionary:
	if slot == OptionsSave.SLOT:
		return save_data.to_dict()

	var game_payload: Dictionary = save_data.to_dict()
	game_payload.erase("options")
	return game_payload


## 读出"可以载入的字典"；返回空 = 拒绝载入（文件不存在 / 版本比程序新 / 迁移失败）。
## 被拒时把**可区分的原因**写进 _load_reject_reason，调用方用它填 result.error。
## 注意：返回的可能是 migrate() 产生的新字典，所以调用方必须用返回值，
## 千万不要再去 clear 原来的 dict（migrate 默认就是原样返回同一个对象，原地清会把数据清没）。
func _prepare_load(dict: Dictionary) -> Dictionary:
	_load_reject_reason = ""

	if dict.is_empty():
		_load_reject_reason = "存档不存在或读取失败"
		return {}

	var file_version: int = int(dict.get("version", 0))
	if file_version == save_data.version:
		return dict

	if file_version > save_data.version:
		_load_reject_reason = "存档结构版本 %d 比当前程序 %d 新，请用新版程序打开" % [file_version, save_data.version]
		CoreSystem.logger.error("[SaveService] %s" % _load_reject_reason)
		return {}

	CoreSystem.logger.warning("[SaveService] 存档版本 %d 较旧（当前 %d），尝试迁移后载入"
		% [file_version, save_data.version])

	var migrated: Dictionary = save_data.migrate(dict, file_version)
	if migrated.is_empty():
		_load_reject_reason = "存档结构版本 %d 过旧，本版本不提供迁移（当前结构版本 %d）" % [file_version, save_data.version]
		CoreSystem.logger.error("[SaveService] %s" % _load_reject_reason)
		return {}

	migrated["version"] = save_data.version
	return migrated


## 写盘前补齐由服务负责的元数据（v2 起元数据在 meta 分段里）
func _stamp(slot: String) -> void:
	save_data.meta.slot = slot
	save_data.meta.saved_at = Time.get_datetime_string_from_system()
	save_data.meta.game_version = str(ProjectSettings.get_setting("application/config/version", ""))


## 组装结果对象
func _make_result(ok: bool, slot: String, error: String = "", reason: String = "manual") -> Types.SaveResult:
	var result: Types.SaveResult = Types.SaveResult.new()
	result.ok = ok
	result.slot = slot
	result.reason = reason
	result.error = error
	return result


## 发送结果事件
func _emit(event_name: String, result: Types.SaveResult) -> void:
	CoreSystem.event_bus.push_event(event_name, result)

#endregion
